# Server Plan (Phase 3, Online Raids)

Contract for epic #174 (AM-01 to AM-12). Every later Phase 3 to 5 issue implements this document. If an issue and this file disagree, fix the file in the same PR and say so in the PR body.

Anchors: [Principles](#principles) · [Storage](#storage-collections) · [RPCs](#rpc-list) · [Job protocol](#job-protocol) · [Versioning](#versioning) · [Security](#security) · [Error codes](#error-codes)

## Principles

- **One rule engine.** Every game rule (placement, costs, generation, sim, loot, memory, breeding) exists **only in GDScript** in `src/core`. The TypeScript server never re-implements a rule. It authenticates, stores, locks, queues **jobs**, and applies the worker's results.
- **The server owns time and randomness.** Job timestamps and raid seeds come from the server.
- **Clients are never trusted.** A client sends intents (a layout, an army, an input log). The worker validates and computes outcomes. Populations, memory and wallets from a client are never accepted.
- **Data parity.** The worker and the client must run the same `data/*.json`. Every job carries the client's `GameConfig.content_hash`. A mismatch is rejected with `"update_required"`.
- Feature flag `online` (default `false`). With it off, Living Base stays local exactly as Phase 2.
- Server code: TypeScript in `server/`, strict mode, built to a single `build/index.js` for Nakama. Client networking only in `src/game/net/**`. Pure job rules in `src/core/online/**` (no network, no `Time`).
- Auth: anonymous **device** authentication only (no passwords, no email). Account linking is out of scope.
- Values in new JSON blocks are placeholders for owner sign-off.
- Every server RPC returns `{"ok": bool, "error": String, ...}`. Error codes are lowercase snake_case strings listed in [Error codes](#error-codes).

```
Godot client (src/game/net) --RPC over HTTPS/WSS--> Nakama (TypeScript runtime, server/) --> Postgres / CockroachDB
Headless Godot worker (tools/worker) --claim/complete jobs (RPC, http_key)--> Nakama
Worker and client both use src/core (GridModel, BattleSim, RaidResolver)
```

## Storage collections

Nakama storage objects. Permissions use Nakama numbers: read 0 = none, 1 = owner, 2 = public; write 0 = server only.

| Collection / key | Owner | Read / write perms | Content |
|---|---|---|---|
| `profile` / `main` | user | read 1, write 0 | `LivingBaseProfile.to_dict()` plus `trophies`, `unlocked_strains`, `shield_until_unix`, `under_attack_until_unix`, `config_hash`, and later `recent_opponents`, `stats`, `first_seen_unix`, `last_seen_days` |
| `base` / `snapshot` | user | read 2 (public), write 0 | The defended snapshot: `layout`, `memory`, structure-type `populations`, `stored_atp`, `trophies`, `updated_unix` |
| `raids` / `<raid_id>` | system | read 0, write 0 | Raid record (see [Raid record](#raid-record), #180) |
| `jobs` / `<job_id>` | system | read 0, write 0 | Job record ([Job protocol](#job-protocol)) |
| `defense_log` / `<entry_id>` | user | read 1, write 0 | Defense-log entry (key = `raid_id`, see [defense log](#defense-log-entry)) |
| `telemetry_daily` / `<yyyy-mm-dd>` | system | read 0, write 0 | Aggregates (see [telemetry](#telemetry-daily)) |
| `profile_lock` / `main` | user | read 0, write 0 | `{job_id, unix}`: the one in-flight profile job per user (see [profile jobs](#profile-jobs)) |
| `ratelimit` / `<group>` | user | read 0, write 0 | Token bucket `{tokens, ms}` per limit group (see [Security](#security)) |

Leaderboard: `trophies` (descending, `set` operator), created in `InitModule`.

### Raid record

`raids/<raid_id>`:

```json
{"raid_id": "", "attacker_id": "", "defender_id": "", "seed": 0, "created_unix": 0, "expires_unix": 0,
 "status": "open|submitted|done|expired|rejected",
 "defender_snapshot": {}, "attacker_pools": {}, "config_hash": "", "submission": null, "result": null}
```

### Breeding integrity and anti-cheat

- **No client genomes.** Every client RPC starts with `clientGuard` (`server/src/guards.ts`): a session, a JSON object, then `rejectForbiddenKeys` (`populations`, `memory`, `wallet`, `trophies`, `unlocked_strains` at the top level answer `forbidden_field`), the rate limit and the version check. The one place a client value reaches the worker is `profile_import`'s `local_profile.layout` and `.memory` (a one-time import into a fresh profile, normalised by `ImmuneMemory.from_dict`); the server forwards nothing else of it.
- **Pool audit** (`src/core/online/pool_audit.gd`): `raid_validate` audits every pool it is about to use (the attacker's pools from the raid record, the defender's from the snapshot): the genome count is `coevolution.pool_size`, each genome has the declared slot counts (receptors may be widened by up to 4), every allele is a known id, and `generation` is between 0 and the owner's raids (`raid_counter + ai_raid_counter + defense_counter`). A bad pool is reset to wild for the raid; the job result lists it in `pool_resets` and the server logs a warning.
- **Stats** (`stats` on the profile, written from the worker's patches): `raids`, `receptor_hits`, `receptor_checks` (counted by `BattleSim` while coevolution is on, never hashed; they belong to the defender's towers) and `max_generation` per type. `defense_counter` counts raids against the player.
- **Flag rule** (`CheatFlags`): `stats.flagged` becomes true (and stays true) when `receptor_hits * 100 >= pvp.suspicious_hit_rate_pct * receptor_checks` over at least 5 raids while no pool passed generation 5. There is no automatic ban; `admin_flagged_list` (http key) lists flagged players.

### DNA and strain unlocks

- DNA is earned only from PvP wins: `raid_validate` adds `loot.dna_per_win` to the attacker's wallet delta on an attacker win. `debug_dna` stays for Phase 2 AI raids and is ignored while `online` is on.
- `profile.unlocked_strains` holds `"type/variant"` keys. A new profile (and any old profile on load) includes every variant with `unlock_dna == 0` (`StrainUnlocks.normalize`); the list is empty while the `strains` flag is off.
- `mutation_unlock {type, variant}` is a profile job: it refuses an unknown variant (`unknown_strain`), one already unlocked or free (`already_unlocked`) and a wallet below `unlock_dna` (`insufficient_funds`), otherwise it spends DNA and adds the key.
- `raid_validate` army legality: a non-wild strain needs the `strains` flag and an unlock; a locked strain makes the army `invalid_army`.

### Defense log entry

```json
{"raid_id": "", "attacker_id": "", "attacker_name": "", "created_unix": 0, "outcome": "",
 "trophies_delta": 0, "atp_lost": 0, "amino_gained": 0, "memory_changes": [], "evolution": [],
 "battle": {}, "seen": false}
```

At most 50 per user; the oldest is deleted on write.

### Telemetry daily

`telemetry_daily/<yyyy-mm-dd>`: `raids`, `attacker_wins`, per strain key `{used_raids, used_atp, wins}`, per type `{max_generation_seen}`, `active_users` (list of `nk.sha256Hash` of user ids, capped at 10 000).

## RPC list

Callers: **client** (user session), **worker** (http_key, rejects any call with a user context), **admin** (http_key, for tests and ops).
Every response also has `ok` and `error`. "Common" errors that any client RPC can return: `rate_limited`, `update_required`, `forbidden_field`, `bad_request`.

| RPC | Caller | Request | Response | Errors | Issue |
|---|---|---|---|---|---|
| `worker_claim` | worker | `{config_hash, max?}` (max default 4) | `{jobs: [job]}` | `worker_only` | #178 |
| `worker_complete` | worker | `{job_id, ok, result, error}` | `{}` | `worker_only`, `unknown_job` | #178 |
| `job_status` | client | `{job_id}` | `{status, result}` | `unknown_job` (also for other users' jobs) | #178 |
| `debug_enqueue_echo` | admin | `{payload}` | `{job_id}` | | #178 |
| `profile_get` | client | `{client_version, config_hash}` | `{profile (null when new), job_id, busy}` | `update_required`, `rate_limited` | #179 |
| `base_commit` | client | `{layout}` | `{job_id}` | `busy`, `no_profile`, `bad_request` | #179 |
| `collect` | client | `{}` | `{job_id}` | `busy` | #179 |
| `upgrade_buy` | client | `{id}` | `{job_id}` | `busy` | #179 |
| `profile_import` | client | `{local_profile}` (only `layout`, `memory` are read) | `{job_id}` | `busy` | #179 |
| `raid_start` | client | `{defender_id}` | `{raid_id, seed, defender_snapshot, expires_unix}` | `raid_in_progress`, `self_raid`, `shielded`, `under_attack`, `unknown_player`, `no_profile` | #180 |
| `raid_submit` | client | `{raid_id, army: [{type, cell, strain}], client_final_hash}` | `{job_id}` | `unknown_raid`, `not_open`, `expired` | #180 |
| `raid_cancel` | client | `{raid_id, army?}` | `{job_id?}` | `unknown_raid`, `not_open` | #180 |
| `find_opponent` | client | `{}` | `{defender_id, preview, trophies}` or `{ai: true}` | `no_profile`, `rate_limited` | #181 |
| `leaderboard_top` | client | `{}` | `{records: [{rank, user_id, name, trophies}], me: {rank, trophies}}` | | #181 |
| `defense_log_list` | client | `{cursor?}` | `{entries, cursor}` (no `battle` but `has_battle`, newest first, 20 per page; `cursor` is `""` on the last page) | `rate_limited` | #183 |
| `defense_log_get` | client | `{raid_id}` | `{entry}` | `unknown_entry` | #183 |
| `defense_log_mark_seen` | client | `{raid_ids}` | `{marked}` | `bad_request`, `conflict` | #183 |
| `mutation_unlock` | client | `{type, variant}` | `{job_id}` | `busy`, `no_profile`, `bad_request` (job: `unknown_strain`, `already_unlocked`, `insufficient_funds`) | #184 |
| `admin_flagged_list` | admin | `{}` | `{players: [{user_id, trophies, stats}]}` | `admin_only` | #185 |
| `admin_report` | admin | `{from, to}` | `{days, retention}` | | #186 |

Job results can carry job-level errors (see [Error codes](#error-codes)): `invalid_layout`, `insufficient_funds`, `maxed`, `unknown_upgrade`, `profile_not_fresh`, `invalid_profile`, `layout_too_expensive`, `invalid_army`, `already_unlocked`, `unknown_strain`, `conflict`.

Client RPCs must be wrapped by `rejectForbiddenKeys(payload, ["populations", "memory", "wallet", "trophies", "unlocked_strains"])` (#185), except that `profile_import` reads only `layout` and `memory` from `local_profile` and drops everything else.

## Job protocol

Job record in collection `jobs`, key `job_id` (`nk.uuidv4()`):

```json
{"job_id": "", "type": "echo", "status": "queued|claimed|done|failed",
 "created_unix": 0, "claimed_unix": 0, "attempts": 0,
 "config_hash": "", "payload": {}, "result": null, "error": ""}
```

- `enqueueJob(nk, type, payload, configHash) -> job_id`: helper for other server modules. Payloads that belong to a user carry `payload.user_id`.
- `worker_claim` returns up to `max` queued jobs, oldest first, whose `config_hash` matches the worker's, and sets them `claimed`. Storage versions (OCC) stop two workers claiming one job. A job claimed more than 60 s ago is re-queued with `attempts + 1`. After 3 attempts it is `failed`.
- `worker_complete` sets `done` or `failed` and calls the type's `onComplete` handler (a registry map type to function).
- The worker runs `JobRules.process(cfg, job)` (`src/core/online/job_rules.gd`), which is pure: no network, files or `Time`. `now_unix` is the job's server-supplied timestamp. It returns `{"ok", "result", "error"}`. Unknown type returns `unknown_job_type`; a config-hash mismatch returns `config_mismatch`.
- Job types: `echo`, `profile_new`, `profile_tick`, `base_commit`, `collect`, `upgrade_buy`, `profile_import`, `raid_validate`, `army_spend`, `mutation_unlock`.
- The worker never trusts itself with state: every job payload includes the data it needs (profile copies, raid record) and the result is applied by the server.

### Profile jobs

Every change to the profile is a worker job (`profile_new`, `profile_tick`, `base_commit`, `collect`, `upgrade_buy`, `profile_import`; rules in `src/core/online/profile_jobs.gd`). The payload carries `profile` (the stored copy), `profile_version` (its storage version) and `now_unix` (server time). The worker returns `result.profile` and `result.snapshot`.

- **Serialisation:** one in-flight profile job per user, held in `profile_lock/main` (a lock older than 120 s is ignored). A second mutating RPC returns `busy`; `profile_get` instead returns the stored copy with `busy: true` and the pending `job_id`.
- **onComplete** writes `profile/main` (read 1) and `base/snapshot` (read 2) with OCC on `profile_version`. On a version conflict the job is re-enqueued once with the newer profile; the original job's result becomes `{requeued_as}` and `job_status` follows it. A second conflict fails the job with `conflict`. A late `profile_new` never replaces an existing profile.
- **Client:** works optimistically on a cached copy, sends one `base_commit` when leaving Synthesis or tapping Save, and reloads the server copy on any rejection.

### Raid jobs

`raid_start` freezes the defender's `base/snapshot` into `raids/<raid_id>`, sets the defender's `under_attack_until_unix = now + 600` (and `under_attack_raid_id`), records the attacker's pathogen pools and sets the attacker's `open_raid_id`. `raid_submit` stores the army and the client's final hash and enqueues `raid_validate` with `{raid, attacker_profile, defender_profile, now_unix}`.

The worker (`src/core/online/raid_jobs.gd`) checks the army (pathogen types, known strains, deploy-ring cells, affordable), re-simulates with the server seed and returns:

- `attacker_patch`: `{wallet_delta, pathogen_pools, raid_counter_inc}`; `attacker_profile` (the whole result, for tests); `defender_patch`: `{atp_lost, amino_gained, memory, structure_pools}`; `res` (the `RaidResolver` result); `army_cost`; `server_final_hash`, `hash_match`; `battle` (for the defense log).
- onComplete applies the patches to the **current** profiles (OCC, three tries, additive and floored at 0), refreshes the defender's snapshot, marks the raid `done` (its record keeps everything except `battle`), clears both locks and writes the raw result to `defense_log/<raid_id>` until AM-09 (#183) defines the entry.
- A rejected validation marks the raid `rejected`, clears the locks and enqueues `army_spend` with the submitted army, so a retry is never free.
- `raid_cancel` (before submit only) ends the raid. The server never sees an army before `raid_submit`, so the army is charged only when the client reports it in `army`; an expired raid costs nothing.
- Expiry is lazy: `raid_start` / `raid_submit` expire the caller's and the target's stale raid, and `worker_claim` sweeps at most 50 open raids.

### Defense log

`raid_validate`'s onComplete writes `defense_log/<raid_id>` for the defender (`defense_log.ts`): `raid_id, attacker_id, attacker_name, created_unix, outcome, trophies_delta, atp_lost, amino_gained, memory_changes, evolution (the defender's structure pools only, from the worker's defense_info), army (counts by type), ticks, battle, seen`. At most 50 per user; the oldest are deleted on write. `defense_log_list` returns newest first with an offset cursor; `defense_log_get` returns the full entry to its owner only; `defense_log_mark_seen` flips `seen`. On entering Living Base online the client folds the unseen entries into one "While you were away" summary and marks them seen. Revenge is a normal `raid_start` on `attacker_id` (shields still apply).

### Trophies, matchmaking and shield

- The `pvp` block of `data/game_rules.json` (placeholders) is bundled with the server; the client only displays it. It is required when the `online` flag is on.
- `profile_new` starts a player at `pvp.start_trophies`; the leaderboard `trophies` (descending, `set`, created in `InitModule`, server-written only) gets a record when the profile is first stored and whenever a raid changes trophies.
- `raid_validate` returns `trophies` (`Trophies.settle`: `delta = clamp(base + (defender - attacker) / divisor, min, max)`; an attacker win moves `delta`, a defender win moves `delta / 2` the other way; nobody drops below 0), `trophies_delta` in both patches and `shield_until_unix = now + shield_hours * 3600` in the defender patch. The server only adds the deltas (floored at 0) and sets the shield.
- `raid_start` ends the attacker's own shield (`shield_until_unix = 0`) and records `recent_opponents[defender_id] = now` on the attacker's profile (entries older than 7 days are dropped).
- `find_opponent` uses `leaderboardRecordsHaystack` (100 records around the caller). Candidates must be within `±band`, widening x2 up to `band_widen_steps` times, and not be the caller, shielded, under attack or a recent opponent. It picks one with server randomness and does not lock; `raid_start` locks. With no candidate it returns `{ai: true}`.
- `leaderboard_top` returns the top 50 and the caller's rank. Nakama 3.41 returns `ownerRecords[].rank` as 0, so the rank is taken from the top list or from a one-record haystack.

## Versioning

- **`config_hash` parity.** `GameConfig.content_hash` is computed from `data/*.json`. The server bundles the same data (#176). A client, job or worker whose hash differs from the server's is rejected with `update_required`.
- **Profile format.** `LivingBaseProfile.to_dict()` carries `format` / `version`. The worker migrates old profiles on load; the server stores whatever the worker returns.
- **Client version.** The client sends `client_version` (from `project.godot` `application/config/version`) with `profile_get`.
- **Minimum version.** The server holds a minimum client version; older clients get `update_required`.

## Security

- **Device auth only.** Clients authenticate with Nakama anonymous device auth. No passwords, email or social login.
- **Worker access.** The worker uses the server's `http_key` through `/v2/rpc/<id>?http_key=&unwrap` (server-to-server), never a user session. Worker RPCs reject calls that have a user context (`ctx.userId` set) with `worker_only`. Admin RPCs likewise require the http key (no user context).
- **No secrets in the repo.** Keys come from environment variables or the host's secret store. `.env` is gitignored.
- **No client-trusted state.** See the forbidden-keys guard above.
- **Rate limits.** Per-user token buckets, stored in the `ratelimit` collection (Nakama's JS runtime freezes module-level objects, so an in-memory map cannot be updated at request time). Limits (placeholders):

| RPC group | Capacity | Refill |
|---|---|---|
| reads (`profile_get`, `job_status`, `defense_log_*`, `leaderboard_top`) | 20 | 5 / s |
| `find_opponent` | 5 | 1 per 2 s |
| writes (`base_commit`, `collect`, `upgrade_buy`, `mutation_unlock`, `profile_import`) | 5 | 1 / s |
| raids (`raid_start`, `raid_submit`, `raid_cancel`) | 5 | 1 per 5 s |

Exceeding a bucket returns `rate_limited`.

## Runtime notes (Nakama JS)

- Nakama runs `InitModule` in one VM only but evaluates the script in every VM of its pool. Module state (the job handler registry) must be set up at top level in `main.ts`, never inside `InitModule`.
- Module-level objects are frozen after load: never mutate globals at request time. Keep state in storage.
- Nakama parses the script statically: `InitModule` and the functions passed to `registerRpc` must be top-level declarations (see `server/README.md`).

## Error codes

Lowercase snake_case strings. Common: `rate_limited`, `update_required`, `forbidden_field`, `bad_request`, `worker_only`, `busy`, `conflict`, `unknown_job`.
Profile: `invalid_layout`, `insufficient_funds`, `maxed`, `unknown_upgrade`, `profile_not_fresh`, `invalid_profile`, `layout_too_expensive`, `no_profile`, `unauthorized`.
Raid: `raid_in_progress`, `self_raid`, `shielded`, `under_attack`, `unknown_player`, `unknown_raid`, `not_open`, `expired`, `invalid_army`.
Strains: `already_unlocked`, `unknown_strain`.
Worker: `unknown_job_type`, `config_mismatch`.
