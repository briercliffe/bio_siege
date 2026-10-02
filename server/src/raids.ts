// PvP raid lifecycle (docs/SERVER_PLAN.md). The server freezes the defender snapshot, issues the seed and the lock,
// and applies the worker's results. The battle, the loot and what both sides learn are decided by the worker
// (src/core/online/raid_jobs.gd); the patches applied here only add, subtract and replace values it returned.
import { nowUnix } from "./clock";
import { DATA, CONTENT_HASH } from "./generated/data";
import { amendJob, enqueueJob, Job, JobOutcome, registerClaimHook, registerJobHandler } from "./jobs";
import { BASE_COLLECTION, readProfile, SNAPSHOT_KEY, updateProfile } from "./profile";
import { takeToken } from "./ratelimit";
import { errResult, okResult, parsePayload, randomInt31 } from "./rpc";
import { clientCompat } from "./version";

export const RAIDS_COLLECTION: string = "raids";
export const DEFENSE_LOG_COLLECTION: string = "defense_log";
export const SYSTEM_USER: string = "00000000-0000-0000-0000-000000000000";
export const RAID_SECONDS: number = 600;
const MAX_ARMY_UNITS: number = 300;
const SWEEP_SCAN_LIMIT: number = 50;

type Dict = { [key: string]: unknown };

export interface RaidRecord {
  raid_id: string;
  attacker_id: string;
  defender_id: string;
  seed: number;
  created_unix: number;
  expires_unix: number;
  status: "open" | "submitted" | "done" | "expired" | "rejected";
  defender_snapshot: Dict;
  attacker_pools: Dict;
  config_hash: string;
  submission: Dict | null;
  result: Dict | null;
}

function readRaid(nk: nkruntime.Nakama, raidId: string): { raid: RaidRecord; version: string } | null {
  const objs = nk.storageRead([{ collection: RAIDS_COLLECTION, key: raidId, userId: SYSTEM_USER }]);
  if (objs.length === 0) return null;
  return { raid: objs[0].value as unknown as RaidRecord, version: objs[0].version };
}

function writeRaid(nk: nkruntime.Nakama, raid: RaidRecord, version: string): void {
  nk.storageWrite([{
    collection: RAIDS_COLLECTION, key: raid.raid_id, userId: SYSTEM_USER, value: raid as unknown as Dict,
    version, permissionRead: 0, permissionWrite: 0,
  }]);
}

/** Read-modify-write one raid with OCC (3 tries). Returns the written record, or null when it vanished or stayed contended. */
function amendRaid(nk: nkruntime.Nakama, raidId: string, mutate: (r: RaidRecord) => boolean): RaidRecord | null {
  for (let i = 0; i < 3; i++) {
    const cur = readRaid(nk, raidId);
    if (cur === null) return null;
    if (!mutate(cur.raid)) return cur.raid;
    try {
      writeRaid(nk, cur.raid, cur.version);
      return cur.raid;
    } catch (_e) {
      // contended: retry
    }
  }
  return null;
}

/** Frees both sides of a raid that ended: the defender's lock and the attacker's open-raid marker. */
function releaseRaid(nk: nkruntime.Nakama, raid: RaidRecord): void {
  updateProfile(nk, raid.defender_id, (p) => {
    if (p.under_attack_raid_id !== undefined && p.under_attack_raid_id !== raid.raid_id) return false; // someone else's lock now
    if (p.under_attack_until_unix === 0 && p.under_attack_raid_id === "") return false;
    p.under_attack_until_unix = 0;
    p.under_attack_raid_id = "";
    return true;
  });
  updateProfile(nk, raid.attacker_id, (p) => { if (p.open_raid_id === raid.raid_id) { p.open_raid_id = ""; return true; } return false; });
}

/** Marks an open raid past its expiry as expired and frees its locks. Returns true when it did. */
export function expireIfStale(nk: nkruntime.Nakama, raidId: string): boolean {
  const now = nowUnix();
  const hit: { raid: RaidRecord | null } = { raid: null };
  amendRaid(nk, raidId, (r) => {
    if (r.status !== "open" || r.expires_unix > now) return false;
    r.status = "expired";
    hit.raid = r;
    return true;
  });
  if (hit.raid === null) return false;
  // The army was never reported, so there is nothing to charge (see rpcRaidCancel for the optional army).
  releaseRaid(nk, hit.raid);
  return true;
}

