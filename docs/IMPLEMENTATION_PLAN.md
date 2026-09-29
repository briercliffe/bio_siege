# Bio Siege MVP: Implementation Plan

This plan builds the "Attack Your Own Base" sandbox from the MVP spec. It covers engine choice, architecture, the design gaps the spec leaves open, a milestone schedule for a 5-week build (with a 1-week buffer, so 6 weeks at most), and how the evaluation metrics get measured.

---

## 0. Key Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Engine | **Godot 4.x (GDScript)** | `AStarGrid2D` is built in and suits a 20x20 grid. Scenes are text files that diff well in git. It exports to desktop and web with no license friction, and a web build is the easiest way to hand to playtesters. |
| Rendering | 2D, geometric placeholders (colored shapes plus simple icons) | The spec rules out complex assets. Shapes also make it faster to tell what each unit is doing. |
| Simulation model | **Fixed-timestep, deterministic sim** (20 ticks/s) kept apart from the view layer | Combat can be tested headlessly, battles can be replayed, and the balance simulator (M5) can run thousands of fights. |
| Target platforms | Desktop (Windows/macOS/Linux) + Web. Input stays touch-compatible. | The spec says "tap", so every interaction is a single press/click. There are no hover-only affordances. |
| Stat data | JSON in `data/` loaded at startup, with hot reload in debug builds | Meets the spec requirement for "tweak without recompiling", and designers can iterate without restarting. |

---

## 1. Spec Gaps and Assumptions

The spec leaves several numbers and rules undefined. The defaults below are **placeholders in JSON** and get tuned during playtests. Each one should get sign-off from design before M3.

### 1.1 Grid and placement
- The grid is 20x20. Tile size is 32 px logically and the view scales it to fit.
- The **outer ring of 1 tile is the deployment zone** and cannot be built on. That leaves an 18x18 buildable interior. Without this rule, walls placed on the edge could leave no valid place to deploy.
- **The Nucleus is 2x2 and pre-placed at the grid center (tiles 9–10, 9–10).** The spec says both "player places" and "pre-placed, free". This plan resolves it as "free and auto-placed", and the player can **move** it during Synthesis. Making it movable is a stretch goal for M2.
- All other structures are 1x1.
- Structures can be sold during Synthesis for a **100% refund**. This is a sandbox, so iteration speed matters more than punishing mistakes.

### 1.2 Combat stats missing from the spec

The spec does not give damage, attack rate or range for pathogens, or attack rate for towers. Proposed values:

| Entity | Speed (tiles/s) | Damage | Attack interval | Range | Notes |
| --- | --- | --- | --- | --- | --- |
| Rhinovirus | 2.5 ("Fast") | 6 | 0.5 s | melee (adjacent) | 12 DPS |
| Bacteriophage | 1.5 ("Med") | 20 | 1.0 s | melee | **x3 vs Macrophage/B-Cell** (anti-defense) |
| Biofilm | 0.75 ("Slow") | 25 | 1.5 s | melee | ~17 DPS, soaks tower fire |
| Macrophage | — | 40 AoE | 1.0 s | 2 tiles | Splash radius 1 tile around the target |
| B-Cell | — | 75 | 1.2 s | 6 tiles | Projectile at 10 tiles/s. Hit is guaranteed (homing). |

### 1.3 Targeting rules (these decide whether pathfinding is legible)
- **Walls are never chosen as targets.** A pathogen attacks a wall only when the wall blocks its path.
- "Nearest" means **straight-line distance from the unit to the structure's center**. Ties go to the lowest structure ID, so the result is deterministic and never random.
- Bacteriophage chooses the nearest Macrophage/B-Cell. If none remain, it falls back to the nearest structure of any kind.
- A unit locks its target and keeps it until the target dies. It does **not** retarget just because something closer appears. This makes behavior easier to predict.
- Towers target the nearest enemy in range, with ties going to the lowest unit ID. A tower keeps its target until the target dies or leaves range.

### 1.4 Pathing through walls
If walls are simply impassable, a fully enclosed base leaves the attackers with no path at all. This plan uses the approach that Clash-style games use:
- In `AStarGrid2D` every structure tile is **passable with a high weight**, never marked solid. The weights are Wall = 10 and Tower = 15, both tunable in JSON.
- A unit follows its path until the next tile is occupied. If that tile belongs to its target, it attacks the target. Otherwise it attacks the **blocking structure**. Once the blocker is destroyed, the path is recalculated.
- The result is that pathogens go around walls when a detour is short and break through when it is long. That behavior is readable and tunable.

