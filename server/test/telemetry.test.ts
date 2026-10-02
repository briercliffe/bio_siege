import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { setClockForTests } from "../src/clock";
import { CONTENT_HASH } from "../src/generated/data";
import { rpcWorkerClaim, rpcWorkerComplete } from "../src/jobs";
import { registerProfileHandlers, rpcProfileGet } from "../src/profile";
import { RAID_SECONDS, registerRaidHandlers, rpcRaidStart, rpcRaidSubmit } from "../src/raids";
import { dayIndex } from "../src/retention";
import { ACTIVE_USERS_CAP, TELEMETRY_COLLECTION, dayKey, recordRaid, rpcAdminReport } from "../src/telemetry";
import { FakeLogger, FakeNk, asLogger, asNk, fakeCtx } from "./fake_nk";

let nk: FakeNk;
let logger: FakeLogger;
let now: number;
const SYSTEM = "00000000-0000-0000-0000-000000000000";

function call(fn: (c: nkruntime.Context, l: nkruntime.Logger, n: nkruntime.Nakama, p: string) => string, userId: string, body: object = {}): any {
  return JSON.parse(fn(fakeCtx(userId), asLogger(logger), asNk(nk), JSON.stringify(body)));
}
const day = (key: string): any => nk.storageRead([{ collection: TELEMETRY_COLLECTION, key, userId: SYSTEM }])[0].value;

beforeEach(() => {
  nk = new FakeNk();
  logger = new FakeLogger();
  now = Date.UTC(2026, 9, 3, 12, 0, 0) / 1000; // 2026-10-03
  setClockForTests(() => now);
  registerProfileHandlers();
  registerRaidHandlers();
});
afterEach(() => setClockForTests(null));

describe("dayKey", () => {
  it("is the UTC date", () => {
    expect(dayKey(now)).toBe("2026-10-03");
    expect(dayKey(Date.UTC(2026, 0, 1, 23, 59, 59) / 1000)).toBe("2026-01-01");
    expect(dayKey(Date.UTC(2026, 0, 2, 0, 0, 0) / 1000)).toBe("2026-01-02");
  });
});

describe("recordRaid", () => {
  const tele = { strains: { "rhinovirus/wild": 40, "rhinovirus/rapid_replication": 16 }, generations: { macrophage: 2, rhinovirus: 1 } };

  it("adds a raid to the day: raids, wins, per-strain usage, generations and hashed active users", () => {
    recordRaid(asNk(nk), asLogger(logger), "a", "d", true, tele);
    recordRaid(asNk(nk), asLogger(logger), "a", "d2", false, { strains: { "rhinovirus/wild": 10 }, generations: { macrophage: 1 } });
    const d = day("2026-10-03");
    expect(d.raids).toBe(2);
    expect(d.attacker_wins).toBe(1);
    expect(d.strains["rhinovirus/wild"]).toEqual({ used_raids: 2, used_atp: 50, wins: 1 });
    expect(d.strains["rhinovirus/rapid_replication"]).toEqual({ used_raids: 1, used_atp: 16, wins: 1 });
    expect(d.types.macrophage.max_generation_seen).toBe(2);
    expect(d.types.rhinovirus.max_generation_seen).toBe(1);
    expect(d.active_users).toHaveLength(3);
    expect(d.active_users).not.toContain("a");
    expect(d.active_users[0]).toMatch(/^[0-9a-f]{64}$/);
  });

  it("starts a new aggregate each UTC day", () => {
    recordRaid(asNk(nk), asLogger(logger), "a", "d", true, tele);
    now += 86400;
    recordRaid(asNk(nk), asLogger(logger), "a", "d", false, tele);
    expect(day("2026-10-03").raids).toBe(1);
    expect(day("2026-10-04").raids).toBe(1);
    expect(day("2026-10-04").attacker_wins).toBe(0);
  });

  it("caps the active-user list at 10000 and does not repeat a user", () => {
    nk.storageWrite([{ collection: TELEMETRY_COLLECTION, key: "2026-10-03", userId: SYSTEM,
      value: { date: "2026-10-03", raids: 0, attacker_wins: 0, strains: {}, types: {}, active_users: Array.from({ length: ACTIVE_USERS_CAP }, (_v, i) => "h" + i) } }]);
    recordRaid(asNk(nk), asLogger(logger), "a", "d", true, tele);
    expect(day("2026-10-03").active_users).toHaveLength(ACTIVE_USERS_CAP);
    expect(day("2026-10-03").raids).toBe(1);
  });

  it("is retried when the day object changed under it", () => {
    recordRaid(asNk(nk), asLogger(logger), "a", "d", true, tele);
    const before = nk.storageWrite;
    let first = true;
    // A concurrent writer slips in between our read and write once.
    nk.storageWrite = ((writes: any[]) => {
      if (first && writes[0].collection === TELEMETRY_COLLECTION) {
        first = false;
        before.call(nk, [{ ...writes[0], value: { ...writes[0].value, raids: 50 }, version: "" }]);
      }
      return before.call(nk, writes);
    }) as any;
    recordRaid(asNk(nk), asLogger(logger), "b", "e", true, tele);
    expect(day("2026-10-03").raids).toBe(51);
  });
});