/** Bounded lazy sweep (called from worker_claim): expires up to SWEEP_SCAN_LIMIT stale open raids. */
export function sweepExpiredRaids(nk: nkruntime.Nakama, _logger: nkruntime.Logger): void {
  const now = nowUnix();
  let checked = 0;
  const res = nk.storageList(SYSTEM_USER, RAIDS_COLLECTION, 100, undefined);
  for (const o of res.objects || []) {
    const r = o.value as unknown as RaidRecord;
    if (r.status !== "open") continue;
    if (++checked > SWEEP_SCAN_LIMIT) break;
    if (r.expires_unix <= now) expireIfStale(nk, r.raid_id);
  }
}

function pathogenPools(profile: Dict): Dict {
  const out: Dict = {};
  const pops = (profile.populations || {}) as Dict;
  for (const id of Object.keys(DATA.pathogens)) {
    if (pops[id] !== undefined) out[id] = pops[id];
  }
  return out;
}

function guard(ctx: nkruntime.Context, nk: nkruntime.Nakama, req: Dict | null): string {
  if (!ctx.userId) return "unauthorized";
  if (req === null) return "bad_request";
  if (!takeToken(nk, ctx.userId, "raid")) return "rate_limited";
  return clientCompat(req);
}

export function rpcRaidStart(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  const req = parsePayload(payload);
  const bad = guard(ctx, nk, req);
  if (bad !== "") return errResult(bad);
  const attackerId = ctx.userId as string;
  if (typeof req!.defender_id !== "string" || req!.defender_id === "") return errResult("bad_request");
  const defenderId = req!.defender_id as string;
  if (defenderId === attackerId) return errResult("self_raid");
  const now = nowUnix();

  const attacker = readProfile(nk, attackerId);
  if (attacker === null) return errResult("no_profile");
  const openId = typeof attacker.profile.open_raid_id === "string" ? attacker.profile.open_raid_id : "";
  if (openId !== "") {
    expireIfStale(nk, openId);
    const open = readRaid(nk, openId);
    if (open !== null && open.raid.status === "open") return errResult("raid_in_progress");
  }
  let defender = readProfile(nk, defenderId);
  if (defender !== null && typeof defender.profile.under_attack_raid_id === "string" && defender.profile.under_attack_raid_id !== "") {
    if (expireIfStale(nk, defender.profile.under_attack_raid_id)) defender = readProfile(nk, defenderId);
  }
  const snapObjs = defender === null ? [] : nk.storageRead([{ collection: BASE_COLLECTION, key: SNAPSHOT_KEY, userId: defenderId }]);
  if (defender === null || snapObjs.length === 0) return errResult("unknown_player");
  if (Number(defender.profile.shield_until_unix || 0) > now) return errResult("shielded");
  if (Number(defender.profile.under_attack_until_unix || 0) > now) return errResult("under_attack");

  // Lock the defender (OCC): a second attacker racing us loses here.
  const raidId = nk.uuidv4();
  const locked = updateProfile(nk, defenderId, (p) => {
    if (Number(p.under_attack_until_unix || 0) > now || Number(p.shield_until_unix || 0) > now) return false;
    p.under_attack_until_unix = now + RAID_SECONDS;
    p.under_attack_raid_id = raidId;
    return true;
  });
  if (locked === null || locked.under_attack_raid_id !== raidId) return errResult("under_attack");

  const raid: RaidRecord = {
    raid_id: raidId,
    attacker_id: attackerId,
    defender_id: defenderId,
    seed: randomInt31(nk),
    created_unix: now,
    expires_unix: now + RAID_SECONDS,
    status: "open",
    defender_snapshot: snapObjs[0].value as Dict,
    attacker_pools: pathogenPools(attacker.profile),
    config_hash: CONTENT_HASH,
    submission: null,
    result: null,
  };
  writeRaid(nk, raid, "*");
  updateProfile(nk, attackerId, (p) => { p.open_raid_id = raid.raid_id; return true; });
  return okResult({ raid_id: raid.raid_id, seed: raid.seed, defender_snapshot: raid.defender_snapshot, expires_unix: raid.expires_unix });
}

