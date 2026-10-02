// Server-owned Living Base profile (docs/SERVER_PLAN.md). The server stores and serialises; every change to the
// profile is computed by the worker (src/core/online/profile_jobs.gd) and written here when the job completes.
//
// Serialisation choice: one in-flight profile job per user. A second mutating RPC while one is pending returns
// "busy" (the client retries); profile_get never fails with busy, it returns the stored copy and the pending job id.
import { nowUnix } from "./clock";
import { CONTENT_HASH } from "./generated/data";
import { writeTrophies } from "./leaderboard";
import { amendJob, enqueueJob, getJob, Job, JobOutcome, registerJobHandler } from "./jobs";
import { takeToken } from "./ratelimit";
import { errResult, okResult, parsePayload, randomInt31 } from "./rpc";
import { clientCompat } from "./version";

export const PROFILE_COLLECTION: string = "profile";
export const PROFILE_KEY: string = "main";
export const BASE_COLLECTION: string = "base";
export const SNAPSHOT_KEY: string = "snapshot";
export const LOCK_COLLECTION: string = "profile_lock";
export const LOCK_TTL_SECONDS: number = 120;
export const PROFILE_JOB_TYPES: string[] = ["profile_new", "profile_tick", "base_commit", "collect", "upgrade_buy", "profile_import"];

type Dict = { [key: string]: unknown };

export interface StoredProfile {
  profile: Dict;
  version: string;
}

interface Lock {
  job_id: string;
  unix: number;
}

export function readProfile(nk: nkruntime.Nakama, userId: string): StoredProfile | null {
  const objs = nk.storageRead([{ collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId }]);
  if (objs.length === 0) return null;
  return { profile: objs[0].value as Dict, version: objs[0].version };
}

/**
 * Read-modify-write the stored profile with OCC (3 tries). `mutate` returns whether it changed anything.
 * Returns the profile as stored afterwards, or null when there is none or it stayed contended.
 * Writing bumps the storage version, so an in-flight profile job re-enqueues itself on completion.
 */
export function updateProfile(nk: nkruntime.Nakama, userId: string, mutate: (profile: Dict) => boolean): Dict | null {
  for (let i = 0; i < 3; i++) {
    const cur = readProfile(nk, userId);
    if (cur === null) return null;
    if (!mutate(cur.profile)) return cur.profile;
    try {
      nk.storageWrite([{
        collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId, value: cur.profile, version: cur.version,
        permissionRead: 1, permissionWrite: 0,
      }]);
      return cur.profile;
    } catch (_e) {
      // contended: retry on a fresh read
    }
  }
  return null;
}

function readLock(nk: nkruntime.Nakama, userId: string): { lock: Lock; version: string } | null {
  const objs = nk.storageRead([{ collection: LOCK_COLLECTION, key: PROFILE_KEY, userId }]);
  if (objs.length === 0) return null;
  return { lock: objs[0].value as unknown as Lock, version: objs[0].version };
}

function writeLock(nk: nkruntime.Nakama, userId: string, lock: Lock, version: string): void {
  nk.storageWrite([{
    collection: LOCK_COLLECTION, key: PROFILE_KEY, userId, value: lock as unknown as Dict,
    version, permissionRead: 0, permissionWrite: 0,
  }]);
}

/** The pending profile job id when this user has one in flight (and it is neither stale nor finished). */
function activeJobId(nk: nkruntime.Nakama, userId: string): string {
  const l = readLock(nk, userId);
  if (l === null || l.lock.job_id === "") return "";
  if (nowUnix() - l.lock.unix > LOCK_TTL_SECONDS) return "";
  const job = getJob(nk, l.lock.job_id);
  if (job === null || (job.status !== "queued" && job.status !== "claimed")) return "";
  return l.lock.job_id;
}

function releaseLock(nk: nkruntime.Nakama, userId: string, jobId: string): void {
  const l = readLock(nk, userId);
  if (l === null || l.lock.job_id !== jobId) return;
  try {
    writeLock(nk, userId, { job_id: "", unix: 0 }, l.version);
  } catch (_e) {
    // someone took the lock meanwhile; leave it
  }
}

/** Takes the user's lock for a new job id and enqueues the job. Returns the job id, or "" when busy. */
function startProfileJob(nk: nkruntime.Nakama, userId: string, type: string, extra: Dict): string {
  if (activeJobId(nk, userId) !== "") return "";
  const prof = readProfile(nk, userId);
  const jobId = nk.uuidv4();
  const existing = readLock(nk, userId);
  try {
    writeLock(nk, userId, { job_id: jobId, unix: nowUnix() }, existing === null ? "*" : existing.version);
  } catch (_e) {
    return "";
  }
  const payload: Dict = { ...extra };
  payload.user_id = userId;
  payload.now_unix = nowUnix();
  payload.profile = prof === null ? null : prof.profile;
  payload.profile_version = prof === null ? "*" : prof.version;
  enqueueJob(nk, type, payload, CONTENT_HASH, jobId);
  return jobId;
}

function writeProfileAndSnapshot(nk: nkruntime.Nakama, userId: string, profile: Dict, snapshot: Dict, version: string): void {
  nk.storageWrite([
    { collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId, value: profile, version, permissionRead: 1, permissionWrite: 0 },
    { collection: BASE_COLLECTION, key: SNAPSHOT_KEY, userId, value: snapshot, permissionRead: 2, permissionWrite: 0 },
  ]);
}

