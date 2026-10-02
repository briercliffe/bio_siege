// Hand-written fake of the nkruntime pieces the server uses. Later issues extend it.
export type StoredObject = {
  collection: string;
  key: string;
  userId: string;
  value: { [key: string]: unknown };
  version: string;
  permissionRead: number;
  permissionWrite: number;
};

export class FakeLogger {
  lines: string[] = [];
  debug(f: string): void { this.lines.push("D " + f); }
  info(f: string): void { this.lines.push("I " + f); }
  warn(f: string): void { this.lines.push("W " + f); }
  error(f: string): void { this.lines.push("E " + f); }
}

export class FakeNk {
  storage: Map<string, StoredObject> = new Map();
  private versionCounter: number = 0;
  private uuidCounter: number = 0;

  uuidv4(): string {
    this.uuidCounter += 1;
    return "00000000-0000-4000-8000-" + String(this.uuidCounter).padStart(12, "0");
  }

  storageList(userId: string | null, collection: string, limit: number = 100, cursor?: string): { objects: StoredObject[]; cursor?: string } {
    const all = Array.from(this.storage.values())
      .filter((o) => o.collection === collection && (userId === null || o.userId === userId))
      .sort((a, b) => (a.key < b.key ? -1 : 1));
    const start = cursor ? parseInt(cursor, 10) : 0;
    const page = all.slice(start, start + limit);
    const next = start + limit < all.length ? String(start + limit) : undefined;
    return { objects: JSON.parse(JSON.stringify(page)), cursor: next };
  }

  storageDelete(keys: { collection: string; key: string; userId: string }[]): void {
    for (const k of keys) this.storage.delete(this.id(k.collection, k.key, k.userId));
  }

  private id(collection: string, key: string, userId: string): string {
    return collection + "|" + key + "|" + userId;
  }

  storageRead(reads: { collection: string; key: string; userId: string }[]): StoredObject[] {
    const out: StoredObject[] = [];
    for (const r of reads) {
      const o = this.storage.get(this.id(r.collection, r.key, r.userId));
      if (o) out.push(JSON.parse(JSON.stringify(o)));
    }
    return out;
  }

  /** Honors `version` as OCC: "" = no check, "*" = must not exist, otherwise must equal the stored version. */
  storageWrite(writes: { collection: string; key: string; userId: string; value: { [key: string]: unknown };
      version?: string; permissionRead?: number; permissionWrite?: number }[]): { collection: string; key: string; version: string }[] {
    const acks: { collection: string; key: string; version: string }[] = [];
    for (const w of writes) {
      const id = this.id(w.collection, w.key, w.userId);
      const existing = this.storage.get(id);
      const v = w.version ?? "";
      if (v === "*" && existing) throw new Error("storage version check failed");
      if (v !== "" && v !== "*" && (!existing || existing.version !== v)) throw new Error("storage version check failed");
      this.versionCounter += 1;
      const version = "v" + this.versionCounter;
      this.storage.set(id, {
        collection: w.collection, key: w.key, userId: w.userId, value: JSON.parse(JSON.stringify(w.value)), version,
        permissionRead: w.permissionRead ?? 0, permissionWrite: w.permissionWrite ?? 0,
      });
      acks.push({ collection: w.collection, key: w.key, version });
    }
    return acks;
  }
}

export function fakeCtx(userId: string = ""): nkruntime.Context {
  return { userId } as unknown as nkruntime.Context;
}

export function asLogger(l: FakeLogger): nkruntime.Logger { return l as unknown as nkruntime.Logger; }
export function asNk(n: FakeNk): nkruntime.Nakama { return n as unknown as nkruntime.Nakama; }
