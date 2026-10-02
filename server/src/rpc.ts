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
