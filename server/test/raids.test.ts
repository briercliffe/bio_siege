import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { setClockForTests } from "../src/clock";
import { CONTENT_HASH } from "../src/generated/data";
import { registerProfileHandlers } from "../src/profile";
import { RAID_SECONDS, registerRaidHandlers, rpcRaidCancel, rpcRaidStart, rpcRaidSubmit } from "../src/raids";
import { rpcWorkerClaim, rpcWorkerComplete } from "../src/jobs";
import { FakeLogger, FakeNk, asLogger, asNk, fakeCtx } from "./fake_nk";

let nk: FakeNk;
let logger: FakeLogger;
let now: number;
const A = "attacker";
const D = "defender";
const E = "enemy";

function call(fn: (c: nkruntime.Context, l: nkruntime.Logger, n: nkruntime.Nakama, p: string) => string, userId: string, body: object = {}): any {
  return JSON.parse(fn(fakeCtx(userId), asLogger(logger), asNk(nk), JSON.stringify(body)));
}
const claim = (): any[] => call(rpcWorkerClaim, "", { config_hash: CONTENT_HASH, max: 16 }).jobs;
const complete = (id: string, ok: boolean, result: object, error = ""): any => call(rpcWorkerComplete, "", { job_id: id, ok, result, error });

function putProfile(userId: string, extra: object = {}): void {
  nk.storageWrite([{
    collection: "profile", key: "main", userId, permissionRead: 1, permissionWrite: 0,
    value: {
      format: "bio_siege.living_base", wallet: { atp: 1000, amino_acids: 0, dna: 0 }, stored_atp: 300, raid_counter: 0, memory: {},
      populations: { rhinovirus: { gen: 3 }, macrophage: { gen: 1 } }, trophies: 0, shield_until_unix: 0, under_attack_until_unix: 0, ...extra,
    },
  }]);
  nk.storageWrite([{
    collection: "base", key: "snapshot", userId, permissionRead: 2, permissionWrite: 0,
    value: { layout: [{ type: "nucleus", origin: [18, 18] }], memory: {}, populations: { macrophage: { gen: 1 } }, stored_atp: 300, trophies: 0, updated_unix: now },
  }]);
}
const profile = (userId: string): any => nk.storageRead([{ collection: "profile", key: "main", userId }])[0].value;
const snapshot = (userId: string): any => nk.storageRead([{ collection: "base", key: "snapshot", userId }])[0].value;
const raidRecord = (id: string): any => nk.storageRead([{ collection: "raids", key: id, userId: "00000000-0000-0000-0000-000000000000" }])[0].value;

const ARMY = [{ type: "rhinovirus", cell: [0, 0], strain: "wild" }];

beforeEach(() => {
  nk = new FakeNk();
  logger = new FakeLogger();
  now = 1_800_000_000;
  setClockForTests(() => now);
  registerProfileHandlers();
  registerRaidHandlers();
  putProfile(A);
  putProfile(D);
  putProfile(E);
});
afterEach(() => setClockForTests(null));