export function rpcRaidSubmit(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  const req = parsePayload(payload);
  const bad = guard(ctx, nk, req);
  if (bad !== "") return errResult(bad);
  const attackerId = ctx.userId as string;
  if (typeof req!.raid_id !== "string" || !Array.isArray(req!.army) || (req!.army as unknown[]).length > MAX_ARMY_UNITS) return errResult("bad_request");
  const raidId = req!.raid_id as string;
  const cur = readRaid(nk, raidId);
  if (cur === null || cur.raid.attacker_id !== attackerId) return errResult("unknown_raid");
  if (expireIfStale(nk, raidId)) return errResult("expired");
  if (cur.raid.status !== "open") return errResult("not_open");

  const submission: Dict = {
    army: req!.army,
    client_final_hash: typeof req!.client_final_hash === "string" ? req!.client_final_hash : "",
    submitted_unix: nowUnix(),
  };
  const updated = amendRaid(nk, raidId, (r) => {
    if (r.status !== "open") return false;
    r.status = "submitted";
    r.submission = submission;
    return true;
  });
  if (updated === null || updated.status !== "submitted" || updated.submission === null || updated.submission.submitted_unix !== submission.submitted_unix) {
    return errResult("not_open");
  }
  const attacker = readProfile(nk, attackerId);
  const defender = readProfile(nk, updated.defender_id);
  if (attacker === null || defender === null) return errResult("no_profile");
  const jobId = enqueueJob(nk, "raid_validate", {
    user_id: attackerId,
    raid_id: raidId,
    raid: updated as unknown as Dict,
    attacker_profile: attacker.profile,
    defender_profile: defender.profile,
    now_unix: nowUnix(),
  }, updated.config_hash);
  return okResult({ job_id: jobId });
}

/** Before submit only. The raid ends; the army is spent when the client reports it (`army`), since the server never saw it. */
export function rpcRaidCancel(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  const req = parsePayload(payload);
  const bad = guard(ctx, nk, req);
  if (bad !== "") return errResult(bad);
  const attackerId = ctx.userId as string;
  if (typeof req!.raid_id !== "string") return errResult("bad_request");
  const raidId = req!.raid_id as string;
  const cur = readRaid(nk, raidId);
  if (cur === null || cur.raid.attacker_id !== attackerId) return errResult("unknown_raid");
  if (cur.raid.status !== "open") return errResult("not_open");
  const ended = amendRaid(nk, raidId, (r) => {
    if (r.status !== "open") return false;
    r.status = "expired";
    return true;
  });
  if (ended === null || ended.status !== "expired") return errResult("not_open");
  releaseRaid(nk, ended);
  if (Array.isArray(req!.army) && (req!.army as unknown[]).length <= MAX_ARMY_UNITS) {
    const attacker = readProfile(nk, attackerId);
    if (attacker !== null) {
      const jobId = enqueueJob(nk, "army_spend", {
        user_id: attackerId, raid_id: raidId, attacker_profile: attacker.profile, army: req!.army, now_unix: nowUnix(),
      }, CONTENT_HASH);
      return okResult({ job_id: jobId });
    }
  }
  return okResult();
}

// --- onComplete handlers ------------------------------------------------------------------------------------

function num(v: unknown): number {
  return typeof v === "number" && isFinite(v) ? v : 0;
}

/** Adds the worker's wallet delta (never below 0), replaces pathogen pools, counts the raid. */
function applyAttackerPatch(p: Dict, patch: Dict): boolean {
  const wallet = (p.wallet || {}) as Dict;
  const delta = (patch.wallet_delta || {}) as Dict;
  for (const cur of Object.keys(delta)) wallet[cur] = Math.max(0, num(wallet[cur]) + num(delta[cur]));
  p.wallet = wallet;
  const pops = (p.populations || {}) as Dict;
  const pools = (patch.pathogen_pools || {}) as Dict;
  for (const t of Object.keys(pools)) pops[t] = pools[t];
  p.populations = pops;
  p.raid_counter = num(p.raid_counter) + num(patch.raid_counter_inc);
  return true;
}

