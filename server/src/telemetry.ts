// Server telemetry for the meta (docs/SERVER_PLAN.md): a daily aggregate per UTC day, and the admin report that
// reads it together with the profiles' retention fields. No game data leaves the server except through admin_report.
import { nowUnix } from "./clock";
import { PROFILE_COLLECTION } from "./profile";
import { dayIndex } from "./retention";
import { errResult, okResult, parsePayload } from "./rpc";

export const TELEMETRY_COLLECTION: string = "telemetry_daily";
export const ACTIVE_USERS_CAP: number = 10000;
const MAX_REPORT_DAYS: number = 120;
const PROFILE_SCAN_PAGES: number = 20;
const SECONDS_PER_DAY: number = 86400;

type Dict = { [key: string]: unknown };

/** yyyy-mm-dd in UTC. */
export function dayKey(unix: number): string {
  const d = new Date(unix * 1000);
  const pad = (n: number): string => (n < 10 ? "0" + n : String(n));
  return d.getUTCFullYear() + "-" + pad(d.getUTCMonth() + 1) + "-" + pad(d.getUTCDate());
}

function num(v: unknown): number {
  return typeof v === "number" && isFinite(v) ? v : 0;
}

function emptyDay(date: string): Dict {
  return { date, raids: 0, attacker_wins: 0, strains: {}, types: {}, active_users: [] };
}

/**
 * Folds one validated raid into today's aggregate (OCC, three tries). `telemetry` is the worker's
 * {strains: {"type/strain": atp}, generations: {type: generation}}; the server only adds it up.
 */
export function recordRaid(nk: nkruntime.Nakama, logger: nkruntime.Logger, attackerId: string, defenderId: string,
    attackerWon: boolean, telemetry: Dict): void {
  const date = dayKey(nowUnix());
  for (let attempt = 0; attempt < 3; attempt++) {
    const objs = nk.storageRead([{ collection: TELEMETRY_COLLECTION, key: date, userId: SYSTEM_USER }]);
    const day: Dict = objs.length > 0 ? (objs[0].value as Dict) : emptyDay(date);
    day.raids = num(day.raids) + 1;
    day.attacker_wins = num(day.attacker_wins) + (attackerWon ? 1 : 0);
    const strains = (day.strains || {}) as { [key: string]: Dict };
    const used = (telemetry.strains || {}) as Dict;
    for (const key of Object.keys(used)) {
      const s = strains[key] || { used_raids: 0, used_atp: 0, wins: 0 };
      s.used_raids = num(s.used_raids) + 1;
      s.used_atp = num(s.used_atp) + num(used[key]);
      s.wins = num(s.wins) + (attackerWon ? 1 : 0);
      strains[key] = s;
    }
    day.strains = strains;
    const types = (day.types || {}) as { [key: string]: Dict };
    const gens = (telemetry.generations || {}) as Dict;
    for (const t of Object.keys(gens)) {
      const entry = types[t] || { max_generation_seen: 0 };
      entry.max_generation_seen = Math.max(num(entry.max_generation_seen), num(gens[t]));
      types[t] = entry;
    }
    day.types = types;
    const users = (day.active_users || []) as string[];
    for (const id of [attackerId, defenderId]) {
      const hashed = nk.sha256Hash(id);
      if (users.length < ACTIVE_USERS_CAP && users.indexOf(hashed) < 0) users.push(hashed);
    }
    day.active_users = users;
    try {
      nk.storageWrite([{
        collection: TELEMETRY_COLLECTION, key: date, userId: SYSTEM_USER, value: day,
        version: objs.length > 0 ? objs[0].version : "*", permissionRead: 0, permissionWrite: 0,
      }]);
      return;
    } catch (_e) {
      // contended: re-read and add again
    }
  }
  logger.warn("telemetry for %s lost a write race three times", date);
}

function validDate(v: unknown): v is string {
  return typeof v === "string" && /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(v) && !isNaN(Date.parse(v + "T00:00:00Z"));
}

/**
 * Admin only (http key). `{from, to}` are yyyy-mm-dd. Returns the daily aggregates (active users as a count, never as
 * hashes) and D1/D7 retention. Retention scans every profile: acceptable at alpha scale (a few thousand players).
 */
export function rpcAdminReport(ctx: nkruntime.Context, _logger: nkruntime.Logger, nk: nkruntime.Nakama, payload: string): string {
  if (ctx.userId) return errResult("admin_only");
  const req = parsePayload(payload);
  if (req === null || !validDate(req.from) || !validDate(req.to)) return errResult("bad_request");
  const from = Date.parse(req.from + "T00:00:00Z") / 1000;
  const to = Date.parse(req.to + "T00:00:00Z") / 1000;
  if (to < from || (to - from) / SECONDS_PER_DAY >= MAX_REPORT_DAYS) return errResult("bad_request");

  const days: Dict[] = [];
  for (let t = from; t <= to; t += SECONDS_PER_DAY) {
    const date = dayKey(t);
    const objs = nk.storageRead([{ collection: TELEMETRY_COLLECTION, key: date, userId: SYSTEM_USER }]);
    if (objs.length === 0) {
      days.push({ date, raids: 0, attacker_wins: 0, strains: {}, types: {}, active_users: 0 });
      continue;
    }
    const { active_users, ...rest } = objs[0].value as Dict;
    days.push({ ...rest, active_users: Array.isArray(active_users) ? active_users.length : 0 });
  }

  const today = dayIndex(nowUnix());
  const retention: { [key: string]: { eligible: number; retained: number } } = { d1: { eligible: 0, retained: 0 }, d7: { eligible: 0, retained: 0 } };
  let players = 0;
  let flagged = 0;
  let cursor: string | undefined = undefined;
  for (let page = 0; page < PROFILE_SCAN_PAGES; page++) {
    const res: nkruntime.StorageObjectList = nk.storageList(null as unknown as string, PROFILE_COLLECTION, 100, cursor);
    for (const o of res.objects || []) {
      const p = o.value as Dict;
      players++;
      const stats = p.stats as Dict | undefined;
      if (stats && stats.flagged === true) flagged++;
      if (typeof p.first_seen_unix !== "number") continue;
      const cohort = dayIndex(p.first_seen_unix);
      const seen = Array.isArray(p.last_seen_days) ? (p.last_seen_days as number[]) : [];
      for (const [name, n] of [["d1", 1], ["d7", 7]] as [string, number][]) {
        if (cohort + n > today) continue;
        retention[name].eligible++;
        if (seen.indexOf(cohort + n) >= 0) retention[name].retained++;
      }
    }
    cursor = res.cursor;
    if (!cursor) break;
  }
  return okResult({ days, retention, players, flagged });
}

const SYSTEM_USER: string = "00000000-0000-0000-0000-000000000000";
