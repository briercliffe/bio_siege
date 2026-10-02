// Job queue between the server and the headless Godot worker (docs/SERVER_PLAN.md, "Job protocol").
// The server only stores and routes jobs; every rule runs in the worker (src/core/online/job_rules.gd).
import { nowUnix } from "./clock";
import { CONTENT_HASH } from "./generated/data";
import { errResult, okResult, parsePayload } from "./rpc";

export const SYSTEM_USER: string = "00000000-0000-0000-0000-000000000000";
export const JOBS_COLLECTION: string = "jobs";
export const STALE_CLAIM_SECONDS: number = 60;
export const MAX_ATTEMPTS: number = 3;
export const DEFAULT_CLAIM_MAX: number = 4;
const MAX_CLAIM_MAX: number = 16;
const LIST_PAGE: number = 100;
const MAX_SCAN_PAGES: number = 5;
/** Finished jobs are kept this long so clients can poll job_status, then pruned during claims. */
const RETENTION_SECONDS: number = 3600;
const PRUNE_PER_CLAIM: number = 50;

export type JobStatus = "queued" | "claimed" | "done" | "failed";

export interface Job {
  job_id: string;
  type: string;
  status: JobStatus;
  created_unix: number;
  claimed_unix: number;
  finished_unix: number;
  attempts: number;
  config_hash: string;
  payload: { [key: string]: unknown };
  result: { [key: string]: unknown } | null;
  error: string;
}

export interface JobOutcome {
  ok: boolean;
  result: { [key: string]: unknown };
  error: string;
}

/** Called after a job finishes (worker_complete or a final stale failure). */
export type JobHandler = (nk: nkruntime.Nakama, logger: nkruntime.Logger, job: Job, outcome: JobOutcome) => void;

const handlers: { [type: string]: JobHandler } = {
  echo: () => {},
};

export function registerJobHandler(type: string, handler: JobHandler): void {
  handlers[type] = handler;
}

/** Runs on every worker_claim (bounded lazy maintenance, for example expiring stale raids). Register at module top level. */
export type ClaimHook = (nk: nkruntime.Nakama, logger: nkruntime.Logger) => void;
const claimHooks: ClaimHook[] = [];

export function registerClaimHook(hook: ClaimHook): void {
  claimHooks.push(hook);
}

interface Entry {
  job: Job;
  version: string;
}

function toJob(value: { [key: string]: unknown }): Job {
  return value as unknown as Job;
}

function writeJob(nk: nkruntime.Nakama, job: Job, version: string): string {
  const acks = nk.storageWrite([{
    collection: JOBS_COLLECTION,
    key: job.job_id,
    userId: SYSTEM_USER,
    value: job as unknown as { [key: string]: unknown },
    version,
    permissionRead: 0,
    permissionWrite: 0,
  }]);
  return acks[0].version;
}

function readJob(nk: nkruntime.Nakama, jobId: string): Entry | null {
  const objs = nk.storageRead([{ collection: JOBS_COLLECTION, key: jobId, userId: SYSTEM_USER }]);
  if (objs.length === 0) return null;
  return { job: toJob(objs[0].value), version: objs[0].version };
}

/** Creates a queued job and returns its id. `payload.user_id` marks the owner for job_status. */
export function enqueueJob(nk: nkruntime.Nakama, type: string, payload: { [key: string]: unknown }, configHash: string, jobId?: string): string {
  const job: Job = {
    job_id: jobId ? jobId : nk.uuidv4(),
    type,
    status: "queued",
    created_unix: nowUnix(),
    claimed_unix: 0,
    finished_unix: 0,
    attempts: 0,
    config_hash: configHash,
    payload,
    result: null,
    error: "",
  };
  writeJob(nk, job, "*");
  return job.job_id;
}

export function getJob(nk: nkruntime.Nakama, jobId: string): Job | null {
  const e = readJob(nk, jobId);
  return e === null ? null : e.job;
}

/** Read-modify-write one job with OCC, retrying a few times. Returns false when the job is missing or stays contended. */
export function amendJob(nk: nkruntime.Nakama, jobId: string, mutate: (job: Job) => void): boolean {
  for (let i = 0; i < 3; i++) {
    const e = readJob(nk, jobId);
    if (e === null) return false;
    mutate(e.job);
    try {
      writeJob(nk, e.job, e.version);
      return true;
    } catch (_err) {
      // contended: re-read and retry
    }
  }
  return false;
}

/** Scans the jobs collection. Alpha scale: a bounded scan, no secondary index. */
function listJobs(nk: nkruntime.Nakama): Entry[] {
  const out: Entry[] = [];
  let cursor: string | undefined = undefined;
  for (let page = 0; page < MAX_SCAN_PAGES; page++) {
    const res: nkruntime.StorageObjectList = nk.storageList(SYSTEM_USER, JOBS_COLLECTION, LIST_PAGE, cursor);
    for (const o of res.objects || []) out.push({ job: toJob(o.value), version: o.version });
    cursor = res.cursor;
    if (!cursor) break;
  }
  return out;
}

function runHandler(nk: nkruntime.Nakama, logger: nkruntime.Logger, job: Job, outcome: JobOutcome): void {
  const handler = handlers[job.type];
  if (!handler) return;
  try {
    handler(nk, logger, job, outcome);
  } catch (e) {
    logger.error("job %s (%s) onComplete failed: %s", job.job_id, job.type, String(e));
  }
}