### 1.5 Path recalculation (spec: "only when a wall or structure is destroyed")
- Pathfinding lives in a single shared `PathService`. When a structure is destroyed, it sets that tile's weight to 1 and bumps a `grid_version`.
- A unit recalculates its path when `grid_version` has changed **or** its target has died. Recalculations are spread across ticks, with at most N units per tick, to avoid frame spikes when the army is large.
- Path results are cached per (target cell, source cell) within a single `grid_version`, so a swarm heading for the same target shares work.

### 1.6 End conditions
- **Attacker wins** when the Nucleus reaches 0 HP.
- **Defender wins** when every deployed pathogen is dead **and** no pathogens remain undeployed.
- **Safety timeout: 3 minutes.** When the timer expires the Defender wins. This prevents soft-locks in edge cases, and the timeout is also logged as its own metric.
- "Launch Attack" is disabled when the army is empty.

### 1.7 Economy flow
- The single pool starts at 1000 ATP. Synthesis spends from it, and whatever is left carries into Incubation, as the spec requires.
- In Incubation, a unit is **bought into a reserve** first and then **deployed by tapping** a perimeter tile. One tap deploys one unit of the selected type. Holding or dragging deploys one unit every 0.1 s. Units left undeployed at launch are placed on random perimeter tiles; a seeded RNG keeps this deterministic.
- Once Infection starts, deployment is closed. This is the simplest rule for the MVP, and allowing live deployment during combat is an open question for playtests.

### 1.8 Post-battle loop (important for measuring "pivot friction")
The results screen offers three options:
1. **Re-raid**: keep the same base and army budget, clear the army, and return to Incubation.
2. **Edit base**: return to Synthesis with the layout intact.
3. **New base**: reset to 1000 ATP.

---

## 2. Architecture

```
bio_siege/
├── project.godot
├── data/                      # Designer-tunable JSON
│   ├── structures.json
│   ├── pathogens.json
│   └── game_rules.json        # start ATP, grid size, wall weights, timeout, tick rate
├── src/
│   ├── core/                  # Pure logic: RefCounted, no Nodes, headless-testable
│   │   ├── config.gd          # JSON loader + schema validation + hot reload
│   │   ├── grid_model.gd      # 20x20 TileState enum, occupancy, placement rules
│   │   ├── economy.gd         # ATP pool, purchase/refund
│   │   ├── path_service.gd    # AStarGrid2D wrapper, weights, grid_version, path cache
│   │   ├── targeting.gd       # Deterministic target selection (pathogens + towers)
│   │   ├── sim/
│   │   │   ├── battle_sim.gd  # Fixed-tick loop; owns entities; emits events
│   │   │   ├── structure_state.gd
│   │   │   ├── pathogen_state.gd
│   │   │   └── projectile_state.gd
│   │   └── rng.gd             # Seeded RNG
│   ├── game/
│   │   ├── game_state_machine.gd   # Synthesis → Incubation → Infection → Results
│   │   └── session.gd              # Holds base layout, ATP, army between phases
│   ├── view/                  # Nodes: render sim state, pooled visuals, interpolation
│   │   ├── grid_view.gd
│   │   ├── structure_view.gd
│   │   ├── pathogen_view.gd
│   │   ├── projectile_view.gd
│   │   └── node_pool.gd       # Generic object pool
│   ├── ui/
│   │   ├── hud_build.tscn/.gd
│   │   ├── hud_spawn.tscn/.gd
│   │   ├── hud_combat.tscn/.gd
│   │   ├── results.tscn/.gd
│   │   └── theme_build.tres / theme_spawn.tres
│   └── telemetry/
│       └── session_logger.gd  # Writes JSONL per playtest session
├── tests/                     # GUT unit + integration tests
└── tools/
    └── balance_sim.gd         # Headless: run N battles from saved bases/armies, output CSV
```

### 2.1 Layering rules
- **`core/` never references Nodes or scenes.** The sim advances with `step(dt_fixed)` and communicates only through emitted events such as `unit_spawned`, `damage_dealt`, `structure_destroyed` and `battle_ended`.
- **`view/` only reads sim state and listens to events.** Between ticks it interpolates positions so movement looks smooth at 60 fps.
- The **state machine** swaps in the HUD for each phase and sets which input mode is active, and it holds the single `Session` object.

