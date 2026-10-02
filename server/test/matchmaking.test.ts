import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { setClockForTests } from "../src/clock";
import { writeTrophies } from "../src/leaderboard";
import { rpcFindOpponent, rpcLeaderboardTop } from "../src/matchmaking";
import { FakeLogger, FakeNk, asLogger, asNk, fakeCtx } from "./fake_nk";

let nk: FakeNk;
let logger: FakeLogger;
let now: number;

function call(fn: (c: nkruntime.Context, l: nkruntime.Logger, n: nkruntime.Nakama, p: string) => string, userId: string, body: object = {}): any {
  return JSON.parse(fn(fakeCtx(userId), asLogger(logger), asNk(nk), JSON.stringify(body)));
}

function player(id: string, trophies: number, extra: object = {}): void {
  nk.storageWrite([{ collection: "profile", key: "main", userId: id, permissionRead: 1, permissionWrite: 0,
    value: { trophies, shield_until_unix: 0, under_attack_until_unix: 0, ...extra } }]);
  nk.storageWrite([{ collection: "base", key: "snapshot", userId: id, permissionRead: 2, permissionWrite: 0, value: { layout: [], tag: id, trophies } }]);
  writeTrophies(asNk(nk), asLogger(logger), id, trophies);
}

beforeEach(() => {
  nk = new FakeNk();
  logger = new FakeLogger();
  now = 1_800_000_000;
  setClockForTests(() => now);
});
afterEach(() => setClockForTests(null));

describe("find_opponent", () => {
  it("picks a player inside the trophy band and returns their snapshot", () => {
    player("me", 100);
    player("near", 150);
    player("far", 900);
    const res = call(rpcFindOpponent, "me");
    expect(res.ok).toBe(true);
    expect(res.defender_id).toBe("near");
    expect(res.preview.tag).toBe("near");
  });

  it("widens the band by x2 up to band_widen_steps times", () => {
    player("me", 100);
    player("d1", 260); // 160 away: needs band 200 (one widening)
    expect(call(rpcFindOpponent, "me").defender_id).toBe("d1");
    nk.leaderboards.trophies.delete("d1");
    player("d2", 520); // 420 away: band 100 -> 200 -> 400 -> 800 (three widenings)
    expect(call(rpcFindOpponent, "me").defender_id).toBe("d2");
    nk.leaderboards.trophies.delete("d2");
    player("d3", 1100); // 1000 away: beyond 800
    expect(call(rpcFindOpponent, "me").ai).toBe(true);
  });

  it("excludes self, shielded and locked players", () => {
    player("me", 100);
    player("shielded", 110, { shield_until_unix: now + 60 });
    player("locked", 120, { under_attack_until_unix: now + 60 });
    expect(call(rpcFindOpponent, "me").ai).toBe(true);
    now += 61;
    const res = call(rpcFindOpponent, "me");
    expect(["shielded", "locked"]).toContain(res.defender_id);
    expect(res.defender_id).not.toBe("me");
  });

  it("excludes opponents raided within recent_opponent_hours", () => {
    player("me", 100, { recent_opponents: { other: now - 3600 } });
    player("other", 110);
    expect(call(rpcFindOpponent, "me").ai).toBe(true);
    now += 24 * 3600;
    expect(call(rpcFindOpponent, "me").defender_id).toBe("other");
  });

  it("falls back to AI when nobody else exists or the caller has no profile", () => {
    player("me", 100);
    expect(call(rpcFindOpponent, "me")).toMatchObject({ ok: true, ai: true });
    expect(call(rpcFindOpponent, "stranger").error).toBe("no_profile");
    expect(call(rpcFindOpponent, "").error).toBe("unauthorized");
  });

  it("does not lock anyone and is rate limited", () => {
    player("me", 100);
    player("other", 110);
    call(rpcFindOpponent, "me");
    const other = nk.storageRead([{ collection: "profile", key: "main", userId: "other" }])[0].value as any;
    expect(other.under_attack_until_unix).toBe(0);
    let limited = false;
    for (let i = 0; i < 10; i++) if (call(rpcFindOpponent, "me").error === "rate_limited") limited = true;
    expect(limited).toBe(true);
  });
});

describe("leaderboard_top", () => {
  it("lists the top players and the caller rank", () => {
    for (let i = 0; i < 60; i++) player("p" + String(i).padStart(2, "0"), 100 + i);
    const res = call(rpcLeaderboardTop, "p00");
    expect(res.ok).toBe(true);
    expect(res.records).toHaveLength(50);
    expect(res.records[0]).toMatchObject({ rank: 1, user_id: "p59", trophies: 159 });
    expect(res.me).toEqual({ rank: 60, trophies: 100 });
    expect(res.records[0].name).toBe("name-p59");
  });
});
