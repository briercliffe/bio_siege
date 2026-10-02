# Bio Siege server

Nakama TypeScript runtime for Phase 3 online raids. Design contract: [docs/SERVER_PLAN.md](../docs/SERVER_PLAN.md).
The server never implements a game rule; rules run in the headless Godot worker.

## Pinned versions

| Component | Version |
|---|---|
| Nakama server image | `registry.heroiclabs.com/heroiclabs/nakama:3.41.0` |
| Runtime types (`nakama-runtime`, from heroiclabs/nakama-common) | `v1.48.0` (the version Nakama 3.41.0 builds against) |
| Postgres | `postgres:16-alpine` |
| TypeScript / esbuild / vitest | see `package.json` and `package-lock.json` |

## Commands (run in `server/`)

```bash
npm ci
npm run lint     # strict type check (tsc --noEmit)
npm test         # vitest
npm run build    # bundle to build/index.js
```

`npm run gen` (run automatically by the scripts above) bundles `data/*.json` and their `content_hash` into the git-ignored `src/generated/data.ts`.

## Local stack

```bash
bash tools/run_server.sh
curl -s -X POST "http://127.0.0.1:7350/v2/rpc/ping?http_key=bio_siege_dev_http_key&unwrap"
```

Ports: API 7350, gRPC 7349, console 7351 (admin / password). Dev keys live in `server/local.yml`; they are public defaults for local use only.

## Conventions

- `build/index.js` is one flat script. Nakama parses it statically: `InitModule` and every function passed to `registerRpc` must be top-level declarations, and the `registerRpc` calls must sit directly in `InitModule` with literal ids and function identifiers.
- The content hash must equal `GameConfig.content_hash`. After any change to `data/*.json`, refresh `test/fixtures/content_hash.txt`:
  `godot --headless --path . -s tools/print_content_hash.gd` (the GUT test `test_server_content_hash.gd` and `npm test` both check it).
- Extend `test/fake_nk.ts` as new `nkruntime.Nakama` methods are used.
