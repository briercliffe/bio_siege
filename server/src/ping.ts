import { CONTENT_HASH } from "./generated/data";
import { nowUnix } from "./clock";
import { okResult } from "./rpc";
import { MIN_CLIENT_VERSION } from "./version";

export function rpcPing(_ctx: nkruntime.Context, _logger: nkruntime.Logger, _nk: nkruntime.Nakama, _payload: string): string {
  return okResult({
    server_time_unix: nowUnix(),
    content_hash: CONTENT_HASH,
    min_client_version: MIN_CLIENT_VERSION,
  });
}
