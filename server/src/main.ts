import { rpcDebugEnqueueEcho, rpcJobStatus, rpcWorkerClaim, rpcWorkerComplete } from "./jobs";
import { createLeaderboard } from "./leaderboard";
import { rpcFindOpponent, rpcLeaderboardTop } from "./matchmaking";
import { rpcPing } from "./ping";
import { registerRaidHandlers, rpcRaidCancel, rpcRaidStart, rpcRaidSubmit } from "./raids";
import { registerProfileHandlers, rpcBaseCommit, rpcCollect, rpcProfileGet, rpcProfileImport, rpcUpgradeBuy } from "./profile";

// Nakama runs InitModule in one VM only, but every VM evaluates the script: module state (job handlers) is set up here,
// at top level, never inside InitModule. Module objects are frozen after load, so no runtime mutation of globals.
registerProfileHandlers();
registerRaidHandlers();

// Nakama parses this file statically: register RPCs with literal ids and top-level function names, directly in InitModule.
export function InitModule(
  _ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  nk: nkruntime.Nakama,
  initializer: nkruntime.Initializer
): void {
  initializer.registerRpc("ping", rpcPing);
  initializer.registerRpc("worker_claim", rpcWorkerClaim);
  initializer.registerRpc("worker_complete", rpcWorkerComplete);
  initializer.registerRpc("job_status", rpcJobStatus);
  initializer.registerRpc("debug_enqueue_echo", rpcDebugEnqueueEcho);
  initializer.registerRpc("profile_get", rpcProfileGet);
  initializer.registerRpc("base_commit", rpcBaseCommit);
  initializer.registerRpc("collect", rpcCollect);
  initializer.registerRpc("upgrade_buy", rpcUpgradeBuy);
  initializer.registerRpc("profile_import", rpcProfileImport);
  initializer.registerRpc("raid_start", rpcRaidStart);
  initializer.registerRpc("raid_submit", rpcRaidSubmit);
  initializer.registerRpc("raid_cancel", rpcRaidCancel);
  initializer.registerRpc("find_opponent", rpcFindOpponent);
  initializer.registerRpc("leaderboard_top", rpcLeaderboardTop);
  createLeaderboard(nk, logger);
  logger.info("bio_siege server module loaded");
}
