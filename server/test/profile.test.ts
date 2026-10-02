import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { setClockForTests } from "../src/clock";
import { CONTENT_HASH } from "../src/generated/data";
import { registerProfileHandlers, rpcBaseCommit, rpcCollect, rpcProfileGet, rpcProfileImport, rpcUpgradeBuy } from "../src/profile";
import { rpcJobStatus, rpcWorkerClaim, rpcWorkerComplete } from "../src/jobs";
import { FakeLogger, FakeNk, asLogger, asNk, fakeCtx } from "./fake_nk";

let nk: FakeNk;
let logger: FakeLogger;
let now: number;
const U = "user-1";

function call(fn: (c: nkruntime.Context, l: nkruntime.Logger, n: nkruntime.Nakama, p: string) => string, userId: string, body: object = {}): any {
  return JSON.parse(fn(fakeCtx(userId), asLogger(logger), asNk(nk), JSON.stringify(body)));
}

/** Plays the worker: claims everything and completes each job with `result` (or a failure when result is null). */
function workerRun(make: (job: any) => { ok: boolean; result: object; error?: string }): any[] {
  const claimed = call(rpcWorkerClaim, "", { config_hash: CONTENT_HASH }).jobs as any[];
  for (const job of claimed) {
    const out = make(job);
    call(rpcWorkerComplete, "", { job_id: job.job_id, ok: out.ok, result: out.result, error: out.error ?? "" });
  }
  return claimed;
}

const fakeProfile = (marker: number): object => ({
  format: "bio_siege.living_base", version: 1, marker, wallet: { atp: 1000 }, layout: [], memory: {}, populations: { macrophage: {} }, stored_atp: 5, trophies: 0,
});
const okWith = (marker: number) => ({ ok: true, result: { profile: fakeProfile(marker), snapshot: { layout: [], marker } } });

function stored(collection: string, key: string): any {
  return nk.storageRead([{ collection, key, userId: U }])[0];
}

beforeEach(() => {
  nk = new FakeNk();
  logger = new FakeLogger();
  now = 1_800_000_000;
  setClockForTests(() => now);
  registerProfileHandlers();
});
afterEach(() => setClockForTests(null));

describe("profile_get", () => {
  it("creates a profile_new job for a new user with a 31-bit seed, then stores the worker's profile and snapshot", () => {
    const res = call(rpcProfileGet, U, { config_hash: CONTENT_HASH });
    expect(res.ok).toBe(true);
    expect(res.profile).toBeNull();
    const jobs = workerRun(() => okWith(1));
    expect(jobs).toHaveLength(1);
    expect(jobs[0].type).toBe("profile_new");
    expect(jobs[0].payload.seed).toBeGreaterThanOrEqual(0);
    expect(jobs[0].payload.seed).toBeLessThan(0x80000000);
    expect(jobs[0].payload.user_id).toBe(U);
    expect(jobs[0].payload.now_unix).toBe(now);

    const p = stored("profile", "main");
    expect(p.value.marker).toBe(1);
    expect(p.permissionRead).toBe(1);
    expect(p.permissionWrite).toBe(0);
    const snap = stored("base", "snapshot");
    expect(snap.value.marker).toBe(1);
    expect(snap.permissionRead).toBe(2);
    expect(call(rpcJobStatus, U, { job_id: res.job_id }).status).toBe("done");
  });

  it("returns the stored copy plus a profile_tick job for an existing profile", () => {
    call(rpcProfileGet, U, {});
    workerRun(() => okWith(1));
    const res = call(rpcProfileGet, U, {});
    expect(res.profile.marker).toBe(1);
    expect(typeof res.job_id).toBe("string");
    const jobs = workerRun(() => okWith(2));
    expect(jobs[0].type).toBe("profile_tick");
    expect(jobs[0].payload.profile.marker).toBe(1);
    expect(stored("profile", "main").value.marker).toBe(2);
  });

  it("does not start a second job while one is pending", () => {
    const first = call(rpcProfileGet, U, {});
    const second = call(rpcProfileGet, U, {});
    expect(second.busy).toBe(true);
    expect(second.job_id).toBe(first.job_id);
  });

  it("rejects an unknown config hash and old clients", () => {
    expect(call(rpcProfileGet, U, { config_hash: "other" }).error).toBe("update_required");
    expect(call(rpcProfileGet, "", {}).error).toBe("unauthorized");
  });
});

