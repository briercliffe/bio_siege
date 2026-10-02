import { beforeEach, describe, expect, it } from "vitest";
import { rpcAdminFlaggedList } from "../src/admin";
import { rpcDefenseLogGet, rpcDefenseLogList, rpcDefenseLogMarkSeen } from "../src/defense_log";
import { FORBIDDEN_CLIENT_KEYS, rejectForbiddenKeys } from "../src/guards";
import { rpcJobStatus } from "../src/jobs";
import { rpcFindOpponent, rpcLeaderboardTop } from "../src/matchmaking";
import { rpcBaseCommit, rpcCollect, rpcMutationUnlock, rpcProfileGet, rpcProfileImport, rpcUpgradeBuy } from "../src/profile";
import { rpcRaidCancel, rpcRaidStart, rpcRaidSubmit } from "../src/raids";
import { FakeLogger, FakeNk, asLogger, asNk, fakeCtx } from "./fake_nk";

type Rpc = (c: nkruntime.Context, l: nkruntime.Logger, n: nkruntime.Nakama, p: string) => string;

/** Every RPC a client may call, with a valid-looking body. */
const CLIENT_RPCS: { [name: string]: { fn: Rpc; body: object } } = {
  profile_get: { fn: rpcProfileGet, body: {} },
  base_commit: { fn: rpcBaseCommit, body: { layout: [] } },
  collect: { fn: rpcCollect, body: {} },
  upgrade_buy: { fn: rpcUpgradeBuy, body: { id: "memory_slot" } },
  profile_import: { fn: rpcProfileImport, body: { local_profile: { format: "x", version: 1, layout: [] } } },
  mutation_unlock: { fn: rpcMutationUnlock, body: { type: "rhinovirus", variant: "rapid_replication" } },
  raid_start: { fn: rpcRaidStart, body: { defender_id: "d" } },
  raid_submit: { fn: rpcRaidSubmit, body: { raid_id: "r", army: [] } },
  raid_cancel: { fn: rpcRaidCancel, body: { raid_id: "r" } },
  find_opponent: { fn: rpcFindOpponent, body: {} },
  leaderboard_top: { fn: rpcLeaderboardTop, body: {} },
  defense_log_list: { fn: rpcDefenseLogList, body: {} },
  defense_log_get: { fn: rpcDefenseLogGet, body: { raid_id: "r" } },
  defense_log_mark_seen: { fn: rpcDefenseLogMarkSeen, body: { raid_ids: [] } },
  job_status: { fn: rpcJobStatus, body: { job_id: "j" } },
};

let nk: FakeNk;
let logger: FakeLogger;

beforeEach(() => {
  nk = new FakeNk();
  logger = new FakeLogger();
});

function call(fn: Rpc, userId: string, body: object): any {
  return JSON.parse(fn(fakeCtx(userId), asLogger(logger), asNk(nk), JSON.stringify(body)));
}

describe("rejectForbiddenKeys", () => {
  it("lists exactly the fields a client may never send", () => {
    expect(FORBIDDEN_CLIENT_KEYS.sort()).toEqual(["memory", "populations", "trophies", "unlocked_strains", "wallet"]);
  });

  it("flags any of the keys and nothing else", () => {
    expect(rejectForbiddenKeys({ layout: [] })).toBe("");
    expect(rejectForbiddenKeys({ populations: {} })).toBe("forbidden_field");
    expect(rejectForbiddenKeys({ a: 1, wallet: { atp: 1 } })).toBe("forbidden_field");
    expect(rejectForbiddenKeys({ a: 1 }, ["a"])).toBe("forbidden_field");
    expect(rejectForbiddenKeys({ nested: { memory: {} } })).toBe("");
  });
});

describe("every client RPC", () => {
  for (const name of Object.keys(CLIENT_RPCS)) {
    for (const key of FORBIDDEN_CLIENT_KEYS) {
      it(`${name} rejects ${key} with forbidden_field`, () => {
        const { fn, body } = CLIENT_RPCS[name];
        const res = call(fn, "user-1", { ...body, [key]: { x: 1 } });
        expect(res.ok).toBe(false);
        expect(res.error).toBe("forbidden_field");
      });
    }
  }

  it("never reaches storage with a forbidden field (the call fails before any write)", () => {
    for (const name of Object.keys(CLIENT_RPCS)) {
      call(CLIENT_RPCS[name].fn, "user-1", { ...CLIENT_RPCS[name].body, populations: { rhinovirus: {} } });
    }
    expect(nk.storage.size).toBe(0);
  });

  it("without a session answers unauthorized, never forbidden", () => {
    for (const name of Object.keys(CLIENT_RPCS)) {
      expect(call(CLIENT_RPCS[name].fn, "", { ...CLIENT_RPCS[name].body, wallet: {} }).error).toBe("unauthorized");
    }
  });
});

describe("profile_import", () => {
  it("drops populations, wallet and the rest of the local profile", () => {
    nk.storageWrite([{ collection: "profile", key: "main", userId: "user-1", value: { format: "x" } }]);
    call(rpcProfileImport, "user-1", {
      local_profile: {
        format: "bio_siege.living_base", version: 1, layout: [], memory: { raids: 1 }, populations: { rhinovirus: { gen: 99 } },
        wallet: { atp: 99999 }, trophies: 5000, unlocked_strains: ["rhinovirus/antigenic_masking"], upgrades: { memory_slot: 9 },
      },
    });
    const job = nk.storageList("00000000-0000-0000-0000-000000000000", "jobs", 10).objects[0] as any;
    expect(job.value.type).toBe("profile_import");
    expect(Object.keys(job.value.payload.local_profile).sort()).toEqual(["format", "layout", "memory", "version"]);
    expect(JSON.stringify(job.value.payload)).not.toContain("99999");
    expect(JSON.stringify(job.value.payload)).not.toContain("antigenic_masking");
    expect(JSON.stringify(job.value.payload)).not.toContain("\"gen\":99");
  });
});

describe("admin_flagged_list", () => {
  const put = (id: string, stats: object | undefined): void => {
    nk.storageWrite([{ collection: "profile", key: "main", userId: id, value: { trophies: 100, stats }, permissionRead: 1, permissionWrite: 0 }]);
  };

  it("lists only flagged players and refuses a user session", () => {
    put("a", { raids: 9, flagged: true });
    put("b", { raids: 9, flagged: false });
    put("c", undefined);
    const res = call(rpcAdminFlaggedList, "", {});
    expect(res.ok).toBe(true);
    expect(res.players).toHaveLength(1);
    expect(res.players[0]).toMatchObject({ user_id: "a", stats: { flagged: true } });
    expect(call(rpcAdminFlaggedList, "user-1", {}).error).toBe("admin_only");
  });
});