describe("raid onComplete", () => {
  it("feeds the daily aggregate from the worker telemetry", () => {
    for (const id of ["A", "D"]) {
      nk.storageWrite([{ collection: "profile", key: "main", userId: id, permissionRead: 1, permissionWrite: 0,
        value: { wallet: { atp: 1000 }, stored_atp: 0, trophies: 0, shield_until_unix: 0, under_attack_until_unix: 0 } }]);
      nk.storageWrite([{ collection: "base", key: "snapshot", userId: id, permissionRead: 2, permissionWrite: 0, value: { layout: [] } }]);
    }
    const r = call(rpcRaidStart, "A", { defender_id: "D" });
    call(rpcRaidSubmit, "A", { raid_id: r.raid_id, army: [] });
    const job = (call(rpcWorkerClaim, "", { config_hash: CONTENT_HASH }) as any).jobs[0];
    call(rpcWorkerComplete, "", { job_id: job.job_id, ok: true, result: {
      attacker_patch: {}, defender_patch: {}, res: { outcome: "attacker" }, battle: {},
      telemetry: { strains: { "rhinovirus/wild": 20 }, generations: { macrophage: 3 } } } });
    const d = day(dayKey(now));
    expect(d.raids).toBe(1);
    expect(d.attacker_wins).toBe(1);
    expect(d.strains["rhinovirus/wild"]).toEqual({ used_raids: 1, used_atp: 20, wins: 1 });
    expect(d.types.macrophage.max_generation_seen).toBe(3);
    expect(RAID_SECONDS).toBeGreaterThan(0);
  });
});

describe("retention fields", () => {
  it("profile_get records first_seen_unix and the days a player came back", () => {
    nk.storageWrite([{ collection: "profile", key: "main", userId: "u", permissionRead: 1, permissionWrite: 0, value: { wallet: {} } }]);
    call(rpcProfileGet, "u", {});
    const p = (): any => nk.storageRead([{ collection: "profile", key: "main", userId: "u" }])[0].value;
    expect(p().first_seen_unix).toBe(now);
    expect(p().last_seen_days).toEqual([dayIndex(now)]);
    now += 3600;
    call(rpcProfileGet, "u", {});
    expect(p().last_seen_days).toEqual([dayIndex(now)]);
    now += 86400;
    call(rpcProfileGet, "u", {});
    expect(p().first_seen_unix).toBe(Date.UTC(2026, 9, 3, 12, 0, 0) / 1000);
    expect(p().last_seen_days).toEqual([dayIndex(now) - 1, dayIndex(now)]);
  });
});

describe("admin_report", () => {
  function profile(id: string, firstDaysAgo: number, seenOffsets: number[], stats?: object): void {
    const first = now - firstDaysAgo * 86400;
    nk.storageWrite([{ collection: "profile", key: "main", userId: id, permissionRead: 1, permissionWrite: 0, value: {
      first_seen_unix: first, last_seen_days: seenOffsets.map((o) => dayIndex(first) + o), stats } }]);
  }

  it("returns the daily aggregates for the range with active users as a count", () => {
    recordRaid(asNk(nk), asLogger(logger), "a", "d", true, { strains: { "rhinovirus/wild": 10 }, generations: {} });
    now += 86400;
    recordRaid(asNk(nk), asLogger(logger), "a", "d", false, { strains: { "rhinovirus/wild": 10 }, generations: {} });
    const res = call(rpcAdminReport, "", { from: "2026-10-02", to: "2026-10-04" });
    expect(res.ok).toBe(true);
    expect(res.days.map((d: any) => d.date)).toEqual(["2026-10-02", "2026-10-03", "2026-10-04"]);
    expect(res.days[0].raids).toBe(0);
    expect(res.days[1]).toMatchObject({ raids: 1, attacker_wins: 1, active_users: 2 });
    expect(res.days[2].raids).toBe(1);
    expect(JSON.stringify(res)).not.toMatch(/[0-9a-f]{64}/);
  });

  it("computes D1 and D7 retention from first_seen_unix and last_seen_days", () => {
    profile("p1", 10, [0, 1, 7]); // eligible for both, back on day 1 and day 7
    profile("p2", 10, [0, 1]); // back on day 1 only
    profile("p3", 10, [0]); // never back
    profile("p4", 3, [0, 1]); // 3 days old: eligible for D1 only
    profile("p5", 0, [0]); // today: eligible for neither
    profile("p6", 10, [0], { flagged: true });
    const res = call(rpcAdminReport, "", { from: "2026-10-03", to: "2026-10-03" });
    expect(res.retention.d1).toEqual({ eligible: 5, retained: 3 });
    expect(res.retention.d7).toEqual({ eligible: 4, retained: 1 });
    expect(res.players).toBe(6);
    expect(res.flagged).toBe(1);
  });

  it("is admin only and validates its range", () => {
    expect(call(rpcAdminReport, "user", { from: "2026-10-01", to: "2026-10-02" }).error).toBe("admin_only");
    expect(call(rpcAdminReport, "", {}).error).toBe("bad_request");
    expect(call(rpcAdminReport, "", { from: "2026-10-05", to: "2026-10-01" }).error).toBe("bad_request");
    expect(call(rpcAdminReport, "", { from: "nope", to: "2026-10-01" }).error).toBe("bad_request");
    expect(call(rpcAdminReport, "", { from: "2020-01-01", to: "2026-10-01" }).error).toBe("bad_request");
  });
});