/** onComplete for every profile job type: write the worker's profile, or re-enqueue once on a version conflict. */
export function onProfileJobComplete(nk: nkruntime.Nakama, logger: nkruntime.Logger, job: Job, outcome: JobOutcome): void {
  const userId = String(job.payload.user_id);
  if (!outcome.ok) {
    releaseLock(nk, userId, job.job_id);
    return;
  }
  const profile = outcome.result.profile as Dict | undefined;
  const snapshot = outcome.result.snapshot as Dict | undefined;
  if (!profile || !snapshot) {
    logger.error("profile job %s returned no profile", job.job_id);
    amendJob(nk, job.job_id, (j) => { j.status = "failed"; j.error = "bad_result"; });
    releaseLock(nk, userId, job.job_id);
    return;
  }
  const cur = readProfile(nk, userId);
  const expected = String(job.payload.profile_version);
  const curVersion = cur === null ? "*" : cur.version;
  if (curVersion === expected) {
    try {
      writeProfileAndSnapshot(nk, userId, profile, snapshot, curVersion);
      // A new player enters the leaderboard with their start trophies.
      if (cur === null && typeof profile.trophies === "number") writeTrophies(nk, logger, userId, profile.trophies);
      releaseLock(nk, userId, job.job_id);
      return;
    } catch (_e) {
      // lost a race after the read: fall through to the conflict path
    }
  }
  handleConflict(nk, logger, job, userId);
}

function handleConflict(nk: nkruntime.Nakama, logger: nkruntime.Logger, job: Job, userId: string): void {
  const cur = readProfile(nk, userId);
  // A second profile_new must never replace an existing profile, and a job that already retried gives up.
  if (job.type === "profile_new" || job.payload.requeued === true || cur === null) {
    logger.warn("profile job %s (%s) lost a version conflict", job.job_id, job.type);
    amendJob(nk, job.job_id, (j) => { j.status = "failed"; j.error = "conflict"; });
    releaseLock(nk, userId, job.job_id);
    return;
  }
  const newId = nk.uuidv4();
  const lock = readLock(nk, userId);
  try {
    writeLock(nk, userId, { job_id: newId, unix: nowUnix() }, lock === null ? "*" : lock.version);
  } catch (_e) {
    amendJob(nk, job.job_id, (j) => { j.status = "failed"; j.error = "conflict"; });
    return;
  }
  const payload: Dict = { ...job.payload };
  payload.profile = cur.profile;
  payload.profile_version = cur.version;
  payload.now_unix = nowUnix();
  payload.requeued = true;
  enqueueJob(nk, job.type, payload, job.config_hash, newId);
  amendJob(nk, job.job_id, (j) => { j.result = { requeued_as: newId }; });
}

export function registerProfileHandlers(): void {
  for (const t of PROFILE_JOB_TYPES) registerJobHandler(t, onProfileJobComplete);
}

// --- RPCs ---------------------------------------------------------------------------------------------------

function guard(ctx: nkruntime.Context, nk: nkruntime.Nakama, group: "read" | "write", req: Dict | null): string {
  if (!ctx.userId) return "unauthorized";
  if (req === null) return "bad_request";
  if (!takeToken(nk, ctx.userId, group)) return "rate_limited";
  return clientCompat(req);
}

export function rpcProfileGet(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  const req = parsePayload(payload);
  const bad = guard(ctx, nk, "read", req);
  if (bad !== "") return errResult(bad);
  const userId = ctx.userId as string;
  const prof = readProfile(nk, userId);
  const pending = activeJobId(nk, userId);
  if (pending !== "") return okResult({ profile: prof === null ? null : prof.profile, job_id: pending, busy: true });
  if (prof === null) {
    const id = startProfileJob(nk, userId, "profile_new", { seed: randomInt31(nk) });
    return okResult({ profile: null, job_id: id, busy: id === "" });
  }
  const id = startProfileJob(nk, userId, "profile_tick", {});
  return okResult({ profile: prof.profile, job_id: id, busy: id === "" });
}

/** Shared body of the four mutating RPCs: needs a profile, takes the lock, returns the job id. */
function mutate(ctx: nkruntime.Context, nk: nkruntime.Nakama, req: Dict | null, type: string, extra: () => Dict | string): string {
  const bad = guard(ctx, nk, "write", req);
  if (bad !== "") return errResult(bad);
  const userId = ctx.userId as string;
  if (readProfile(nk, userId) === null) return errResult("no_profile");
  const body = extra();
  if (typeof body === "string") return errResult(body);
  const id = startProfileJob(nk, userId, type, body);
  if (id === "") return errResult("busy");
  return okResult({ job_id: id });
}

export function rpcBaseCommit(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  const req = parsePayload(payload);
  return mutate(ctx, nk, req, "base_commit", () => (Array.isArray(req!.layout) ? { layout: req!.layout } : "bad_request"));
}

export function rpcCollect(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  return mutate(ctx, nk, parsePayload(payload), "collect", () => ({}));
}

export function rpcUpgradeBuy(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  const req = parsePayload(payload);
  return mutate(ctx, nk, req, "upgrade_buy", () => (typeof req!.id === "string" ? { id: req!.id } : "bad_request"));
}

/** Only the layout and the memory of the local profile are forwarded; the worker never sees anything else. */
export function rpcProfileImport(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  const req = parsePayload(payload);
  return mutate(ctx, nk, req, "profile_import", () => {
    const local = req!.local_profile;
    if (local === null || typeof local !== "object" || Array.isArray(local)) return "bad_request";
    const l = local as Dict;
    if (!Array.isArray(l.layout)) return "bad_request";
    return {
      local_profile: {
        format: l.format, version: l.version, layout: l.layout,
        memory: l.memory !== null && typeof l.memory === "object" ? l.memory : {},
      },
    };
  });
}
