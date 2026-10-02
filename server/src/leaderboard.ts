// The trophies leaderboard (docs/SERVER_PLAN.md): descending, `set` operator, written only by the server.
export const LEADERBOARD_ID: string = "trophies";

/** Called from InitModule: creates the leaderboard (an existing one with the same settings is left alone). */
export function createLeaderboard(nk: nkruntime.Nakama, logger: nkruntime.Logger): void {
  try {
    nk.leaderboardCreate(LEADERBOARD_ID, true, "descending" as unknown as nkruntime.SortOrder, "set" as unknown as nkruntime.Operator);
  } catch (e) {
    logger.warn("leaderboard create: %s", String(e));
  }
}

/** Writes the player's trophies to the leaderboard (a `set`, so the latest value wins). */
export function writeTrophies(nk: nkruntime.Nakama, logger: nkruntime.Logger, userId: string, trophies: number): void {
  try {
    let username = "";
    try {
      username = nk.accountGetId(userId).user.username;
    } catch (_e) {
      // the record is still useful without a name
    }
    nk.leaderboardRecordWrite(LEADERBOARD_ID, userId, username, Math.max(0, Math.floor(trophies)), 0, undefined, "set" as unknown as nkruntime.OverrideOperator);
  } catch (e) {
    logger.warn("leaderboard write for %s failed: %s", userId, String(e));
  }
}
