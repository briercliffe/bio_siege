import { rpcPing } from "./ping";

// Nakama parses this file statically: register RPCs with literal ids and top-level function names, directly in InitModule.
export function InitModule(
  _ctx: nkruntime.Context,
  logger: nkruntime.Logger,
  _nk: nkruntime.Nakama,
  initializer: nkruntime.Initializer
): void {
  initializer.registerRpc("ping", rpcPing);
  logger.info("bio_siege server module loaded");
}