describe("raid_start", () => {
  it("freezes the snapshot, issues a seed, locks the defender and records the attacker's pathogen pools", () => {
    const res = call(rpcRaidStart, A, { defender_id: D });
    expect(res.ok).toBe(true);
    expect(res.seed).toBeGreaterThanOrEqual(0);
    expect(res.seed).toBeLessThan(0x80000000);
    expect(res.expires_unix).toBe(now + RAID_SECONDS);
    expect(res.defender_snapshot.layout).toHaveLength(1);
    expect(profile(D).under_attack_until_unix).toBe(now + RAID_SECONDS);
    expect(profile(D).under_attack_raid_id).toBe(res.raid_id);
    expect(profile(A).open_raid_id).toBe(res.raid_id);
    const rec = raidRecord(res.raid_id);
    expect(rec).toMatchObject({ attacker_id: A, defender_id: D, status: "open", config_hash: CONTENT_HASH, submission: null, result: null });
    expect(rec.attacker_pools).toEqual({ rhinovirus: { gen: 3 } });
    expect(snapshot(D).stored_atp).toBe(300);
  });

  it("rejects a raid on yourself, an unknown player and a missing profile", () => {
    expect(call(rpcRaidStart, A, { defender_id: A }).error).toBe("self_raid");
    expect(call(rpcRaidStart, A, { defender_id: "nobody" }).error).toBe("unknown_player");
    expect(call(rpcRaidStart, "newbie", { defender_id: D }).error).toBe("no_profile");
    expect(call(rpcRaidStart, A, {}).error).toBe("bad_request");
    expect(call(rpcRaidStart, "", { defender_id: D }).error).toBe("unauthorized");
  });

  it("rejects a shielded defender", () => {
    putProfile(D, { shield_until_unix: now + 10 });
    expect(call(rpcRaidStart, A, { defender_id: D }).error).toBe("shielded");
    now += 11;
    expect(call(rpcRaidStart, A, { defender_id: D }).ok).toBe(true);
  });

  it("locks the defender against a second attacker and the attacker against a second raid", () => {
    expect(call(rpcRaidStart, A, { defender_id: D }).ok).toBe(true);
    expect(call(rpcRaidStart, E, { defender_id: D }).error).toBe("under_attack");
    expect(call(rpcRaidStart, A, { defender_id: E }).error).toBe("raid_in_progress");
  });
});

describe("expiry", () => {
  it("lets a new raid start once the old one expired, and frees the lock", () => {
    const first = call(rpcRaidStart, A, { defender_id: D });
    now += RAID_SECONDS + 1;
    expect(call(rpcRaidStart, E, { defender_id: D }).ok).toBe(true);
    expect(raidRecord(first.raid_id).status).toBe("expired");
    expect(call(rpcRaidStart, A, { defender_id: E }).ok).toBe(true);
  });

  it("is swept by worker_claim, which clears both sides", () => {
    const first = call(rpcRaidStart, A, { defender_id: D });
    now += RAID_SECONDS + 1;
    claim();
    expect(raidRecord(first.raid_id).status).toBe("expired");
    expect(profile(D).under_attack_until_unix).toBe(0);
    expect(profile(A).open_raid_id).toBe("");
  });

  it("makes a late submit fail with expired", () => {
    const r = call(rpcRaidStart, A, { defender_id: D });
    now += RAID_SECONDS + 1;
    expect(call(rpcRaidSubmit, A, { raid_id: r.raid_id, army: ARMY, client_final_hash: "h" }).error).toBe("expired");
  });
});

describe("raid_submit", () => {
  it("enqueues raid_validate once, only for the owner", () => {
    const r = call(rpcRaidStart, A, { defender_id: D });
    expect(call(rpcRaidSubmit, E, { raid_id: r.raid_id, army: ARMY }).error).toBe("unknown_raid");
    expect(call(rpcRaidSubmit, A, { raid_id: r.raid_id, army: "x" }).error).toBe("bad_request");
    const ok = call(rpcRaidSubmit, A, { raid_id: r.raid_id, army: ARMY, client_final_hash: "abc" });
    expect(ok.ok).toBe(true);
    expect(call(rpcRaidSubmit, A, { raid_id: r.raid_id, army: ARMY }).error).toBe("not_open");
    expect(raidRecord(r.raid_id).status).toBe("submitted");
    expect(raidRecord(r.raid_id).submission.client_final_hash).toBe("abc");
    const jobs = claim();
    expect(jobs).toHaveLength(1);
    expect(jobs[0].type).toBe("raid_validate");
    expect(jobs[0].payload.raid.defender_snapshot.layout).toHaveLength(1);
    expect(jobs[0].payload.attacker_profile.wallet.atp).toBe(1000);
    expect(jobs[0].payload.defender_profile.stored_atp).toBe(300);
    expect(jobs[0].payload.user_id).toBe(A);
  });
});