/** Applies the loss, the Amino Acids, the learned memory and the bred pools to the defender's current profile. */
function applyDefenderPatch(p: Dict, patch: Dict): boolean {
  p.stored_atp = Math.max(0, num(p.stored_atp) - num(patch.atp_lost));
  const wallet = (p.wallet || {}) as Dict;
  wallet.amino_acids = Math.max(0, num(wallet.amino_acids) + num(patch.amino_gained));
  p.wallet = wallet;
  if (patch.memory !== undefined) p.memory = patch.memory;
  const pops = (p.populations || {}) as Dict;
  const pools = (patch.structure_pools || {}) as Dict;
  for (const t of Object.keys(pools)) pops[t] = pools[t];
  p.populations = pops;
  return true;
}

function refreshSnapshot(nk: nkruntime.Nakama, userId: string, profile: Dict): void {
  const objs = nk.storageRead([{ collection: BASE_COLLECTION, key: SNAPSHOT_KEY, userId }]);
  if (objs.length === 0) return;
  const snap = objs[0].value as Dict;
  snap.memory = profile.memory;
  snap.stored_atp = profile.stored_atp;
  const pops = (snap.populations || {}) as Dict;
  const all = (profile.populations || {}) as Dict;
  for (const t of Object.keys(pops)) if (all[t] !== undefined) pops[t] = all[t];
  snap.populations = pops;
  snap.updated_unix = nowUnix();
  nk.storageWrite([{ collection: BASE_COLLECTION, key: SNAPSHOT_KEY, userId, value: snap, permissionRead: 2, permissionWrite: 0 }]);
}

function charge(nk: nkruntime.Nakama, raid: RaidRecord): void {
  const army = raid.submission !== null ? raid.submission.army : [];
  const attacker = readProfile(nk, raid.attacker_id);
  if (attacker === null) return;
  enqueueJob(nk, "army_spend", {
    user_id: raid.attacker_id, raid_id: raid.raid_id, attacker_profile: attacker.profile, army, now_unix: nowUnix(),
  }, CONTENT_HASH);
}

export function onRaidValidateComplete(nk: nkruntime.Nakama, logger: nkruntime.Logger, job: Job, outcome: JobOutcome): void {
  const raidId = String(job.payload.raid_id);
  const cur = readRaid(nk, raidId);
  if (cur === null) return;
  const raid = cur.raid;
  if (!outcome.ok) {
    // A rejected validation still charges the army, so retrying is never free.
    logger.warn("raid %s rejected: %s", raidId, outcome.error);
    amendRaid(nk, raidId, (r) => { r.status = "rejected"; r.result = { error: outcome.error }; return true; });
    releaseRaid(nk, raid);
    charge(nk, raid);
    return;
  }
  const result = outcome.result;
  if (result.hash_match === false) logger.warn("raid %s: client hash differs from the server re-simulation", raidId);
  const attackerPatch = (result.attacker_patch || {}) as Dict;
  const defenderPatch = (result.defender_patch || {}) as Dict;
  updateProfile(nk, raid.attacker_id, (p) => applyAttackerPatch(p, attackerPatch));
  const defenderAfter = updateProfile(nk, raid.defender_id, (p) => applyDefenderPatch(p, defenderPatch));
  if (defenderAfter !== null) refreshSnapshot(nk, raid.defender_id, defenderAfter);
  const { battle, ...slim } = result;
  amendRaid(nk, raidId, (r) => { r.status = "done"; r.result = slim; return true; });
  releaseRaid(nk, raid);
  // The full defense-log entry arrives with AM-09 (#183); until then the raw result is stored for the defender.
  nk.storageWrite([{
    collection: DEFENSE_LOG_COLLECTION, key: raidId, userId: raid.defender_id,
    value: { raid_id: raidId, attacker_id: raid.attacker_id, created_unix: nowUnix(), result: slim, battle: battle || null, seen: false },
    permissionRead: 1, permissionWrite: 0,
  }]);
}

export function onArmySpendComplete(nk: nkruntime.Nakama, _logger: nkruntime.Logger, job: Job, outcome: JobOutcome): void {
  if (!outcome.ok) return;
  const attackerId = String(job.payload.user_id);
  const patch = (outcome.result.attacker_patch || {}) as Dict;
  updateProfile(nk, attackerId, (p) => applyAttackerPatch(p, patch));
  amendJob(nk, job.job_id, (j) => { j.result = { army_cost: outcome.result.army_cost }; });
}

export function registerRaidHandlers(): void {
  registerJobHandler("raid_validate", onRaidValidateComplete);
  registerJobHandler("army_spend", onArmySpendComplete);
  registerClaimHook(sweepExpiredRaids);
}