describe("mutating RPCs", () => {
  function withProfile(): void {
    call(rpcProfileGet, U, {});
    workerRun(() => okWith(1));
  }

  it("need a profile", () => {
    expect(call(rpcCollect, U, {}).error).toBe("no_profile");
  });

  it("enqueue the right job type and payload", () => {
    withProfile();
    const layout = [{ type: "nucleus", origin: [1, 1] }];
    expect(call(rpcBaseCommit, U, { layout }).ok).toBe(true);
    let jobs = workerRun(() => okWith(2));
    expect(jobs[0].type).toBe("base_commit");
    expect(jobs[0].payload.layout).toEqual(layout);

    call(rpcCollect, U, {});
    jobs = workerRun(() => okWith(3));
    expect(jobs[0].type).toBe("collect");

    call(rpcUpgradeBuy, U, { id: "memory_slot" });
    jobs = workerRun(() => okWith(4));
    expect(jobs[0].type).toBe("upgrade_buy");
    expect(jobs[0].payload.id).toBe("memory_slot");
  });

  it("validate their request shape", () => {
    withProfile();
    expect(call(rpcBaseCommit, U, { layout: "x" }).error).toBe("bad_request");
    expect(call(rpcUpgradeBuy, U, {}).error).toBe("bad_request");
    expect(call(rpcProfileImport, U, { local_profile: 5 }).error).toBe("bad_request");
  });

  it("return busy while a job is in flight and free up when it finishes", () => {
    withProfile();
    expect(call(rpcCollect, U, {}).ok).toBe(true);
    expect(call(rpcCollect, U, {}).error).toBe("busy");
    workerRun(() => okWith(2));
    expect(call(rpcCollect, U, {}).ok).toBe(true);
  });

  it("free the lock when the worker rejects a job, and the rejection reaches the client", () => {
    withProfile();
    const res = call(rpcBaseCommit, U, { layout: [] });
    workerRun(() => ({ ok: false, result: {}, error: "insufficient_funds" }));
    expect(call(rpcJobStatus, U, { job_id: res.job_id })).toMatchObject({ status: "failed", job_error: "insufficient_funds" });
    expect(stored("profile", "main").value.marker).toBe(1);
    expect(call(rpcCollect, U, {}).ok).toBe(true);
  });

  it("a stale lock does not block forever", () => {
    withProfile();
    expect(call(rpcCollect, U, {}).ok).toBe(true);
    now += 200;
    expect(call(rpcCollect, U, {}).ok).toBe(true);
  });

  it("are rate limited", () => {
    withProfile();
    let limited = false;
    for (let i = 0; i < 10; i++) {
      const r = call(rpcCollect, U, {});
      if (r.error === "rate_limited") limited = true;
    }
    expect(limited).toBe(true);
  });

  it("profile_import forwards only the layout and memory of the local profile", () => {
    withProfile();
    call(rpcProfileImport, U, {
      local_profile: {
        format: "bio_siege.living_base", version: 1, layout: [], memory: { a: 1 },
        wallet: { atp: 99999 }, populations: { macrophage: { x: 1 } }, upgrades: { memory_slot: 2 }, trophies: 9999, unlocked_strains: ["x"],
      },
    });
    const job = workerRun(() => okWith(2))[0];
    expect(job.type).toBe("profile_import");
    expect(Object.keys(job.payload.local_profile).sort()).toEqual(["format", "layout", "memory", "version"]);
    expect(job.payload.local_profile.memory).toEqual({ a: 1 });
  });
});

describe("version conflicts", () => {
  it("re-enqueue once with the newer profile, and job_status follows the new job", () => {
    call(rpcProfileGet, U, {});
    workerRun(() => okWith(1));
    const res = call(rpcCollect, U, {});
    // Someone else (a raid result) changes the profile after the job was enqueued.
    const cur = stored("profile", "main");
    nk.storageWrite([{ collection: "profile", key: "main", userId: U, value: { ...cur.value, marker: 50 }, version: cur.version }]);

    const first = workerRun(() => okWith(2));
    expect(first[0].type).toBe("collect");
    expect(stored("profile", "main").value.marker).toBe(50);
    // The original job points at a successor, which is queued with the newer profile.
    const status = call(rpcJobStatus, U, { job_id: res.job_id });
    expect(status.status).toBe("queued");
    const second = workerRun(() => okWith(3));
    expect(second[0].payload.requeued).toBe(true);
    expect(second[0].payload.profile.marker).toBe(50);
    expect(stored("profile", "main").value.marker).toBe(3);
    expect(call(rpcJobStatus, U, { job_id: res.job_id }).status).toBe("done");
  });

  it("fail with conflict when the retry conflicts too", () => {
    call(rpcProfileGet, U, {});
    workerRun(() => okWith(1));
    const res = call(rpcCollect, U, {});
    const bump = (m: number): void => {
      const cur = stored("profile", "main");
      nk.storageWrite([{ collection: "profile", key: "main", userId: U, value: { ...cur.value, marker: m }, version: cur.version }]);
    };
    bump(50);
    workerRun(() => okWith(2));
    bump(60);
    workerRun(() => okWith(3));
    expect(stored("profile", "main").value.marker).toBe(60);
    expect(call(rpcJobStatus, U, { job_id: res.job_id })).toMatchObject({ status: "failed", job_error: "conflict" });
    expect(call(rpcCollect, U, {}).ok).toBe(true);
  });

  it("never lets a late profile_new replace an existing profile", () => {
    const res = call(rpcProfileGet, U, {});
    nk.storageWrite([{ collection: "profile", key: "main", userId: U, value: { marker: 7 }, version: "*" }]);
    workerRun(() => okWith(1));
    expect(stored("profile", "main").value.marker).toBe(7);
    expect(call(rpcJobStatus, U, { job_id: res.job_id }).status).toBe("failed");
  });
});