### 2.2 Data schema (example)
```json
// data/structures.json
{
  "macrophage": {
    "display_name": "Macrophage", "cost": 100, "hp": 500, "footprint": [1,1],
    "attack": { "damage": 40, "interval": 1.0, "range": 2.0, "splash_radius": 1.0 },
    "path_weight": 15, "is_targetable": true, "tags": ["defense"]
  }
}
// data/pathogens.json
{
  "bacteriophage": {
    "display_name": "Bacteriophage", "cost": 40, "hp": 80, "speed": 1.5,
    "attack": { "damage": 20, "interval": 1.0, "range": 1.0 },
    "targeting": { "priority_tags": ["defense"], "fallback": "nearest" },
    "damage_multipliers": { "defense": 3.0 }
  }
}
```
When the config loads, it is validated against the schema: required keys, positive numbers and known tags. A bad value gives a readable error on screen, and the game never silently falls back.

### 2.3 Object pooling
- `NodePool` pre-warms **100 pathogen views**, which covers the worst case of 1000 ATP / 10 = 100 Rhinoviruses, plus **64 projectile views** and **64 hit VFX**.
- The sim uses flat arrays of state objects that are reused between battles, so it allocates nothing per tick.

---

## 3. Milestones

Five weeks of build plus one week of buffer and playtest fixes. Each milestone ends with something that can be demoed.

### M0: Project Skeleton (Days 1–2)
- Godot project, folder layout, GUT test framework, and a CI workflow on GitHub Actions that runs headless tests and does a web export.
- `config.gd` with JSON loading and validation. All three data files hold the spec values plus the placeholder values from section 1.2.
- `game_state_machine.gd` with empty phase scenes and debug buttons for moving between phases.
- **Exit:** CI is green, and a headless test confirms the config loads.

### M1: Grid & Synthesis (Build Mode) (Days 3–7)
- `grid_model.gd` with the tile states (`Empty`, `Wall`, `Tower`, `Nucleus`, and `DeployZone` as a derived state) and the placement rules: in bounds, not in the deploy ring, not occupied, enough ATP.
- `economy.gd` for spending and refunds.
- Grid view with a placement ghost that shows valid/invalid in green/red and tap-to-place/tap-to-sell. The Nucleus is auto-placed.
- Build HUD in the blue/white theme: ATP at top-left, a scrollable tray with the three structures at the bottom, and "Finalize Base" at top-right.
- Tests cover placement validity, ATP accounting and sell refunds.
- **Exit:** A player can build a base, see ATP go down, and finalize it.

### M2: Incubation (Spawn Mode) (Days 8–10)
- A transition screen or banner: "Switching sides — you are now the Pathogen". The palette changes to red/green. This transition is itself a playtest variable (see section 5).
- Spawn HUD: remaining ATP, a tray with the three pathogens and a counter for each, and "Launch Attack".
- The deployment ring is highlighted in green. Tapping it deploys from the reserve, and tapping a deployed unit before launch returns it to the reserve.
- Stretch goal: moving the Nucleus during Synthesis.
- **Exit:** A player can buy and position an army and then launch.

### M3: Battle Simulation Core (Days 11–17) *(highest-risk milestone)*
- `path_service.gd`: `AStarGrid2D` with weighted structure tiles, `grid_version`, a path cache and recalculation budgeted across ticks.
- `targeting.gd`: every rule in section 1.3, with unit tests for each tie-break and fallback case.
- `battle_sim.gd`: the fixed tick loop. The pathogen state machine is `Seeking → Moving → Attacking(target|blocker) → Dead`. Towers acquire targets and fire on a cooldown. The Macrophage has AoE, and the B-Cell fires homing projectiles.
- Win/loss and timeout from section 1.6.
- **Integration tests** (headless, fixed seed):
  - An open field with one Nucleus: Rhinoviruses walk straight to it and destroy it.
  - A Nucleus fully walled in: units break through the wall on the cheapest side.
  - Bacteriophage skips a nearer wall/Nucleus and goes for a B-Cell.
  - The same seed and inputs produce an identical outcome (determinism).
  - When a structure is destroyed, only the affected units recalculate paths (checked with a counter).
- **Exit:** A battle between a saved base and a saved army runs headlessly and produces a correct, repeatable result.

