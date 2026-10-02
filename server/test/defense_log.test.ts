import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { setClockForTests } from "../src/clock";
import { MAX_ENTRIES, PAGE_SIZE, rpcDefenseLogGet, rpcDefenseLogList, rpcDefenseLogMarkSeen, writeDefenseLogEntry } from "../src/defense_log";
import { FakeLogger, FakeNk, asLogger, asNk, fakeCtx } from "./fake_nk";

let nk: FakeNk;
let logger: FakeLogger;
let now: number;
const D = "defender";

function call(fn: (c: nkruntime.Context, l: nkruntime.Logger, n: nkruntime.Nakama, p: string) => string, userId: string, body: object = {}): any {
  return JSON.parse(fn(fakeCtx(userId), asLogger(logger), asNk(nk), JSON.stringify(body)));
}

const result = {
  res: { outcome: "attacker", memory_changes: [{ strain_key: "rhinovirus/wild", reason: "learned", from: 0, to: 1 }] },
  defender_patch: { atp_lost: 40, amino_gained: 3, trophies_delta: -20 },
  defense_info: { army: { rhinovirus: 4 }, ticks: 321, defender_evolution: [{ type_id: "b_cell", generation: 4 }] },
};

function write(id: string, battle: unknown = { big: "log" }): void {
  writeDefenseLogEntry(asNk(nk), asLogger(logger), id, "attacker", D, result, battle);
}

beforeEach(() => {
  nk = new FakeNk();
  logger = new FakeLogger();
  now = 1_800_000_000;
  setClockForTests(() => now);
});
afterEach(() => setClockForTests(null));

describe("writing", () => {
  it("stores the entry for the defender with the documented fields", () => {
    write("r1");
    const o = nk.storageRead([{ collection: "defense_log", key: "r1", userId: D }])[0];
    expect(o.permissionRead).toBe(1);
    expect(o.permissionWrite).toBe(0);
    expect(o.value).toMatchObject({
      raid_id: "r1", attacker_id: "attacker", attacker_name: "name-attacker", created_unix: now, outcome: "attacker", trophies_delta: -20,
      atp_lost: 40, amino_gained: 3, seen: false, army: { rhinovirus: 4 }, ticks: 321, battle: { big: "log" },
    });
    expect((o.value as any).evolution).toEqual([{ type_id: "b_cell", generation: 4 }]);
    expect((o.value as any).memory_changes).toHaveLength(1);
  });

  it("keeps at most 50 entries per user and deletes the oldest", () => {
    for (let i = 0; i < MAX_ENTRIES + 5; i++) {
      now += 10;
      write("r" + String(i).padStart(3, "0"));
    }
    const all = nk.storageList(D, "defense_log", 100).objects;
    expect(all).toHaveLength(MAX_ENTRIES);
    const keys = all.map((o: any) => o.key);
    expect(keys).not.toContain("r000");
    expect(keys).toContain("r054");
    // Another user's log is untouched.
    writeDefenseLogEntry(asNk(nk), asLogger(logger), "x1", "attacker", "other", result, null);
    expect(nk.storageList("other", "defense_log", 100).objects).toHaveLength(1);
  });
});

describe("defense_log_list", () => {
  it("lists newest first without the battle, 20 per page, with a cursor", () => {
    for (let i = 0; i < 45; i++) {
      now += 10;
      write("r" + String(i).padStart(3, "0"));
    }
    const first = call(rpcDefenseLogList, D);
    expect(first.ok).toBe(true);
    expect(first.entries).toHaveLength(PAGE_SIZE);
    expect(first.entries[0].raid_id).toBe("r044");
    expect(first.entries[0].battle).toBeUndefined();
    expect(first.entries[0].has_battle).toBe(true);
    expect(first.cursor).toBe("20");
    const second = call(rpcDefenseLogList, D, { cursor: first.cursor });
    expect(second.entries).toHaveLength(PAGE_SIZE);
    expect(second.entries[0].raid_id).toBe("r024");
    const third = call(rpcDefenseLogList, D, { cursor: second.cursor });
    expect(third.entries).toHaveLength(5);
    expect(third.cursor).toBe("");
  });

  it("only lists the caller own entries and needs a session", () => {
    write("r1");
    expect(call(rpcDefenseLogList, "someone-else").entries).toHaveLength(0);
    expect(call(rpcDefenseLogList, "").error).toBe("unauthorized");
  });
});

describe("defense_log_get and mark_seen", () => {
  it("returns the full entry to its owner only", () => {
    write("r1");
    const mine = call(rpcDefenseLogGet, D, { raid_id: "r1" });
    expect(mine.ok).toBe(true);
    expect(mine.entry.battle).toEqual({ big: "log" });
    expect(call(rpcDefenseLogGet, "attacker", { raid_id: "r1" }).error).toBe("unknown_entry");
    expect(call(rpcDefenseLogGet, D, { raid_id: "nope" }).error).toBe("unknown_entry");
    expect(call(rpcDefenseLogGet, D, {}).error).toBe("bad_request");
  });

  it("marks entries seen, only the caller own", () => {
    write("r1");
    write("r2");
    const res = call(rpcDefenseLogMarkSeen, D, { raid_ids: ["r1", "missing", 5] });
    expect(res).toMatchObject({ ok: true, marked: 1 });
    expect(call(rpcDefenseLogGet, D, { raid_id: "r1" }).entry.seen).toBe(true);
    expect(call(rpcDefenseLogGet, D, { raid_id: "r2" }).entry.seen).toBe(false);
    expect(call(rpcDefenseLogMarkSeen, "attacker", { raid_ids: ["r2"] }).marked).toBe(0);
    expect(call(rpcDefenseLogMarkSeen, D, { raid_ids: "x" }).error).toBe("bad_request");
  });
});
