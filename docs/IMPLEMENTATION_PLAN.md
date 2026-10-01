# Bio Siege: Implementation Plan

This plan has two parts.

- **Part I (sections 0–7): the MVP.** It builds the "Attack Your Own Base" sandbox from the MVP spec. It covers engine choice, architecture, the design gaps the spec leaves open, a milestone schedule for a 5-week build (with a 1-week buffer, so 6 weeks at most), and how the evaluation metrics get measured. The MVP scope is unchanged from the spec.
- **Part II (sections 8–15): the full game.** It covers the dual economy, the extended immune defenses and pathogen roster, and clan play. It shows how each system conflicts with or extends the MVP and stages it into post-MVP phases. Every phase is gated on the MVP's playtest results.

> **Design update (2026-09-29).** The MVP look is locked in [`MVP_UI_SPEC.md`](MVP_UI_SPEC.md): isometric view (view layer only), a 40x40 grid with a 2-tile deploy band, larger footprints (Nucleus 4x4, towers 3x3), and the final screen set and models. Where that spec conflicts with the grid, projection or rendering text below, the spec wins. Sections 0, 1.1, 1.9, 2.4 and the M1, M2 and M4 milestones are affected; the spec's section 7 lists the changes and section 6 lists the follow-up work. The data files have not been changed yet.

> **Design update (2026-09-29): identity.** [`IDENTITY_PROPOSAL.md`](IDENTITY_PROPOSAL.md) makes adaptation the core of the game: B-Cells learn strains, bases remember them between raids, pathogens mutate, and the self-raid gets a score and an Outbreak run mode. It replaces Phase 1.5 (section 9) with Phase 1.5: Identity, and reshapes parts of sections 10 to 13. Its section 9 lists the amended sections. The work is tracked in epic #85, and every mechanic is behind a feature flag that defaults to off.

# Part I: MVP

---

## 0. Key Decisions

| Decision | Choice | Rationale |
| --- | --- | --- |
| Engine | **Godot 4.x (GDScript)** | `AStarGrid2D` is built in and suits a 20x20 grid. Scenes are text files that diff well in git. It exports to desktop and web with no license friction, and a web build is the easiest way to hand to playtesters. |
| Rendering | 2D, geometric placeholders (colored shapes plus simple icons) | The spec rules out complex assets. Shapes also make it faster to tell what each unit is doing. |
| Simulation model | **Fixed-timestep, deterministic sim** (20 ticks/s) kept apart from the view layer | Combat can be tested headlessly, battles can be replayed, and the balance simulator (M5) can run thousands of fights. |
| Target platforms | Desktop (Windows/macOS/Linux) + Web. Input stays touch-compatible. | The spec says "tap", so every interaction is a single press/click. There are no hover-only affordances. |
| Art assets | **All in-house.** No outside models, sprites or textures are used. | See the note below. |
| Stat data | JSON in `data/` loaded at startup, with hot reload in debug builds | Meets the spec requirement for "tweak without recompiling", and designers can iterate without restarting. |


> **Note: art assets.** Do **not** use any outside models, sprites, textures or other art. That includes third-party marketplace assets such as the FlatPyramid Bacteriophage model. Every asset is generated in-house, from the MVP's geometric placeholders through to final production art. Outside images may serve only as a general style reference, and nothing from them may be copied, traced or imported into the project.

---

## 1. Spec Gaps and Assumptions

The spec leaves several numbers and rules undefined. The defaults below are **placeholders in JSON** and get tuned during playtests. Each one should get sign-off from design before M3.

### 1.1 Grid and placement
- The grid is 20x20. Tile size is 32 px logically and the view scales it to fit.
- The **outer ring of 1 tile is the deployment zone** and cannot be built on. That leaves an 18x18 buildable interior. Without this rule, walls placed on the edge could leave no valid place to deploy.
- **The Nucleus is 2x2 and pre-placed at the grid center (tiles 9–10, 9–10).** The spec says both "player places" and "pre-placed, free". This plan resolves it as "free and auto-placed", and the player can **move** it during Synthesis. Making it movable is a stretch goal for M2.
- All other structures are 1x1.
- Grid size and structure footprints come from JSON. Section 1.9 explains why 20x20 was chosen and how it gets checked in playtests.
- Structures can be sold during Synthesis for a **100% refund**. This is a sandbox, so iteration speed matters more than punishing mistakes.

