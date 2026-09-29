# Bio Siege: Development Conventions

This project uses Godot 4.4.1-stable (standard build, GDScript only) with GUT 9.4.0 for testing. All contributors and automated agents must adhere to the following rules:

1. **Language:** GDScript with static typing everywhere (e.g. `var hp: int = 0`, `func f(a: int) -> void`). Use `class_name` for every script in `src/core/`.
2. **Naming:** `snake_case` for files, functions, and variables; `PascalCase` for `class_name`; `UPPER_SNAKE` for constants.
3. **Layering (Implementation Plan Section 2.1):**
   - `src/core/**` must never reference `Node`, scenes, `Input`, `OS`, `Time`, `get_tree()`, or autoloads. Core classes extend `RefCounted`.
   - `src/view/**` may read core state but must never modify it.
   - UI goes in `src/ui/**`.
   - Glue code (state machine, session, autoloads) goes in `src/game/**`.
4. **Determinism:** Simulation code in `src/core/sim/**` uses **ints only**, with no `float` math. Distances are represented in milli-tiles (1 tile = 1000 milli-tiles) and time is represented in ticks. Floats are permitted only when converting configuration values at load time.
5. **Data:** Stat numbers live in `data/*.json` and must never be hard-coded in scripts. Do not change JSON values unless an issue explicitly requests it.
6. **Tests:** Every issue that adds or modifies code in `src/core/**` must add GUT tests in `tests/unit` or `tests/integration`. `tools/run_tests.sh` must pass cleanly before any PR is opened. Test framework is GUT 9.4.0 vendored in `addons/gut/`.
7. **Art:** Do not add outside art, audio, fonts, or 3D models. Visuals are geometric placeholders drawn in code (`_draw()`) using Godot's default font, adhering to the art guidelines in plan section 0.
8. **Input:** Handle `InputEventScreenTouch` and `InputEventScreenDrag` only; mouse events are emulated as touch via `input_devices/pointing/emulate_touch_from_mouse=true`. Every tappable control must be at least 48x48 px, with no hover-only features.
9. **Commits and PRs:** One PR per issue. Reference the issue with `Closes #N` in the PR description body.
10. **Local setup:** Run `tools/install_godot.sh` first to set up Godot 4.4.1, then run `tools/run_tests.sh` to run the test suite.
