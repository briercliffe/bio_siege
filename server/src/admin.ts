// Admin-only RPCs (http key, no user session). Never reachable from a client.
import { PROFILE_COLLECTION } from "./profile";
import { errResult, okResult } from "./rpc";

type Dict = { [key: string]: unknown };

const SCAN_PAGES: number = 20;
const PAGE: number = 100;

/**
 * Players whose stats object is flagged by the receptor-hit-rate rule (the worker sets `stats.flagged`). There is no
 * automatic ban: this is a list for a human. Scanning every profile is acceptable at alpha scale.
 */
export function rpcAdminFlaggedList(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, _payload: string): string {
  if (ctx.userId) return errResult("admin_only");
  const players: Dict[] = [];
  let cursor: string | undefined = undefined;
  for (let page = 0; page < SCAN_PAGES; page++) {
    const res: nkruntime.StorageObjectList = nk.storageList(null as unknown as string, PROFILE_COLLECTION, PAGE, cursor);
    for (const o of res.objects || []) {
      const v = o.value as Dict;
      const stats = v.stats as Dict | undefined;
      if (stats && stats.flagged === true) players.push({ user_id: o.userId, trophies: v.trophies, stats });
    }
    cursor = res.cursor;
    if (!cursor) break;
  }
  return okResult({ players });
}