### 1.2 Combat stats missing from the spec

The spec does not give damage, attack rate or range for pathogens, or attack rate for towers. Proposed values:

| Entity | Speed (tiles/s) | Damage | Attack interval | Range | Notes |
| --- | --- | --- | --- | --- | --- |
| Rhinovirus | 2.5 ("Fast") | 6 | 0.5 s | melee (adjacent) | 12 DPS |
| Bacteriophage | 1.5 ("Med") | 20 | 1.0 s | melee | **x3 vs Macrophage/B-Cell** (anti-defense) |
| Staphylococcus | 0.75 ("Slow") | 25 | 1.5 s | melee | ~17 DPS, soaks tower fire. This is the spec's "Biofilm" slot, renamed to match the full-game roster (see section 8). |
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

### 1.9 Grid size: is 20x20 big enough?
**Comparison with Clash of Clans.**
- The home village has a buildable area of about **44x44 tiles** inside a deploy-only border roughly 3 tiles wide, so the whole map is about 50x50.
- Buildings cover several tiles. The Town Hall is 4x4, most defenses are 3x3, some buildings and traps are 2x2, and walls and small traps are 1x1.
- A maxed base holds roughly 40–60 buildings plus about 250–325 wall pieces.
- Troops can be dropped anywhere except within about 1 tile of a building, not only at the map edge.

**Size measured in buildings.**
- A Clash defense is 3 tiles wide, so its base is about **15 defenses across**.
- The MVP's interior is **18 defenses across**: 18x18 buildable tiles with 1x1 towers.
- In building terms, 20x20 is already slightly bigger than a Clash base.

**The budget fills the grid long before the space does.**
- 1000 ATP buys roughly 5 towers and 30 walls. That is about 40 of the 320 buildable tiles, around 12%.
- Bases will be small clusters around the Nucleus, and attackers cross a lot of empty ground first.
- So the realistic risk is that the grid is **too empty**, not too small.

**The real limitation is granularity.**
- In Clash a wall is a third as wide as a defense, which allows tight compartments and funnels.
- In the MVP a wall is the same size as a tower. That gives fewer and blunter layout options.

**Decision.**
- The MVP keeps **20x20 with 1x1 structures**, which keeps pathing, ranges and balance simple.
- The assumption is checked in playtests (section 5, question 4).
- A finer grid of about 40x40 with multi-tile structures is planned for Phase 2 (section 11). The grid-scale hook in section 2.4 makes that mostly a data change.

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
│   │   ├── economy.gd         # Multi-currency wallet (MVP uses ATP only), purchase/refund
│   │   ├── status_effects.gd  # Generic timed modifiers: slow, root, disable, buffs, damage multipliers
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

### 2.4 Built for the full game
Almost every Part II mechanic depends on the items below. Each one is cheap to add during the MVP and expensive to retrofit later, so all of them are in the MVP milestones.

