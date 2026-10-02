import { CONTENT_HASH } from "./generated/data";

/** Clients older than this get "update_required". 0.0.0 accepts everything until a release needs a floor. */
export const MIN_CLIENT_VERSION: string = "0.0.0";

/** True when dotted version `a` is lower than `b` ("0.1.0" < "0.10.0"). Missing parts count as 0. */
export function versionLess(a: string, b: string): boolean {
  const pa = a.split(".").map((p) => parseInt(p, 10) || 0);
  const pb = b.split(".").map((p) => parseInt(p, 10) || 0);
  const n = Math.max(pa.length, pb.length);
  for (let i = 0; i < n; i++) {
    const x = pa[i] || 0;
    const y = pb[i] || 0;
    if (x !== y) return x < y;
  }
  return false;
}

/** Returns "update_required" when the request carries a content hash or client version the server rejects, else "". */
export function clientCompat(req: { [key: string]: unknown }): string {
  if (typeof req.config_hash === "string" && req.config_hash !== CONTENT_HASH) return "update_required";
  if (typeof req.client_version === "string" && versionLess(req.client_version, MIN_CLIENT_VERSION)) return "update_required";
  return "";
}
