// Trophies, matchmaking and the leaderboard (docs/SERVER_PLAN.md). Which player to show is plumbing: the
// band and exclusions come from the bundled data/game_rules.json "pvp" block, the trophy maths is the worker's
// (src/core/online/trophies.gd). The server only writes the deltas it is given.
import { nowUnix } from "./clock";
import { DATA } from "./generated/data";
import { LEADERBOARD_ID } from "./leaderboard";
import { BASE_COLLECTION, PROFILE_COLLECTION, PROFILE_KEY, readProfile, SNAPSHOT_KEY } from "./profile";
import { takeToken } from "./ratelimit";
import { errResult, okResult, parsePayload, randomInt31 } from "./rpc";
import { clientCompat } from "./version";

const HAYSTACK_LIMIT: number = 100;
const TOP_LIMIT: number = 50;

type Dict = { [key: string]: unknown };

interface Pvp {
  band: number;
  band_widen_steps: number;
  recent_opponent_hours: number;
}

function pvp(): Pvp {
  return DATA.game_rules.pvp as Pvp;
}

function num(v: unknown): number {
  return typeof v === "number" && isFinite(v) ? v : 0;
}

/** True when `userId` may be raided by `callerProfile` right now (shield, lock, recent opponents). */
function raidable(callerProfile: Dict, userId: string, profile: Dict, now: number): boolean {
  if (num(profile.shield_until_unix) > now) return false;
  if (num(profile.under_attack_until_unix) > now) return false;
  const recent = (callerProfile.recent_opponents || {}) as Dict;
  if (num(recent[userId]) > now - pvp().recent_opponent_hours * 3600) return false;
  return true;
}

export function rpcFindOpponent(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  const req = parsePayload(payload);
  if (!ctx.userId) return errResult("unauthorized");
  if (req === null) return errResult("bad_request");
  if (!takeToken(nk, ctx.userId, "find")) return errResult("rate_limited");
  const compat = clientCompat(req);
  if (compat !== "") return errResult(compat);
  const me = ctx.userId;
  const mine = readProfile(nk, me);
  if (mine === null) return errResult("no_profile");
  const now = nowUnix();
  const myTrophies = num(mine.profile.trophies);

  const around = nk.leaderboardRecordsHaystack(LEADERBOARD_ID, me, HAYSTACK_LIMIT, "", 0);
  const records = (around.records || []).filter((r) => r.ownerId !== me);
  if (records.length === 0) return okResult({ ai: true });
  const profiles: { [id: string]: Dict } = {};
  const objs = nk.storageRead(records.map((r) => ({ collection: PROFILE_COLLECTION, key: PROFILE_KEY, userId: r.ownerId })));
  for (const o of objs) profiles[o.userId] = o.value as Dict;

  let band = pvp().band;
  for (let step = 0; step <= pvp().band_widen_steps; step++) {
    const candidates = records.filter((r) => {
      const p = profiles[r.ownerId];
      return p !== undefined && Math.abs(r.score - myTrophies) <= band && raidable(mine.profile, r.ownerId, p, now);
    });
    if (candidates.length > 0) {
      const pick = candidates[randomInt31(nk) % candidates.length];
      const snap = nk.storageRead([{ collection: BASE_COLLECTION, key: SNAPSHOT_KEY, userId: pick.ownerId }]);
      if (snap.length > 0) return okResult({ defender_id: pick.ownerId, preview: snap[0].value, trophies: pick.score });
    }
    band *= 2;
  }
  return okResult({ ai: true });
}

export function rpcLeaderboardTop(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  const req = parsePayload(payload);
  if (!ctx.userId) return errResult("unauthorized");
  if (req === null) return errResult("bad_request");
  if (!takeToken(nk, ctx.userId, "read")) return errResult("rate_limited");
  const list = nk.leaderboardRecordsList(LEADERBOARD_ID, [ctx.userId], TOP_LIMIT);
  const records = (list.records || []).map((r) => ({ rank: r.rank, user_id: r.ownerId, name: r.username, trophies: r.score }));
  const mine = (list.ownerRecords || [])[0];
  if (!mine) return okResult({ records, me: { rank: 0, trophies: 0 } });
  // ownerRecords can come back without a rank (seen on Nakama 3.41): use the top list, then the haystack.
  let rank = mine.rank;
  const inTop = (list.records || []).filter((r) => r.ownerId === ctx.userId)[0];
  if (!rank && inTop) rank = inTop.rank;
  if (!rank) {
    const around = nk.leaderboardRecordsHaystack(LEADERBOARD_ID, ctx.userId, 1, "", 0);
    const self = (around.records || []).filter((r) => r.ownerId === ctx.userId)[0];
    rank = self ? self.rank : 0;
  }
  return okResult({ records, me: { rank, trophies: mine.score } });
}
