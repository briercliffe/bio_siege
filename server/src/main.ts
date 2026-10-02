import { rpcDebugEnqueueEcho, rpcJobStatus, rpcWorkerClaim, rpcWorkerComplete } from "./jobs";
import { rpcPing } from "./ping";

// Nakama parses this file statically: register RPCs with literal ids and top-level function names, directly in InitModule.
export function InitModule(
  _ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  _nk: nkruntime.Nakama,
  initializer: nkruntime.Initializer
): void {
  initializer.registerRpc("ping", rpcPing);
  initializer.registerRpc("worker_claim", rpcWorkerClaim);
  initializer.registerRpc("worker_complete", rpcWorkerComplete);
  initializer.registerRpc("job_status", rpcJobStatus);
  initializer.registerRpc("debug_enqueue_echo", rpcDebugEnqueueEcho);
  logger.info("bio_siege server module loaded");
}
