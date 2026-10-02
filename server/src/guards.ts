// Guards shared by every client RPC (docs/SERVER_PLAN.md, "Security"). Clients send intents only: a layout, an
// army, an id. They never send populations, memory, wallets, trophies or unlocks; those exist only on the server.
import { takeToken, LimitGroup } from "./ratelimit";
import { clientCompat } from "./version";

type Dict = { [key: string]: unknown };

/** Top-level keys no client RPC accepts. `profile_import` reads `local_profile.layout` and `.memory` (nested, see profile.ts). */
export const FORBIDDEN_CLIENT_KEYS: string[] = ["populations", "memory", "wallet", "trophies", "unlocked_strains"];

/** Returns "forbidden_field" when the payload carries any of `keys`, else "". */
export function rejectForbiddenKeys(payload: Dict, keys: string[] = FORBIDDEN_CLIENT_KEYS): string {
  for (const k of keys) {
    if (Object.prototype.hasOwnProperty.call(payload, k)) return "forbidden_field";
  }
  return "";
}

/**
 * The common front door of a client RPC: a session, a JSON object payload, no forbidden fields, a rate-limit token
 * (spent only for a well-formed call) and a compatible client. Returns an error code, or "" to go on.
 */
export function clientGuard(ctx: nkruntime.Context, nk: nkruntime.Nakama, req: Dict | null, group: LimitGroup): string {
  if (!ctx.userId) return "unauthorized";
  if (req === null) return "bad_request";
  const forbidden = rejectForbiddenKeys(req);
  if (forbidden !== "") return forbidden;
  if (!takeToken(nk, ctx.userId, group)) return "rate_limited";
  return clientCompat(req);
}
