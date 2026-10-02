# Bio Siege: Development Conventions

This project uses Godot 4.7.2-stable (standard build, GDScript for the game; TypeScript for `server/`) with GUT 9.7.1 for testing. All contributors and automated agents must adhere to the following rules:

1. **Language:** GDScript **for the game and the validation worker**, with static typing everywhere (e.g. `var hp: int = 0`, `func f(a: int) -> void`). Use `class_name` for every script in `src/core/`. Server code in `server/` is TypeScript (strict) for the Nakama runtime (see `docs/SERVER_PLAN.md`).
2. **Naming:** `snake_case` for files, functions, and variables; `PascalCase` for `class_name`; `UPPER_SNAKE` for constants.
3. **Layering (Implementation Plan Section 2.1):**
   - `src/core/**` must never reference `Node`, scenes, `Input`, `OS`, `Time`, `get_tree()`, or autoloads. Core classes extend `RefCounted`.
   - `src/view/**` may read core state but must never modify it.
   - UI goes in `src/ui/**`.
   - Glue code (state machine, session, autoloads) goes in `src/game/**`.
   - `src/game/net/**` is the only place that talks to the network.
   - `src/core/online/**` holds pure job rules (no network, no `Time`).
   - `server/**` never re-implements a game rule. Rules run in the headless Godot worker.
4. **Determinism:** Simulation code in `src/core/sim/**` uses **ints only**, with no `float` math. Distances are represented in milli-tiles (1 tile = 1000 milli-tiles) and time is represented in ticks. Floats are permitted only when converting configuration values at load time.
5. **Data:** Stat numbers live in `data/*.json` and must never be hard-coded in scripts. Do not change JSON values unless an issue explicitly requests it.
6. **Tests:** Every issue that adds or modifies code in `src/core/**` must add GUT tests in `tests/unit` or `tests/integration`. `tools/run_tests.sh` must pass cleanly before any PR is opened. Test framework is GUT 9.7.1 vendored in `addons/gut/`. `server/` changes need `npm test` in `server/` to pass. `tools/run_tests.sh` runs it when `node` is installed and prints a skip line otherwise.
7. **Art:** Do not add outside art, audio, fonts, or 3D models. Visuals are geometric placeholders drawn in code (`_draw()`) using Godot's default font, adhering to the art guidelines in plan section 0.
8. **Input:** Handle `InputEventScreenTouch` and `InputEventScreenDrag` only; mouse events are emulated as touch via `input_devices/pointing/emulate_touch_from_mouse=true`. Every tappable control must be at least 48x48 px, with no hover-only features.
9. **Commits and PRs:** One PR per issue. Reference the issue with `Closes #N` in the PR description body.
10. **Local setup:** Run `tools/install_godot.sh` first to set up Godot 4.7.2, then run `tools/run_tests.sh` to run the test suite. `tools/run_server.sh` starts a local Nakama with Docker for online work.
11. **Vendored code:** Third-party code lives only in `addons/` (GUT, the Nakama Godot client) and `server/node_modules` (not committed). Record each with its version and licence in `addons/README.md`.