describe("raid results", () => {
  const result = {
    attacker_patch: { wallet_delta: { atp: -10, amino_acids: 7 }, pathogen_pools: { rhinovirus: { gen: 4 } }, raid_counter_inc: 1 },
    defender_patch: { atp_lost: 120, amino_gained: 3, memory: { raids: 5 }, structure_pools: { macrophage: { gen: 2 } } },
    res: { outcome: "attacker" }, army_cost: { atp: 10 }, hash_match: true, server_final_hash: "h", battle: { big: "log" },
  };

  function submit(): string {
    const r = call(rpcRaidStart, A, { defender_id: D });
    call(rpcRaidSubmit, A, { raid_id: r.raid_id, army: ARMY, client_final_hash: "h" });
    return r.raid_id;
  }

  it("applies both patches to the current profiles, even if the defender changed since the snapshot", () => {
    const raidId = submit();
    // The defender changed after the snapshot was frozen: more ATP and Amino Acids.
    putProfile(D, { stored_atp: 500, wallet: { atp: 1000, amino_acids: 40, dna: 0 }, under_attack_until_unix: now + RAID_SECONDS, under_attack_raid_id: raidId });
    const job = claim()[0];
    complete(job.job_id, true, result);

    const a = profile(A);
    expect(a.wallet.atp).toBe(990);
    expect(a.wallet.amino_acids).toBe(7);
    expect(a.raid_counter).toBe(1);
    expect(a.populations.rhinovirus).toEqual({ gen: 4 });
    expect(a.populations.macrophage).toEqual({ gen: 1 });
    expect(a.open_raid_id).toBe("");

    const d = profile(D);
    expect(d.stored_atp).toBe(380);
    expect(d.wallet.amino_acids).toBe(43);
    expect(d.memory).toEqual({ raids: 5 });
    expect(d.populations.macrophage).toEqual({ gen: 2 });
    expect(d.under_attack_until_unix).toBe(0);

    expect(snapshot(D).stored_atp).toBe(380);
    expect(snapshot(D).populations.macrophage).toEqual({ gen: 2 });
    const rec = raidRecord(raidId);
    expect(rec.status).toBe("done");
    expect(rec.result.hash_match).toBe(true);
    expect(rec.result.battle).toBeUndefined();
    const log = nk.storageRead([{ collection: "defense_log", key: raidId, userId: D }])[0];
    expect(log.value.battle).toEqual({ big: "log" });
    expect(log.permissionRead).toBe(1);
  });

  it("never lets stored ATP or the wallet go negative", () => {
    const raidId = submit();
    putProfile(D, { stored_atp: 50, under_attack_until_unix: now + RAID_SECONDS, under_attack_raid_id: raidId });
    const job = claim()[0];
    complete(job.job_id, true, result);
    expect(profile(D).stored_atp).toBe(0);
  });

  it("logs a warning when the client hash differs", () => {
    submit();
    const job = claim()[0];
    complete(job.job_id, true, { ...result, hash_match: false });
    expect(logger.lines.some((l) => l.startsWith("W ") && l.includes("hash differs"))).toBe(true);
  });

  it("a rejected validation marks the raid rejected, frees the locks and still charges the army", () => {
    const raidId = submit();
    const job = claim()[0];
    complete(job.job_id, false, {}, "invalid_army");
    expect(raidRecord(raidId).status).toBe("rejected");
    expect(profile(D).under_attack_until_unix).toBe(0);
    expect(profile(A).open_raid_id).toBe("");
    const spend = claim();
    expect(spend).toHaveLength(1);
    expect(spend[0].type).toBe("army_spend");
    expect(spend[0].payload.army).toEqual(ARMY);
    complete(spend[0].job_id, true, { attacker_patch: { wallet_delta: { atp: -10 }, pathogen_pools: {}, raid_counter_inc: 0 }, army_cost: { atp: 10 } });
    expect(profile(A).wallet.atp).toBe(990);
    expect(profile(A).raid_counter).toBe(0);
    // And the attacker can start another raid.
    expect(call(rpcRaidStart, A, { defender_id: D }).ok).toBe(true);
  });
});

