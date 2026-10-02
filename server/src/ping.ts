import { CONTENT_HASH } from "./generated/data";
import { okResult } from "./rpc";

export const MIN_CLIENT_VERSION: string = "0.1.0";

export function rpcPing(_ctx: nkruntime.Context, _logger: nkruntime.Logger, _nk: nkruntime.Nakama, _payload: string): string {
  return okResult({
    server_time_unix: Math.floor(Date.now() / 1000),
    content_hash: CONTENT_HASH,
    min_client_version: MIN_CLIENT_VERSION,
  });
}