| Hook | Where | Why (Part II dependency) |
| --- | --- | --- |
| The wallet is a `currency → amount` map, not a single int | `economy.gd` (M1) | Amino Acids and DNA/Plasmids (section 10) |
| A generic status-effect system for timed modifiers | `status_effects.gd` (M3) | Mucous slow/trap, Bacteriophage hijack, B-Cell analysis, Dendritic buff, gene-transfer traits |
| Entity **tags** (`virus`, `bacteria`, `defense`, `resource`, `small`, `hidden`), with targeting priorities and damage multipliers keyed by tag | JSON + `targeting.gd` (M3) | Rhinovirus → Mitochondria becomes a JSON change, not a code change |
| A `levels` array per entity in the JSON (the MVP ships only level 1) | `config.gd` (M0) | Amino Acid upgrades |
| **Integer / fixed-point sim math**, with positions stored in milli-tiles | `core/sim` (M3) | Cross-platform determinism, so a server can re-simulate and validate raids (section 12) |
| Versioned JSON snapshots of bases and armies | M5 | Becomes the async multiplayer base format |
| A battle input log (seed plus timestamped deploy commands) | M5 | Replays, defense logs and server validation |
| A per-structure `visible_to_attacker` flag | `grid_model.gd` (M1) | Dendritic Cells |
| Feature flags in `game_rules.json` | M0 | Lets playtests A/B the stretch mechanics in section 9 |
| Grid size, footprints and a global `grid_scale` in `game_rules.json`. Ranges, speeds and splash radii are multiplied by the scale, and nothing assumes 20x20 or 1x1. | `config.gd`, `grid_model.gd` (M0–M1) | Moving to the finer grid in Phase 2 (section 1.9) becomes a data change, not a rewrite |

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
- `targeting.gd`: every rule in section 1.3, driven by tags, with unit tests for each tie-break and fallback case.
- `status_effects.gd` and integer/fixed-point math, as listed in section 2.4.
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
- `session_logger.gd` writes one JSONL file per session with these events: phase durations, structures built and sold, ATP split between base and army, army composition, the outcome, the Nucleus HP remaining, the battle length, and whether the timeout fired. For the grid-size check (section 1.9) it also logs **grid occupancy** (the share of buildable tiles used), the **time until the first pathogen reaches a structure**, and the number of walls placed.
- `tools/balance_sim.gd`: run `godot --headless -s tools/balance_sim.gd -- --base=b.json --army=a.json --runs=500` to get win rate and average time-to-kill as CSV. The designer runs this after each JSON tweak.
- Save and load for bases and armies as **versioned** JSON, so playtesters can share layouts and the balance sim can use them. Every battle also records a battle input log (seed plus deploy commands) that can be replayed.
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
| The 20x20 grid feels too empty (long walks before combat) or too coarse (walls as big as towers limit layouts) | Med | Grid size and footprints are data-driven. Section 5 question 4 measures it, and Phase 2 plans a finer grid (section 1.9). |
| Scope creep toward out-of-scope features | Med | Any new feature needs a matching evaluation question from section 6 of the spec |

---

## 5. Mapping Evaluation Metrics to Instrumentation

| Spec Question | What we measure | How |
| --- | --- | --- |
| **1. "Pivot" friction** | Time spent on the transition screen, Incubation duration, how often players pick Re-raid vs Edit base, and a post-session 1–5 rating | Telemetry, plus a 3-question in-game survey on the Results screen (can be skipped) |
| **2. Pathfinding legibility** | Before launch, the tester predicts which structure falls first, and the prediction is compared with what actually happens | Optional "Predict" tap during Incubation that is logged against the first structure destroyed. Facilitator notes. |
| **3. Economy balance** | How ATP is split between base and army, the win rate for each split, and how often players change their base after a raid | Telemetry plus a scatter plot from the aggregated JSONL (script in `tools/`) |
| **4. Grid size and granularity** *(added, section 1.9)* | Grid occupancy, time until first contact, walls placed, and whether testers call bases "empty", "cramped" or say walls feel "too chunky" | Telemetry plus one Results-screen survey question: "The map felt: too small / right / too big". Facilitator notes on layout complaints. |

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

---

# Part II: Full Game Vision & Post-MVP Roadmap

## 8. How the Full Vision Fits the MVP

Several full-game systems are explicitly out of scope in the MVP spec: secondary currencies, mutation, clans and gene transfer. Others change the behavior of entities the MVP already has. The table shows how each item is handled.