### M4: Infection (Combat View) & Full Loop (Days 18–22)
- Pooled views for pathogens, projectiles and hit VFX. Health bars appear on damaged entities, a flash plays on hit, and a death puff plays when an entity dies.
- **Legibility aids:** a thin "intent line" runs from each pathogen to its locked target (toggle in the HUD, on by default for playtests), and a blocker gets a crack overlay when it is being attacked.
- Combat HUD: a timer, the Nucleus HP bar, and pathogens alive/total.
- Results screen with Re-raid / Edit base / New base.
- **Exit:** The full Synthesis → Incubation → Infection → Results loop can be played start to finish.

### M5: Telemetry, Balance Tooling & Polish (Days 23–25)
- `session_logger.gd` writes one JSONL file per session with these events: phase durations, structures built and sold, ATP split between base and army, army composition, the outcome, the Nucleus HP remaining, the battle length, and whether the timeout fired.
- `tools/balance_sim.gd`: run `godot --headless -s tools/balance_sim.gd -- --base=b.json --army=a.json --runs=500` to get win rate and average time-to-kill as CSV. The designer runs this after each JSON tweak.
- Save and load for bases and armies as JSON, so playtesters can share layouts and the balance sim can use them.
- A pass on sound placeholders, a web export for playtesters, and a short "How to play" overlay.
- **Exit:** A web build is deployed to testers and telemetry is being captured.

### Buffer / Playtest Round 1 (Week 6)
- Run internal playtests, then tune the JSON values from telemetry and the balance sim, and fix whatever bugs come up.

---

## 4. Risk Register

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Pathing behavior feels random, which undermines evaluation metric 2 | High | Deterministic tie-breaks, target lock, intent lines, and integration tests asserting the expected targets |
| Wall weight tuning is either too high (units flow around the whole base) or too low (walls do nothing) | Med | The weight is in JSON. The balance sim sweeps the weight and reports how often units break through versus detour. |
| Swarm clumping: 100 units stacked on one tile look confusing | Med | No unit collision in the MVP. Each unit gets a small deterministic visual offset, and physical collision is skipped. |
| Spikes when many units recalculate paths after a wall breaks | Low | Per-tick recalculation budget and a shared path cache |
| Shared ATP pool degenerates, with the player spending everything on the base | Med | This is exactly what the playtest measures. Telemetry records the base/army split. The results screen shows the split so players notice it. |
| Scope creep toward out-of-scope features | Med | Any new feature needs a matching evaluation question from section 6 of the spec |

---

## 5. Mapping Evaluation Metrics to Instrumentation

| Spec Question | What we measure | How |
| --- | --- | --- |
| **1. "Pivot" friction** | Time spent on the transition screen, Incubation duration, how often players pick Re-raid vs Edit base, and a post-session 1–5 rating | Telemetry, plus a 3-question in-game survey on the Results screen (can be skipped) |
| **2. Pathfinding legibility** | Before launch, the tester predicts which structure falls first, and the prediction is compared with what actually happens | Optional "Predict" tap during Incubation that is logged against the first structure destroyed. Facilitator notes. |
| **3. Economy balance** | How ATP is split between base and army, the win rate for each split, and how often players change their base after a raid | Telemetry plus a scatter plot from the aggregated JSONL (script in `tools/`) |

Run the playtest with ten or more sessions across three or more testers. Before playtesting starts, define what counts as a "go": for example, a median pivot rating of 3.5 or higher and a prediction accuracy of 60% or higher.

---

## 6. Definition of Done (MVP)

- [ ] The full loop can be played on the web build with no debug tools.
- [ ] Every value in the entity tables comes from JSON and hot-reloads in debug builds.
- [ ] Battles are deterministic for a given seed, and the headless test suite is green in CI.
- [ ] 100 Rhinoviruses against a base full of towers holds 60 fps on a mid-range laptop browser.
- [ ] Telemetry JSONL is captured for every session, and the balance sim runs from the CLI.
- [ ] Every assumption in section 1 has been reviewed and signed off by design, or overridden.

---

## 7. Open Questions for Design

1. Can the player move the Nucleus, or is it fixed at the center?
2. Should deployment stay open during Infection, as in Clash-style games, or close at launch?
3. Should destroyed-but-free structures be refunded between re-raids? The current plan rebuilds the base at full HP for free on Re-raid.
4. Should the Bacteriophage's anti-defense role come from a damage multiplier (current plan), from targeting only, or from both?
5. Is 3 minutes the right safety timeout, or should a timeout count as a draw instead of a Defender win?
