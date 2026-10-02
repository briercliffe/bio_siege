// Retention bookkeeping on the profile (docs/SERVER_PLAN.md): the first time a player was seen and the UTC day
// indexes they came back on. admin_report turns these into D1/D7 retention.

type Dict = { [key: string]: unknown };

const SECONDS_PER_DAY: number = 86400;
const MAX_LAST_SEEN_DAYS: number = 400;

export function dayIndex(unix: number): number {
  return Math.floor(unix / SECONDS_PER_DAY);
}

/** Stamps first_seen_unix and today's day index on a profile. Returns whether anything changed. */
export function touchRetention(profile: Dict, now: number): boolean {
  let changed = false;
  if (typeof profile.first_seen_unix !== "number") {
    profile.first_seen_unix = now;
    changed = true;
  }
  const today = dayIndex(now);
  const days = Array.isArray(profile.last_seen_days) ? (profile.last_seen_days as number[]) : [];
  if (days.indexOf(today) < 0) {
    days.push(today);
    while (days.length > MAX_LAST_SEEN_DAYS) days.shift();
    changed = true;
  }
  profile.last_seen_days = days;
  return changed;
}
