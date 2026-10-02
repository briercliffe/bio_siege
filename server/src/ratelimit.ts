// Per-user token buckets (docs/SERVER_PLAN.md, "Security"). Nakama's JS runtime freezes module-level objects
// (a map of buckets cannot be mutated at request time), so each bucket lives in storage: collection `ratelimit`,
// key = group, owner = the user, server-only permissions. Two storage ops per limited call: alpha scale.
import { nowMs } from "./clock";

export type LimitGroup = "read" | "write" | "find" | "raid";

export const RATELIMIT_COLLECTION: string = "ratelimit";

export const LIMITS: { [group: string]: { capacity: number; perSecond: number } } = {
  read: { capacity: 20, perSecond: 5 },
  write: { capacity: 5, perSecond: 1 },
  find: { capacity: 5, perSecond: 0.5 },
  raid: { capacity: 5, perSecond: 0.2 },
};

/** True when the call is allowed (one token spent). A lost write race is allowed through (best effort). */
export function takeToken(nk: nkruntime.Nakama, userId: string, group: LimitGroup): boolean {
  const limit = LIMITS[group];
  const now = nowMs();
  const objs = nk.storageRead([{ collection: RATELIMIT_COLLECTION, key: group, userId }]);
  let tokens = limit.capacity;
  let version = "*";
  if (objs.length > 0) {
    const v = objs[0].value as { tokens?: number; ms?: number };
    const last = typeof v.ms === "number" ? v.ms : now;
    tokens = Math.min(limit.capacity, (typeof v.tokens === "number" ? v.tokens : limit.capacity) + ((now - last) / 1000) * limit.perSecond);
    version = objs[0].version;
  }
  const allowed = tokens >= 1;
  if (allowed) tokens -= 1;
  try {
    nk.storageWrite([{
      collection: RATELIMIT_COLLECTION, key: group, userId, value: { tokens, ms: now },
      version, permissionRead: 0, permissionWrite: 0,
    }]);
  } catch (_e) {
    // contended: another call of this user spent a token at the same moment; do not block on it
  }
  return allowed;
}
