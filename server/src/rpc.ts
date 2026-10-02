// Shared RPC helpers. Every RPC returns {"ok": bool, "error": string, ...} (docs/SERVER_PLAN.md).

export type RpcResult = { ok: boolean; error: string; [key: string]: unknown };

export function okResult(extra: { [key: string]: unknown } = {}): string {
  return JSON.stringify({ ok: true, error: "", ...extra });
}

export function errResult(error: string, extra: { [key: string]: unknown } = {}): string {
  return JSON.stringify({ ...extra, ok: false, error });
}

export function parsePayload(payload: string): { [key: string]: unknown } | null {
  if (payload === "") return {};
  try {
    const v: unknown = JSON.parse(payload);
    if (v !== null && typeof v === "object" && !Array.isArray(v)) return v as { [key: string]: unknown };
  } catch (_e) {
    // fall through
  }
  return null;
}

/** A random non-negative 31-bit int from the server's crypto-random uuid (seeds for profiles and raids). */
export function randomInt31(nk: nkruntime.Nakama): number {
  return parseInt(nk.uuidv4().replace(/-/g, "").slice(0, 8), 16) % 0x80000000;
}
