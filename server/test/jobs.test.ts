import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { setClockForTests } from "../src/clock";
import { CONTENT_HASH } from "../src/generated/data";
import {
  MAX_ATTEMPTS, STALE_CLAIM_SECONDS, enqueueJob, registerJobHandler, rpcDebugEnqueueEcho, rpcJobStatus, rpcWorkerClaim, rpcWorkerComplete,
} from "../src/jobs";
import { FakeLogger, FakeNk, asLogger, asNk, fakeCtx } from "./fake_nk";

let nk: FakeNk;
let logger: FakeLogger;
let now: number;

function call(fn: (c: nkruntime.Context, l: nkruntime.Logger, n: nkruntime.Nakama, p: string) => string, userId: string, body: object): any {
  return JSON.parse(fn(fakeCtx(userId), asLogger(logger), asNk(nk), JSON.stringify(body)));
}
const claim = (body: object = { config_hash: CONTENT_HASH }, userId: string = ""): any => call(rpcWorkerClaim, userId, body);

beforeEach(() => {
  nk = new FakeNk();
  logger = new FakeLogger();
  now = 1_800_000_000;
  setClockForTests(() => now);
});
afterEach(() => setClockForTests(null));

describe("job lifecycle", () => {
  it("enqueue -> claim -> complete", () => {
    const id = enqueueJob(asNk(nk), "echo", { user_id: "u1", x: 1 }, CONTENT_HASH);
    const res = claim();
    expect(res.ok).toBe(true);
    expect(res.jobs).toHaveLength(1);
    expect(res.jobs[0].job_id).toBe(id);
    expect(res.jobs[0].status).toBe("claimed");
    expect(res.jobs[0].attempts).toBe(1);
    expect(claim().jobs).toHaveLength(0);

    const done = call(rpcWorkerComplete, "", { job_id: id, ok: true, result: { x: 1 }, error: "" });
    expect(done.ok).toBe(true);
    const status = call(rpcJobStatus, "u1", { job_id: id });
    expect(status).toMatchObject({ ok: true, status: "done", result: { x: 1 } });
  });

  it("claims oldest first and honors max", () => {
    const a = enqueueJob(asNk(nk), "echo", {}, CONTENT_HASH);
    now += 5;
    const b = enqueueJob(asNk(nk), "echo", {}, CONTENT_HASH);
    now += 5;
    enqueueJob(asNk(nk), "echo", {}, CONTENT_HASH);
    const res = claim({ config_hash: CONTENT_HASH, max: 2 });
    expect(res.jobs.map((j: any) => j.job_id)).toEqual([a, b]);
  });

  it("a failed completion marks the job failed and runs the handler with the error", () => {
    const seen: string[] = [];
    registerJobHandler("boom", (_nk, _l, job, outcome) => { seen.push(job.job_id + ":" + outcome.error); });
    const id = enqueueJob(asNk(nk), "boom", { user_id: "u1" }, CONTENT_HASH);
    claim();
    call(rpcWorkerComplete, "", { job_id: id, ok: false, result: null, error: "invalid_layout" });
    expect(call(rpcJobStatus, "u1", { job_id: id })).toMatchObject({ status: "failed", job_error: "invalid_layout" });
    expect(seen).toEqual([id + ":invalid_layout"]);
  });

  it("completing twice is a harmless duplicate and an unclaimed job cannot be completed", () => {
    const id = enqueueJob(asNk(nk), "echo", {}, CONTENT_HASH);
    expect(call(rpcWorkerComplete, "", { job_id: id, ok: true, result: {} }).error).toBe("not_claimed");
    claim();
    expect(call(rpcWorkerComplete, "", { job_id: id, ok: true, result: {} }).ok).toBe(true);
    expect(call(rpcWorkerComplete, "", { job_id: id, ok: true, result: {} }).duplicate).toBe(true);
    expect(call(rpcWorkerComplete, "", { job_id: "nope", ok: true }).error).toBe("unknown_job");
  });
});

describe("config hash", () => {
  it("a claim with the wrong config hash returns nothing", () => {
    enqueueJob(asNk(nk), "echo", {}, CONTENT_HASH);
    expect(claim({ config_hash: "other" }).jobs).toHaveLength(0);
    expect(claim().jobs).toHaveLength(1);
  });

  it("a claim without a config hash is a bad request", () => {
    expect(claim({}).error).toBe("bad_request");
  });
});

describe("stale claims", () => {
  it("are re-queued, then fail after MAX_ATTEMPTS", () => {
    const failures: string[] = [];
    registerJobHandler("slow", (_nk, _l, _job, outcome) => { failures.push(outcome.error); });
    const id = enqueueJob(asNk(nk), "slow", { user_id: "u1" }, CONTENT_HASH);
    for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
      const res = claim();
      expect(res.jobs).toHaveLength(1);
      expect(res.jobs[0].attempts).toBe(attempt);
      now += STALE_CLAIM_SECONDS + 1;
    }
    expect(claim().jobs).toHaveLength(0);
    expect(call(rpcJobStatus, "u1", { job_id: id })).toMatchObject({ status: "failed", job_error: "too_many_attempts" });
    expect(failures).toEqual(["too_many_attempts"]);
  });

  it("a fresh claim is not re-queued", () => {
    enqueueJob(asNk(nk), "echo", {}, CONTENT_HASH);
    claim();
    now += STALE_CLAIM_SECONDS - 1;
    expect(claim().jobs).toHaveLength(0);
  });
});

describe("OCC", () => {
  it("two workers cannot claim the same job", () => {
    enqueueJob(asNk(nk), "echo", {}, CONTENT_HASH);
    const first = claim();
    const second = claim();
    expect(first.jobs.length + second.jobs.length).toBe(1);
  });
});

describe("access control", () => {
  it("rejects a user context on worker RPCs", () => {
    const id = enqueueJob(asNk(nk), "echo", { user_id: "u1" }, CONTENT_HASH);
    expect(claim({ config_hash: CONTENT_HASH }, "u1").error).toBe("worker_only");
    expect(call(rpcWorkerComplete, "u1", { job_id: id, ok: true }).error).toBe("worker_only");
  });

  it("job_status hides jobs that belong to other users", () => {
    const id = enqueueJob(asNk(nk), "echo", { user_id: "u1" }, CONTENT_HASH);
    expect(call(rpcJobStatus, "u2", { job_id: id }).error).toBe("unknown_job");
    expect(call(rpcJobStatus, "u1", { job_id: id }).ok).toBe(true);
    expect(call(rpcJobStatus, "", { job_id: id }).error).toBe("unauthorized");
  });

  it("debug_enqueue_echo is admin only", () => {
    expect(call(rpcDebugEnqueueEcho, "u1", {}).error).toBe("admin_only");
    const res = call(rpcDebugEnqueueEcho, "", { payload: { a: 1 }, user_id: "u9" });
    expect(res.ok).toBe(true);
    const claimed = claim();
    expect(claimed.jobs[0].payload).toEqual({ a: 1, user_id: "u9" });
  });
});

describe("pruning", () => {
  it("deletes finished jobs after the retention window", () => {
    const id = enqueueJob(asNk(nk), "echo", { user_id: "u1" }, CONTENT_HASH);
    claim();
    call(rpcWorkerComplete, "", { job_id: id, ok: true, result: {} });
    now += 3601;
    claim();
    expect(call(rpcJobStatus, "u1", { job_id: id }).error).toBe("unknown_job");
  });
});
