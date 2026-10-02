import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { CONTENT_HASH, DATA } from "../src/generated/data";
import { rpcPing } from "../src/ping";
import { InitModule } from "../src/main";
import { FakeLogger, FakeNk, asLogger, asNk, fakeCtx } from "./fake_nk";

describe("ping", () => {
  it("returns ok, time, content hash and min version", () => {
    const res = JSON.parse(rpcPing(fakeCtx(), asLogger(new FakeLogger()), asNk(new FakeNk()), ""));
    expect(res.ok).toBe(true);
    expect(res.error).toBe("");
    expect(res.content_hash).toBe(CONTENT_HASH);
    expect(typeof res.server_time_unix).toBe("number");
    expect(res.server_time_unix).toBeGreaterThan(1_700_000_000);
    expect(typeof res.min_client_version).toBe("string");
  });

  it("registers ping in InitModule", () => {
    const names: string[] = [];
    const init = { registerRpc: (n: string) => { names.push(n); } } as unknown as nkruntime.Initializer;
    InitModule(fakeCtx(), asLogger(new FakeLogger()), asNk(new FakeNk()), init);
    expect(names).toContain("ping");
  });
});

describe("content hash parity", () => {
  it("matches the hash GameConfig.content_hash prints (tools/print_content_hash.gd)", () => {
    const expected = readFileSync(join(__dirname, "fixtures", "content_hash.txt"), "utf8").trim();
    expect(CONTENT_HASH).toBe(expected);
  });

  it("bundles the three data files", () => {
    expect(DATA.game_rules.feature_flags).toBeTypeOf("object");
    expect(DATA.structures).toBeDefined();
    expect(DATA.pathogens).toBeDefined();
  });
});
