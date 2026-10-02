// Online defense log (docs/SERVER_PLAN.md): every validated raid on a player writes one entry for the defender,
// with the battle (for replay), the outcome, losses, gains, memory changes and the new pool generation.
// Collection `defense_log`, key = raid_id, owner = defender, read 1 (owner), write 0 (server only).
import { nowUnix } from "./clock";
import { clientGuard } from "./guards";
import { errResult, okResult, parsePayload } from "./rpc";

export const DEFENSE_LOG_COLLECTION: string = "defense_log";
export const MAX_ENTRIES: number = 50;
export const PAGE_SIZE: number = 20;

type Dict = { [key: string]: unknown };

function num(v: unknown): number {
  return typeof v === "number" && isFinite(v) ? v : 0;
}

/** Writes the entry for a validated raid and drops the oldest entries beyond MAX_ENTRIES. */
export function writeDefenseLogEntry(nk: nkruntime.Nakama, logger: nkruntime.Logger, raidId: string, attackerId: string,
    defenderId: string, result: Dict, battle: unknown): void {
  const res = (result.res || {}) as Dict;
  const patch = (result.defender_patch || {}) as Dict;
  const info = (result.defense_info || {}) as Dict;
  let attackerName = "";
  try {
    attackerName = nk.accountGetId(attackerId).user.username;
  } catch (_e) {
    // an unnamed attacker is shown as "Player"
  }
  const entry: Dict = {
    raid_id: raidId,
    attacker_id: attackerId,
    attacker_name: attackerName,
    created_unix: nowUnix(),
    outcome: res.outcome,
    trophies_delta: num(patch.trophies_delta),
    atp_lost: num(patch.atp_lost),
    amino_gained: num(patch.amino_gained),
    memory_changes: res.memory_changes || [],
    evolution: info.defender_evolution || [],
    army: info.army || {},
    ticks: num(info.ticks),
    battle: battle === undefined ? null : battle,
    seen: false,
  };
  nk.storageWrite([{ collection: DEFENSE_LOG_COLLECTION, key: raidId, userId: defenderId, value: entry, permissionRead: 1, permissionWrite: 0 }]);
  trim(nk, logger, defenderId);
}

function allEntries(nk: nkruntime.Nakama, userId: string): Dict[] {
  const out: Dict[] = [];
  let cursor: string | undefined = undefined;
  for (let page = 0; page < 5; page++) {
    const res: nkruntime.StorageObjectList = nk.storageList(userId, DEFENSE_LOG_COLLECTION, 100, cursor);
    for (const o of res.objects || []) out.push(o.value as Dict);
    cursor = res.cursor;
    if (!cursor) break;
  }
  out.sort((a, b) => num(b.created_unix) - num(a.created_unix) || (String(a.raid_id) < String(b.raid_id) ? 1 : -1));
  return out;
}

function trim(nk: nkruntime.Nakama, logger: nkruntime.Logger, userId: string): void {
  const entries = allEntries(nk, userId);
  if (entries.length <= MAX_ENTRIES) return;
  const doomed = entries.slice(MAX_ENTRIES);
  try {
    nk.storageDelete(doomed.map((e) => ({ collection: DEFENSE_LOG_COLLECTION, key: String(e.raid_id), userId })));
  } catch (e) {
    logger.warn("defense log trim for %s failed: %s", userId, String(e));
  }
}

/** Entries without `battle`, newest first, PAGE_SIZE per page. `cursor` is the offset of the next page. */
export function rpcDefenseLogList(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  const req = parsePayload(payload);
  const bad = clientGuard(ctx, nk, req, "read");
  if (bad !== "") return errResult(bad);
  const offset = typeof req!.cursor === "string" && /^[0-9]+$/.test(req!.cursor) ? parseInt(req!.cursor, 10) : 0;
  const entries = allEntries(nk, ctx.userId as string);
  const page = entries.slice(offset, offset + PAGE_SIZE).map((e) => {
    const { battle, ...rest } = e;
    return { ...rest, has_battle: battle !== null && battle !== undefined };
  });
  const next = offset + PAGE_SIZE < entries.length ? String(offset + PAGE_SIZE) : "";
  return okResult({ entries: page, cursor: next });
}

/** The full entry (with its battle) for the owner only. */
export function rpcDefenseLogGet(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  const req = parsePayload(payload);
  const bad = clientGuard(ctx, nk, req, "read");
  if (bad !== "") return errResult(bad);
  if (typeof req!.raid_id !== "string") return errResult("bad_request");
  const objs = nk.storageRead([{ collection: DEFENSE_LOG_COLLECTION, key: req!.raid_id as string, userId: ctx.userId as string }]);
  if (objs.length === 0) return errResult("unknown_entry");
  return okResult({ entry: objs[0].value });
}

export function rpcDefenseLogMarkSeen(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  const req = parsePayload(payload);
  const bad = clientGuard(ctx, nk, req, "write");
  if (bad !== "") return errResult(bad);
  if (!Array.isArray(req!.raid_ids) || (req!.raid_ids as unknown[]).length > MAX_ENTRIES) return errResult("bad_request");
  const userId = ctx.userId as string;
  const writes: nkruntime.StorageWriteRequest[] = [];
  for (const id of req!.raid_ids as unknown[]) {
    if (typeof id !== "string") continue;
    const objs = nk.storageRead([{ collection: DEFENSE_LOG_COLLECTION, key: id, userId }]);
    if (objs.length === 0) continue;
    const value = objs[0].value as Dict;
    if (value.seen === true) continue;
    value.seen = true;
    writes.push({ collection: DEFENSE_LOG_COLLECTION, key: id, userId, value, version: objs[0].version, permissionRead: 1, permissionWrite: 0 });
  }
  if (writes.length > 0) {
    try {
      nk.storageWrite(writes);
    } catch (_e) {
      return errResult("conflict");
    }
  }
  return okResult({ marked: writes.length });
}