describe("trophies and shield", () => {
  const verdict = {
    attacker_patch: { wallet_delta: {}, pathogen_pools: {}, raid_counter_inc: 1, trophies_delta: 20 },
    defender_patch: { atp_lost: 0, amino_gained: 0, memory: {}, structure_pools: {}, trophies_delta: -20, shield_until_unix: 1_800_000_000 + 12 * 3600 },
    res: { outcome: "attacker" }, army_cost: {}, hash_match: true, server_final_hash: "h", battle: {},
  };

  it("applies the worker trophy deltas, floors at 0, sets the shield and updates the leaderboard", () => {
    putProfile(A, { trophies: 100 });
    putProfile(D, { trophies: 15 });
    const r = call(rpcRaidStart, A, { defender_id: D });
    call(rpcRaidSubmit, A, { raid_id: r.raid_id, army: ARMY });
    putProfile(D, { trophies: 15, under_attack_until_unix: now + RAID_SECONDS, under_attack_raid_id: r.raid_id });
    complete(claim()[0].job_id, true, verdict);
    expect(profile(A).trophies).toBe(120);
    expect(profile(D).trophies).toBe(0);
    expect(profile(D).shield_until_unix).toBe(now + 12 * 3600);
    expect(snapshot(D).trophies).toBe(0);
    expect(nk.leaderboards.trophies.get(A)?.score).toBe(120);
    expect(nk.leaderboards.trophies.get(D)?.score).toBe(0);
  });

  it("starting a raid ends the attacker own shield and records the recent opponent", () => {
    putProfile(A, { shield_until_unix: now + 3600 });
    call(rpcRaidStart, A, { defender_id: D });
    expect(profile(A).shield_until_unix).toBe(0);
    expect(profile(A).recent_opponents[D]).toBe(now);
  });

  it("a shielded defender cannot be raided until the shield ends", () => {
    const r = call(rpcRaidStart, A, { defender_id: D });
    call(rpcRaidSubmit, A, { raid_id: r.raid_id, army: ARMY });
    putProfile(D, { under_attack_until_unix: now + RAID_SECONDS, under_attack_raid_id: r.raid_id });
    complete(claim()[0].job_id, true, verdict);
    expect(call(rpcRaidStart, E, { defender_id: D }).error).toBe("shielded");
    now += 12 * 3600 + 1;
    expect(call(rpcRaidStart, E, { defender_id: D }).ok).toBe(true);
  });
});

describe("raid_cancel", () => {
  it("ends an open raid, frees the locks and spends the reported army", () => {
    const r = call(rpcRaidStart, A, { defender_id: D });
    expect(call(rpcRaidCancel, E, { raid_id: r.raid_id }).error).toBe("unknown_raid");
    const res = call(rpcRaidCancel, A, { raid_id: r.raid_id, army: ARMY });
    expect(res.ok).toBe(true);
    expect(raidRecord(r.raid_id).status).toBe("expired");
    expect(profile(D).under_attack_until_unix).toBe(0);
    expect(profile(A).open_raid_id).toBe("");
    const jobs = claim();
    expect(jobs[0].type).toBe("army_spend");
    expect(call(rpcRaidCancel, A, { raid_id: r.raid_id }).error).toBe("not_open");
  });

  it("is not allowed after submit", () => {
    const r = call(rpcRaidStart, A, { defender_id: D });
    call(rpcRaidSubmit, A, { raid_id: r.raid_id, army: ARMY });
    expect(call(rpcRaidCancel, A, { raid_id: r.raid_id }).error).toBe("not_open");
  });

  it("without an army charges nothing (the server never saw one)", () => {
    const r = call(rpcRaidStart, A, { defender_id: D });
    expect(call(rpcRaidCancel, A, { raid_id: r.raid_id }).ok).toBe(true);
    expect(claim()).toHaveLength(0);
  });
});