| Full-game item | Relationship to the MVP spec | Handling |
| --- | --- | --- |
| Mitochondria + ATP generation | The MVP has a fixed pool of 1000 ATP | Phase 2 |
| Amino Acids, DNA/Plasmids | Explicitly out of scope | Amino Acids in Phase 2, DNA/Plasmids in Phase 3 |
| Mucous Membrane slow + trap | The MVP wall only blocks paths | The slow is an **MVP stretch goal** (section 9). The trap is Phase 2, because nothing in the MVP roster is a "weak bacterium". |
| B-Cell 10 s "analysis" → 3x damage | Not in the spec | **MVP stretch goal**. It is a pure sim rule. |
| Dendritic Cells (hidden traps) | Hidden information means nothing when you built the base yourself | Built in Phase 2 against AI bases. They only matter fully in Phase 3. |
| Fever (global spell) | The defender is AI-controlled during a raid, so nobody is there to press a "panic button" | **Removed from the plan.** Moved to [FUTURE_FEATURES.md](FUTURE_FEATURES.md). |
| Rhinovirus targets Mitochondria first | The MVP has no Mitochondria | The MVP keeps "nearest structure". In Phase 2 the tag priority changes in JSON. |
| Bacteriophage hijacks towers | The MVP gives it x3 damage against defenses | **MVP stretch goal**: hijack instead of or in addition to the multiplier |
| Staphylococcus clumps into a Biofilm | The MVP has a "Biofilm" slow tank | **Renamed in the MVP now** (same stats). Clumping is an MVP stretch goal. |
| Parasites (dropship, spores) | A new unit | Phase 2 |
| Finer grid (about 40x40, multi-tile structures) | The MVP uses 20x20 with 1x1 structures (section 1.9) | Phase 2, if playtest question 4 shows the grid is too coarse or empty |
| Clans, gene transfer, Lymph Node, Pandemic Mode | Explicitly out of scope | Phases 4–5 |
| Coevolution (antigens, receptors, fitness-weighted mating; epic #141) | Not in the spec. Adds per-type genome pools and a damage multiplier, and defenders evolve too | **Phase 1.5**, behind the `coevolution` flag (section 9). Its snapshot `populations` block is the hook for Phases 3–5. |

## 9. MVP Stretch Mechanics (Phase 1.5)

Each mechanic below is a sim-only rule behind a feature flag. None of them needs new systems beyond the hooks in section 2.4. They are built only if M0–M5 finish early. Otherwise they become a 1–2 week Phase 1.5, and a second playtest round compares each one against the flag switched off.

**B-Cell analysis.**
- Each B-Cell tracks how long it has spent attacking each pathogen *type*, cumulatively.
- After 10 s on a type, that B-Cell deals **3x damage to that type** for the rest of the battle.
- The analysis belongs to the individual tower. Dendritic Cells in Phase 2 could share it between towers.
- The view shows a progress ring on the tower and an icon for each analyzed type.
- *Balance flag:* 75 × 3 = 225, which one-shots every unit except Staphylococcus. The base damage probably needs to drop to about 50. The balance sim decides.

**Bacteriophage hijack ("Wall-Breaker / Hijacker").**
- When a Bacteriophage reaches a Macrophage or B-Cell, it **injects** over a 2 s channel. If the phage dies during the channel, the injection is interrupted.
- A successful injection **hijacks** the tower for 8 s. **Decided:** the hijacked tower turns on neighbouring immune structures and fires at them instead of at pathogens. The balance sim must check that one phage can't unravel a tight tower cluster (tune damage, range and duration, or add a cooldown).
- The phage is consumed by the injection. This keeps it a specialist and prevents one phage from locking a tower permanently.
- For its wall-breaker role, the phage keeps the x3 multiplier against walls when a wall blocks its path.

**Staphylococcus Biofilm.**
- Staphylococcus units within 1.5 tiles of each other link into a Biofilm group. The groups are recomputed with union-find every 0.5 s.
- Damage to any member is **split evenly across the group**, and the group takes 25% less damage.
- The group moves at the speed of its slowest member and shares one target.
- Links break when members are more than 2 tiles apart.

**Mucous slow.** Pathogens on tiles next to a Mucous Membrane move at 50% speed. This can be applied as an aura status effect.

**Coevolution (epic #141, issues #142–#145).** Every fighting character type breeds, behind the `coevolution` flag (default `false`).
- Rhinovirus, Bacteriophage, Staphylococcus, Macrophage and B-Cell each keep a pool of genomes (starting value: 8). A genome is a few antigen slots and a few receptor slots.
- A character's receptors are scored against its target's antigens. A match hits harder (+25% each) and a miss hits softer (−25% each), with a floor of 1%. Walls and the Nucleus do not breed, and damage against them is unchanged.
- After a finished raid, fitness is damage dealt plus a survival bonus. The fittest genomes are drawn as parents, and each child is a per-slot crossover with at most one mutation.
- Generation 0 is wild: every slot is empty and every matchup is 100% until a mutation fills a receptor. The cost is the limited receptor slots, not a flat level.
- It sits **beside** B-Cell analysis, strains and immune memory. Bred antigens do not raise analysis and do not change the strain key, so the two bonuses never stack.
- It is built as four issues in order: CE-01 genome, match math and mating (#142); CE-02 battle damage and fitness (#143); CE-03 breeding after the raid and snapshot persistence (#144); CE-04 the read-only Coevolution panel, Results summary and identity doc (#145).
- All of it uses integer math and the seeded `Rng`. Breeding seed = `battle_seed + generation * 100003`, and `state_hash()` only gains `G:` lines for entities with a genome, so flag-off hashes are unchanged.
- It adds one optional `populations` block to the base snapshot. That block is the Phase 3 hook (section 12). This phase adds no matchmaking, no global gene pool and no PvP transport.

## 10. The Dual Economy

The core tension from the MVP carries forward: **ATP is shared between offense and defense**. The two new currencies each open up one side.

| Currency | Earned from | Spent on | Phase |
| --- | --- | --- | --- |
| **ATP (Energy)** | **Mitochondria** structures, which generate ATP over real time up to a storage cap. Offline time is computed from timestamps (server-side in Phase 3). Raid loot is taken from destroyed Mitochondria. | Building structures and training units | 2 |
| **Amino Acids** | Harvested from defeated enemies: each pathogen killed while defending, plus structures destroyed while raiding. The drop is a function of the victim's cost. | Upgrading **structural integrity**: the HP and damage levels of walls and towers, via the `levels` JSON | 2 |
| **DNA / Plasmids** (premium) | **Successful raids on other players only**, plus in Phase 2 debug raids on AI "wild infection" bases so the currency can be tested | The **Mutation Lab** (permanent pathogen trait unlocks) and gene-transfer donations (Phase 4) | 3 |

**Mutation Lab.** Each pathogen has a small trait tree, such as "Capsid Hardening: +15% HP" or "Rapid Replication: −20% train cost". A trait is a permanent modifier applied through the status-effect system. The unlocked traits are stored on the player profile on the server.

**Coevolution and the economy.** Breeding costs no currency. The limit is receptor slots, so flat HP or damage levels from Amino Acids stay cut or shrunk (the identity proposal's position, and epic #141 also puts them out of scope). The Mutation Lab and bred genomes are separate layers. The Lab unlocks hand-authored strain variants, which are stat tradeoffs. Breeding fills the antigen and receptor slots on top of them. The Lab must never unlock an allele or a genome directly, or it would bypass fitness selection.

*"Premium" is ambiguous:* it could mean "earned only through PvP" or "purchasable with real money". This plan implements the first. Monetization is an open question (section 15).

## 11. Extended Roster (Phase 2)

Phase 2 is a **single-player "Living Base"** build. The player raids AI-generated bases and defends against AI raids, which lets the whole roster and economy be tested before any server work.

### Immune system (defenses)

| Structure | Behavior | Implementation notes |
| --- | --- | --- |
| **Mitochondria** | Resource generator and storage. Can be targeted and holds loot. | Tag `resource`. The generation tick runs outside battle. |
| **Mucous Membrane** (upgraded wall) | Slows enemies (section 9) and **traps weak pathogens**, which are rooted for 2 s on contact | The trap keys on the `small` tag instead of "bacteria", because the roster has no weak bacterium. It catches Rhinovirus and Parasite spores. Whether that stays biologically honest is an open question. |
| **B-Cell** | Sniper tower firing antibodies, with the analysis mechanic | As in section 9 |
| **Macrophage** | Unchanged from the MVP | — |
| **Dendritic Cell** | **Hidden from the attacker.** It triggers when a pathogen comes within 1 tile, then reveals itself and gives defenses within 4 tiles +50% attack speed for 10 s. It fires once per battle and can also share B-Cell analysis within its radius. | Uses the `visible_to_attacker` flag. The attacker's view never gets hidden entities, so rendering them is filtered by what the attacker can see. |

### Pathogens (attackers)

| Unit | Behavior | Implementation notes |
| --- | --- | --- |
| **Rhinovirus** ("Goblins") | Fast and weak. Targets **Mitochondria first**, then the nearest structure. | A JSON change: `priority_tags: ["resource"]` |
| **Bacteriophage** | Wall-breaker and hijacker, as in section 9. Art direction: a "lunar lander" silhouette. | Its model is created in-house, like every other asset (see the art assets note in section 0). |
| **Staphylococcus** | A tank that forms a Biofilm (section 9) | — |
| **Parasite** ("Dropship") | Large and slow. It **burrows**: it is untargetable underground, ignores walls, and surfaces next to its target after a travel time. On death it **bursts into 4 spores**, which are fast, low-HP and tagged `small`. | A burrowed movement mode skips the weighted path and moves in a straight line at reduced speed. Spores come from the same object pool. |

### How Phase 2 units fit coevolution

New roster entries join the breeding set by adding their ids to `coevolution.types` in JSON (a data change, subject to CLAUDE.md rule 5). No code change is needed, because assignment keys on the type id.

| New unit | Breeds? | Adaptation |
| --- | --- | --- |
| **Parasite** and its spores | Parasite yes. Spores inherit the parent's genome index, not a pool of their own. | A burst of 4 spores must not double-count fitness. Damage dealt by spores is credited to the parent's genome index. |
| **Dendritic Cell** | Yes, as a defender | It becomes the **antigen presenter**. Within its radius it shares the antigens it has seen with nearby B-Cells, which is the in-game version of antigen presentation. It does not raise match damage directly. It lets the base's pools evolve toward what actually attacked it. |
| **Mitochondria** | No | A tissue like walls and the Nucleus. |
| **Mucous Membrane** | No | Its slow and trap are not scaled by match. |
| **Rhinovirus, Bacteriophage, Staphylococcus, Macrophage, B-Cell** | Yes (MVP set) | The Phase 2 retuning pass re-validates the 100% baseline and the ±25% step in the balance sim. The finer 40x40 grid changes the number of targets, so fitness totals shift. |

AI bases (Phase 2) start with wild pools and breed after each AI raid. Their pools are generated by the AI generator from a seed, and not saved from a human player.

### Finer grid (about 40x40)
Once the roster has more structure types (Mitochondria, Dendritic Cells, upgraded walls), move from the MVP's 20x20 grid to a finer, Clash-style grid. The reasoning is in section 1.9.

| Entity | MVP footprint | Phase 2 footprint (proposed) |
| --- | --- | --- |
| Nucleus | 2x2 | 4x4 |
| Macrophage, B-Cell, Mitochondria | 1x1 | 3x3 (Mitochondria possibly 2x2) |
| Dendritic Cell | — | 2x2 (hidden) |
| Mucous Membrane (wall) | 1x1 | **1x1**, so a wall is a third as wide as a tower and allows real compartments and funnels |

- `grid_scale` goes from 1 to 2. Ranges, speeds and splash radii scale automatically, and the balance sim re-validates each stat.
- The deploy zone can widen to Clash-style free deployment: anywhere outside a 1-tile buffer around buildings. That is a separate playtest decision.
- The start budget and wall cost may need retuning so that a typical base fills a sensible share of the larger area.

## 12. Async Multiplayer (Phase 3)

This is the "raid other players" layer that the MVP deliberately left out.

- **Backend: Nakama**, an open-source game server with a Godot client SDK. It provides accounts, storage, leaderboards, groups (used for clans in Phase 4) and server-side runtime code. The alternative is a custom service, which costs more to build.
- **Base snapshots:** the versioned JSON from M5 becomes the canonical format for defended bases.
- **Matchmaking:** pick an offline player's snapshot within a strength or trophy band. A defender gets a protection shield after being raided.
- **Authoritative results:** the client uploads the seed and the battle input log. A headless Godot validation worker re-simulates the battle, which only works because the sim is deterministic with integer math (section 2.4). Loot, Amino Acids and DNA are awarded from the server's result, never from what the client reports.
- **Replays and defense logs:** a replay is the stored inputs plus the base snapshot, re-simulated on the viewing client.
- **Mutation Lab** goes live here, because DNA can only be earned through PvP.
- **Populations travel with the snapshot.** An async raid loads the defender's tower pools (Macrophage, B-Cell) and the attacker's pathogen pools. Combat needs no new rule, because the damage formula already reads genomes (epic #141).
- **The server breeds, not the client.** The validation worker re-simulates the battle and then runs breeding with the same seed rule (`battle_seed + generation * 100003`). The client's `populations` block is never trusted as a result. A client could otherwise submit a hand-built genome with every receptor matched to the defender's antigens. The server stores the canonical pools and checks an uploaded block against them.
- **Pool ownership (decided).** A defender's Macrophage and B-Cell pools evolve against every attacker who raids them, which makes popular builds counter themselves, as in the identity proposal's self-balancing meta. Each player's attacker pools still evolve only from their own raids. The server applies the breed after each validated raid and writes a defense-log entry showing the new generation, so an offline player can see what changed.
- **Anti-cheat and telemetry.** Log receptor-hit rate and generation count per player, and flag pools that match a defender's antigens too well too fast.

## 13. Clans & Social Play (Phases 4–5)

| Feature | Design | Implementation notes |
| --- | --- | --- |
| **Clans** | Membership, roles and chat | Nakama groups and chat channels |
| **Horizontal Gene Transfer** (donations) | A player requests a trait such as "Speed Buff" or "Antibiotic Resistance". Clanmates donate it from traits they have unlocked, and it applies **only to the requester's next raid**. **With coevolution, a donor can also donate a receptor** (a plasmid carrying one allele) taken from one of their bred genomes. It fills one receptor slot in one genome of the requester's pool for the next raid only. | Donated traits are temporary status modifiers. A donated receptor is a temporary overlay on `Genome.receptors` that is discarded before breeding, so it can't enter the permanent pool through the next mating step. The rules include a request cooldown and a cap of about 3 traits per raid, and the donor pays a small DNA cost. |
| **Lymph Node** (clan castle, **replaces the Nucleus as HQ and win condition**) | Houses defensive **memory cells** donated by clanmates. When pathogens come into range, the memory cells deploy as mobile defenders. | This is the first **mobile defender** entity, so defenders get pathing too. **Decided:** the Lymph Node replaces the Nucleus. From Phase 4 it is the structure attackers must destroy, and every base has one, so a player without a clan still has a Lymph Node with its donation slots empty. This changes a core MVP rule, so Phase 4 has to migrate the `nucleus` id, snapshots, footprint, tag priorities and tests. Donations are split in two: plasmids for offense and memory cells for defense. Under the identity proposal the Lymph Node donates strain memory (vaccination). **Memory cells can also carry a donated B-Cell genome**, and whether the mobile defender counts as a breeding type is still undecided. |
| **Pandemic Mode: Patient Zero** (Phase 5a) | The clan pools its mutated pathogens against a huge, heavily fortified AI boss base. Damage **persists across members' attacks** over a 48 h window. | PvE, so no clan matchmaking is needed. The boss base keeps persistent server-side HP state. **The boss's Macrophage and B-Cell pools breed across members' attacks too**, so the clan has to rotate receptors, because the boss's antigens and tower genomes shift with each attempt. Build this first. |
| **Pandemic Mode: Herd Immunity** (Phase 5b) | Clan versus clan: each clan's member bases form a "Herd Immunity" network that the other clan attacks. | Needs war scheduling, clan matchmaking and war-state storage. **Gene flow:** a tower genome can spread to neighbouring member bases inside the network, so a lucky mutation helps the whole clan. Build this last. |

## 14. Roadmap Summary

The estimates are rough and assume 2–3 engineers. They should be re-estimated after the MVP. **Each phase starts only if the previous phase's playtest gate passes.**

| Phase | Contents | Rough duration | Gate to proceed |
| --- | --- | --- | --- |
| **1. MVP** | Part I | 6 weeks | Go/no-go targets from section 5 |
| **1.5. Stretch mechanics** | Section 9, A/B-tested behind feature flags, plus **Coevolution** (epic #141, issues #142–#145, flag `coevolution`) | 1–2 weeks. About 3–4 weeks with the identity work (the identity proposal's estimate). Coevolution adds about 1–2 weeks and the four issues run in a chain. | Each mechanic improves the legibility or fun ratings, or it is cut. **Coevolution also has to show that a bred pool beats a wild pool by generation 3–5 without hurting prediction accuracy.** |
| **2. Living Base** | Mitochondria, ATP generation, Amino Acids and upgrades, Dendritic Cells, Parasites, Mucous trap, a finer ~40x40 grid, AI bases and AI raids | 6–8 weeks | The economy loop holds attention over repeated single-player sessions |
| **3. Async multiplayer** | Nakama backend, accounts, snapshots, matchmaking, server validation, replays, DNA/Plasmids, Mutation Lab | 10–14 weeks | Closed alpha retention and anti-cheat validation |
| **4. Clans** | Clans, chat, gene transfer, Lymph Node and memory cells | 8–10 weeks | Share of players in a clan; donation usage |
| **5. Pandemic Mode** | 5a Patient Zero, then 5b Herd Immunity wars | 6–8 weeks each | — |

## 15. Design Decisions (Full Game)

These were open questions and are now decided.

| # | Question | Decision |
| --- | --- | --- |
| 1 | Premium currency | DNA/Plasmids are **earned in PvP only**. No purchase, no store. Monetization is revisited after the closed alpha. |
| 2 | Lymph Node vs Nucleus | The Lymph Node **replaces the Nucleus** as HQ and win condition in Phase 4 (see section 13). |
| 3 | Bacteriophage hijack | A hijacked tower **turns on neighbouring immune structures**. The phage is still consumed. Needs balance-sim checks (section 9). |
| 4 | Fever | **Removed from the plan** and moved to [FUTURE_FEATURES.md](FUTURE_FEATURES.md). |
| 5 | Mucous trap targets | The trap keys on the `small` tag (Rhinovirus, Parasite spores). No new unit. |
| 6 | Amino Acid sources | **Both defending and raiding.** |
| 7 | B-Cell analysis scope | **Per tower.** A Dendritic Cell shares analysis with nearby towers (Phase 2). |
| 8 | Gene-transfer traits | A **fixed short list**, and not every Mutation Lab trait. |
| 9 | Deploy zone | **Keep the edge band.** The grid is 40x40 and already in the MVP. |
| 10 | Coevolution pool ownership | A defender's tower pools **evolve against every attacker** that raids them. A server concern for Phase 3, and a global gene pool is still out of scope. |
| 11 | Coevolution and Phase 2 units | The Dendritic Cell shares **antigens and analysis only**, not genomes. Parasite spores **inherit the parent's genome index**. |
| 12 | Donated receptors | Gene transfer donates **receptors only**, for one raid. No antigen donation. |

**Still open.** How to balance a one-phage hijack chain (item 3), and how a defender whose pools evolve while offline (item 10) is told what changed. The second one needs a defense-log entry that shows the new generation.