function requeueOrFail(nk: nkruntime.Nakama, logger: nkruntime.Logger, entry: Entry, now: number): void {
  const job = entry.job;
  if (job.attempts >= MAX_ATTEMPTS) {
    job.status = "failed";
    job.error = "too_many_attempts";
    job.finished_unix = now;
    entry.version = writeJob(nk, job, entry.version);
    runHandler(nk, logger, job, { ok: false, result: {}, error: job.error });
  } else {
    job.status = "queued";
    job.claimed_unix = 0;
    entry.version = writeJob(nk, job, entry.version);
  }
}

export function rpcWorkerClaim(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (ctx.userId) return errResult("worker_only");
  const req = parsePayload(payload);
  if (req === null || typeof req.config_hash !== "string" || req.config_hash === "") return errResult("bad_request");
  let max = typeof req.max === "number" ? Math.floor(req.max) : DEFAULT_CLAIM_MAX;
  max = Math.max(1, Math.min(MAX_CLAIM_MAX, max));
  const now = nowUnix();
  const entries = listJobs(nk);

  // Stale claims go back to the queue (a worker died); after MAX_ATTEMPTS claims the job fails.
  for (const e of entries) {
    if (e.job.status === "claimed" && now - e.job.claimed_unix > STALE_CLAIM_SECONDS) {
      try {
        requeueOrFail(nk, logger, e, now);
      } catch (_err) {
        // Another writer touched it first (OCC); leave it.
      }
    }
  }

  const queued = entries
    .filter((e) => e.job.status === "queued" && e.job.config_hash === req.config_hash)
    .sort((a, b) => a.job.created_unix - b.job.created_unix || (a.job.job_id < b.job.job_id ? -1 : 1));
  const claimed: Job[] = [];
  for (const e of queued) {
    if (claimed.length >= max) break;
    const job = e.job;
    job.status = "claimed";
    job.claimed_unix = now;
    job.attempts += 1;
    try {
      writeJob(nk, job, e.version);
      claimed.push(job);
    } catch (_err) {
      // Lost the race to another worker.
    }
  }

  pruneFinished(nk, entries, now);
  for (const hook of claimHooks) {
    try {
      hook(nk, logger);
    } catch (e) {
      logger.error("claim hook failed: %s", String(e));
    }
  }
  return okResult({ jobs: claimed });
}

function pruneFinished(nk: nkruntime.Nakama, entries: Entry[], now: number): void {
  const doomed = entries
    .filter((e) => (e.job.status === "done" || e.job.status === "failed") && now - e.job.finished_unix > RETENTION_SECONDS)
    .slice(0, PRUNE_PER_CLAIM);
  if (doomed.length === 0) return;
  nk.storageDelete(doomed.map((e) => ({ collection: JOBS_COLLECTION, key: e.job.job_id, userId: SYSTEM_USER })));
}

export function rpcWorkerComplete(ctx: nkruntime.Context, logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (ctx.userId) return errResult("worker_only");
  const req = parsePayload(payload);
  if (req === null || typeof req.job_id !== "string") return errResult("bad_request");
  const entry = readJob(nk, req.job_id);
  if (entry === null) return errResult("unknown_job");
  const job = entry.job;
  if (job.status === "done" || job.status === "failed") return okResult({ duplicate: true });
  if (job.status !== "claimed") return errResult("not_claimed");

  const ok = req.ok === true;
  const outcome: JobOutcome = {
    ok,
    result: ok && req.result !== null && typeof req.result === "object" ? (req.result as { [key: string]: unknown }) : {},
    error: typeof req.error === "string" ? req.error : "",
  };
  job.status = ok ? "done" : "failed";
  job.result = outcome.result;
  job.error = outcome.error;
  job.finished_unix = nowUnix();
  try {
    writeJob(nk, job, entry.version);
  } catch (_err) {
    return errResult("conflict");
  }
  runHandler(nk, logger, job, outcome);
  return okResult();
}

export function rpcJobStatus(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (!ctx.userId) return errResult("unauthorized");
  const req = parsePayload(payload);
  if (req === null || typeof req.job_id !== "string") return errResult("bad_request");
  let entry = readJob(nk, req.job_id);
  // A job re-enqueued after a storage conflict points at its successor (same owner); follow it.
  for (let hop = 0; hop < 3 && entry !== null && entry.job.result && typeof entry.job.result.requeued_as === "string"; hop++) {
    entry = readJob(nk, entry.job.result.requeued_as as string);
  }
  if (entry === null || entry.job.payload.user_id !== ctx.userId) return errResult("unknown_job");
  return okResult({ status: entry.job.status, result: entry.job.result, job_error: entry.job.error });
}

/** Admin only (http key): enqueue an echo job for tests. Request: {payload?, user_id?, config_hash?}. */
export function rpcDebugEnqueueEcho(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (ctx.userId) return errResult("admin_only");
  const req = parsePayload(payload);
  if (req === null) return errResult("bad_request");
  const body: { [key: string]: unknown } =
    req.payload !== null && typeof req.payload === "object" ? { ...(req.payload as { [key: string]: unknown }) } : {};
  if (typeof req.user_id === "string") body.user_id = req.user_id;
  const hash = typeof req.config_hash === "string" ? req.config_hash : CONTENT_HASH;
  return okResult({ job_id: enqueueJob(nk, "echo", body, hash) });
}
