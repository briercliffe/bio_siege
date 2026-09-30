# Bio Siege: Model and Animation Pipeline Plan

**Status: proposed.** Companion to [`MVP_UI_SPEC.md`](MVP_UI_SPEC.md), which locks the look, projection and model silhouettes. This plan says how those models get built in Godot and animated, and how the work splits into issues.

---

## 1. Goals and constraints

Goals:
- Every pathogen and structure is drawn as a layered, shaded model and animates: idle, move, attack, hit reaction and death.
- Animation reads clearly at the in-game tile size (14 px), including for a swarm of a few hundred units.
- Animation never changes the outcome of a battle.

Constraints, from `CLAUDE.md` and the locked spec:
- **Rule 7:** no outside art. Visuals are geometric placeholders drawn in code with `_draw()`, using Godot's default font.
- **Rule 3:** `src/view/**` may read core state but must never modify it. No core file may reference `Node`, `Input`, `Time` or `get_tree()`.
- **Rule 4:** `src/core/sim/**` is integer-only. Floats are fine in `src/view/**`.
- **Rule 8:** touch input only, with hit-testing by tile, never by sprite pixels.
- **Rule 9:** one PR per issue.
- The projection is isometric and view-only (spec section 3). Models are anchored at the ground centre of their footprint and sized in tile units `T`.

---

## 2. Approach

| Option | What it is | Verdict |
| --- | --- | --- |
| **A. Procedural rigs in `_draw()`** | Each model is a painter that draws shapes from a pose. Animation is a function of sim state. | **Chosen for the MVP.** Fits rule 7, no asset pipeline, and ports almost 1:1 from the canvas model sheet. |
| B. Scene rigs (`Polygon2D`, `Skeleton2D`, `AnimationPlayer`) | Editor-authored keyframes. | Good tooling, but conflicts with "drawn in code". Revisit after the MVP. |
| C. Baked sprite atlas | Render the procedural rigs into a texture atlas at load, then draw sprites. | **Held in reserve** as a performance step (section 6). The pose contract does not change. |
| D. Pre-rendered 3D or hand-drawn rigged 2D | In-house production art. | Post-MVP art upgrade (section 10). |

---

## 3. Architecture

```
BattleSim (core, ints)                       src/view/ (floats, read-only)
  pathogens[], structures[], projectiles[]     BattleSnapshotBuffer   keeps previous + current tick
  drain_events() -> Array[Dictionary]   --->   AnimDriver            state + events -> ModelPose
                                               UnitLayer             depth sort, one draw pass
                                               ModelPainter (per model)   pose -> draw calls
                                               EffectLayer           hit flash, bursts, scorch, splash
```

### 3.1 Files

```
src/view/
  iso_projection.gd        class_name IsoProjection     ground <-> screen, depth key
  battle_snapshot.gd       previous/current positions for interpolation
  anim/
    model_pose.gd          class_name ModelPose         plain data, no logic
    anim_driver.gd         class_name AnimDriver        pure functions, unit-testable
    easing.gd              class_name Easing
  models/
    paint_kit.gd           class_name PaintKit          sphere, ellipse, hex, bar, cylinder, sphere-cluster helpers
    model_painter.gd       class_name ModelPainter      base class: paint(ci, pose, t_px)
    rhino_painter.gd  phage_painter.gd  staph_painter.gd
    macrophage_painter.gd  bcell_painter.gd  nucleus_painter.gd
    wall_renderer.gd       connected-segment renderer, not a per-unit painter
  unit_layer.gd            class_name UnitLayer         the single draw pass for units and towers
  effect_layer.gd          class_name EffectLayer
  placeholder_shapes.gd    kept as the fallback and for HUD icons
tools/
  model_viewer.tscn + model_viewer.gd     dev scene (section 7)
```

Scripts in `src/view/` follow the same naming rules as the rest of the project: `snake_case` files, `PascalCase` `class_name`, static typing everywhere.

### 3.2 The pose contract

```gdscript
class_name ModelPose
extends RefCounted

enum Anim { IDLE, MOVE, WINDUP, STRIKE, RECOVER, HIT, DEAD }

var anim: Anim = Anim.IDLE
var facing_right: bool = true        # mirror rule from the spec, view-side only
var gait_phase: float = 0.0          # 0..1, advances with distance travelled
var attack_t: float = 0.0            # 0..1 across windup -> strike -> recover
var hit_t: float = 0.0               # 1 at the hit, decays to 0
var death_t: float = 0.0             # 0..1 across the death animation
var hp_frac: float = 1.0
var aim: Vector2 = Vector2.ZERO      # towers: direction to target on screen
var seed: int = 0                    # per-entity phase offset
var time: float = 0.0                # view clock for idle loops (paused with the game)
```

The painter is a pure function of the pose and the tile size. It reads nothing else.

### 3.3 Smoothing and time

- The sim steps at 20 ticks/s (`tick_rate`) and positions are integer milli-tiles. `BattleSnapshotBuffer` stores each unit's position from the previous and current tick, and the view interpolates with the fractional tick alpha every frame.
- `pose.time` is a view clock that advances by `delta` and stops when the game is paused. It drives idle loops only. Anything tied to gameplay uses ticks.
- The view has its own RNG for per-entity phase offsets and particle scatter (seeded from the unit id). It never touches `Rng` or any sim state.

### 3.4 Rendering layers, back to front

1. **Ground layer**: island slab, terrain patches, deploy band. Static. Cache it in a `SubViewport` texture and redraw only when the theme or phase changes.
2. **Structure layer**: walls, towers, Nucleus. Redraw on `grid_version` change (structure placed, sold or destroyed) and when a structure animates.
3. **Unit layer**: pathogens, plus animated towers, depth-sorted together.
4. **Effect layer**: projectiles, splash rings, bursts, health bars, intent lines.

Depth key is `gx + gy` of the anchor, ascending. Ground decals (footprints, ranges, scorch) always draw first.

---

## 4. Driving animation from sim state

Everything below already exists in core unless marked **missing**.

| Cue | Source | Result |
| --- | --- | --- |
| Moving | `PathogenState.state == MOVING` and position delta this frame | `Anim.MOVE`, `gait_phase += distance / stride` |
| Idle or seeking | `state == SEEKING` | `Anim.IDLE` |
| Facing | Direction to `attacking_id()` target, else the movement delta, converted to screen X | `facing_right` |
| Windup | `state == ATTACKING` and `attack_cooldown <= windup_ticks` | `Anim.WINDUP`, `attack_t` 0 to 0.4 |
| Strike | `STRUCTURE_DAMAGED` with `source_unit_id`, on the impact tick | `Anim.STRIKE`, `attack_t` 0.4 to 0.6 |
| Recover | Cooldown just reset to `attack_interval_ticks` | `Anim.RECOVER`, `attack_t` 0.6 to 1.0 |
| Hit reaction | `PATHOGEN_DAMAGED`, `STRUCTURE_DAMAGED` | `hit_t = 1`, decays over 4 ticks |
| Death | `PATHOGEN_KILLED`, `STRUCTURE_DESTROYED` | `Anim.DEAD`, `death_t` 0 to 1 |
| Wall damage tier | `hp / max_hp` | cracked below 50%, lower profile |
| Tower aim | `StructureState.target_id` | `aim` |
| Tower shot | `TOWER_FIRED` | **missing** |
| Splash | `SPLASH` | **missing** |
| Projectile flight | `ProjectileState` and `PROJECTILE_*` | **missing** |

**Windup timing:** `windup_ticks = min(WINDUP_CAP, interval_ticks * 0.4)`. The windup is derived from `attack_cooldown`, so the impact frame lands on the same tick the damage is applied, with no look-ahead and no extra sim state.

**Gait timing:** stride length is in tiles on the 40x40 grid, so feet don't slide and slows and speed effects look right without extra code.

**Known dependency:** none. Tower fire and projectiles already landed in #18: `BattleSim._update_towers()` and `_update_projectiles()` emit `TOWER_FIRED`, `SPLASH` and `PROJECTILE_SPAWNED`, `PROJECTILE_HIT` and `PROJECTILE_FIZZLED`, so tower attack animation and projectile visuals are not blocked.

---

## 5. Animation spec

Timings are in sim ticks (20 per second). Attack intervals come from `data/pathogens.json` and `data/structures.json`: Rhinovirus 10 ticks, Bacteriophage 20, Staphylococcus 30, Macrophage 20, B-Cell 24. Stride lengths are proposals for the 40x40 grid.

**Windup timing decision (#65):** the formula `windup_ticks = min(12, interval * 2 / 5)` is the rule. It gives Rhinovirus 4, Bacteriophage 8, Staphylococcus 12, Macrophage 8 and B-Cell 9 ticks. Where the tables below list different numbers (Rhinovirus 3, Macrophage 6), the formula wins.

### Pathogens

| | Idle | Move | Attack | Death |
| --- | --- | --- | --- | --- |
| **Rhinovirus** | Squash wobble, spikes pulse (loop about 1.2 s) | Bouncing roll, stride 1.6 tiles, squash on landing | Windup 3 ticks: crouch and compress. Strike: lunge and spikes flare. Recover 4 ticks. | 8 ticks: pop into 6 fragments and a puff |
| **Bacteriophage** | Head bob, legs settle | Four-leg gait, stride 2.0 tiles, front and back pairs alternate, body bob | Windup 8 ticks: crouch, head dips. Strike: tail sheath drives down like a syringe, injection glow at the contact point. Recover 8 ticks. | 14 ticks: legs splay, head cracks, fade |
| **Staphylococcus** | Cocci breathe out of phase | Ooze, stride 1.2 tiles: squash forward, biofilm trail | Windup 12 ticks: cluster gathers back. Strike: heave and slam, small shockwave ring. Recover 10 ticks. | 18 ticks: cocci scatter on scripted arcs and pop |

### Structures

| | Idle | Attack | Hit and death |
| --- | --- | --- | --- |
| **Macrophage** | Arms sway, granules drift, cup opens and closes slowly | Windup 6 ticks: arms raise, cup opens. Strike: vesicle launches. Splash ring at the target (radius from data). | Hit: 4-tick shudder. Death: 16 ticks, deflate, scorch decal. |
| **B-Cell** | Y-antibody spins, halo pulses | Aims continuously (`aim`). Charge glow over the last 6 ticks of cooldown. Recoil over 6 ticks: tiers compress and rebound. | Hit: 4-tick shudder. Death: 20 ticks, tiers collapse top-down, scorch decal. |
| **Nucleus** | Ring orbits, nucleolus pulses. Pulse rate rises as HP falls. | None | Hit: shudder and ring flicker. Death: 40 ticks, ring detaches, dome cracks and bursts. |
| **Mucous Wall** | None | None | Hit: 3-tick shake. Below 50% HP: cracks and lower profile. Destroyed: 10 ticks, chunks and goo, segment removed. |

### Rules that apply to all of them

- **Readability first.** At 14 px tiles a Rhinovirus is about 15 px wide. Animate silhouette-level features (bob, squash, spike length, leg positions). Skip internal facets below a size threshold.
- **Desynchronise.** Offset every idle and gait loop by `hash(id)` so swarms don't pulse in unison.
- **Anticipation and follow-through** on every attack: windup, a sharp strike, and a slower recover.
- **Accessibility.** Hit flash intensity and shake amplitude are multiplied by the "Reduce flashes" setting from the Settings screen. At the reduced setting the flash is off and shake is halved.
- **Debug lines.** Intent lines are a toggle and are independent of animation.

---

## 6. Rendering and performance

- **One draw pass for units.** `UnitLayer` iterates the state arrays and calls the painter functions in depth order. No node per unit. Sorting a few hundred keys per frame is cheap.
- **No allocation in `_draw()`.** Cache polygons as `PackedVector2Array` per model, scaled once for the current tile size. Use `draw_set_transform` for rotation and squash.
- **Static layers are cached.** Ground and unchanged structures are not redrawn every frame.
- **Redraw policy.** Call `queue_redraw()` only for layers that changed: the unit layer while a battle runs, the structure layer on `grid_version` change.
- **Bake step (option C).** If the web build misses its frame budget with a large army, bake each rig at load: render a fixed set of frames per state (for example idle 8, move 8, attack 6, hit 3, death 8) into a `SubViewport`, keep the result as an atlas, and draw sprites with `draw_texture_rect_region` (negative width for the mirrored facing). Turn it on only if a profile shows the need. The budget is set from the first measurement in the Rhinovirus slice issue, not guessed now.
- **Unit tile size.** Painters take the tile size in pixels and scale everything by it, so the same code serves gameplay (14 px), zoomed views and HUD icons.

---

## 7. Development workflow

### 7.1 Model viewer (`tools/model_viewer.tscn`)

A standalone dev scene, not part of the shipped game flow.

- Pick a model, state, facing and tile size (14 px in-game, 4x zoom).
- Time scrubber, play, pause and slow motion. Trigger buttons for hit, attack and death.
- Debug toggles: anchor cross, footprint diamond, gait phase readout, bounding box.
- Export a PNG contact sheet of every model and state, attached to review PRs.
- Optional side-by-side with a static reference render from the design canvas.

### 7.2 Parity with the design canvas

The canvas model sheet is the visual reference. Its helpers map directly onto Godot calls:

| Canvas helper | Godot |
| --- | --- |
| `P(dx, dy, w, h, ...)` ellipse or rect part | `draw_circle`, `draw_colored_polygon`, `draw_rect` at `anchor + Vector2(dx, dy) * T` |
| `B(x1, y1, x2, y2, thickness, ...)` bar | `draw_line` with `width = thickness * T` and round caps via circles |
| `sph(a, b, c)` sphere gradient | `PaintKit.sphere(ci, center, radius, light, mid, dark)` (stacked filled circles or a small radial texture) |
| `clip-path` polygons | `draw_colored_polygon` |

Painter parameters keep the canvas numbers in `T` units so a visual diff against the canvas is a straight comparison.

### 7.3 Testing

Rule 6 requires GUT tests only for `src/core/**`. The pose logic is pure, so we test it anyway.

- `AnimDriver` unit tests (in `tests/unit`):
  - impact tick maps to the strike frame (cooldown 0);
  - `gait_phase` only advances with distance, and not at all when rooted or stopped;
  - windup starts at `min(cap, 0.4 * interval)` before impact;
  - `death_t` clamps to 1 and stays `DEAD`;
  - facing flips when the target crosses the unit on screen;
  - the Reduce flashes setting scales hit intensity.
- `IsoProjection` unit tests: projection then inverse returns the original tile, and depth ordering is monotonic.
- An integration test runs `BattleSim` headless with a fixed seed and feeds every tick's events into `AnimDriver`, asserting no errors and stable output. It also asserts that the sim's `state_hash()` is identical with and without the view attached, which guards the read-only rule.
- Painters are checked with the model viewer and contact sheets, not with assertions.

---

## 8. Issue breakdown

One PR per issue. Order matters: 1 to 4 prove the pipeline before any content work.

| # | Issue | Scope | Depends on |
| --- | --- | --- | --- |
| 1 | Iso projection and unit layer | `IsoProjection`, snapshot buffer, `UnitLayer` drawing depth-sorted placeholder circles from `BattleSim` state, inverse mapping for touch. Tests for projection and ordering. | grid at 40x40 (spec section 6) |
| 2 | Pose model and AnimDriver | `ModelPose`, `AnimDriver`, `Easing`, `PaintKit`, view RNG. Full unit tests from section 7.3. | 1 |
| 3 | Model viewer | `tools/model_viewer.tscn`, debug toggles, contact-sheet export. | 2 |
| 4 | **Rhinovirus vertical slice** | `RhinoPainter` with the full animation set, hit flash, death burst. A bench scene with about 200 units. Record frame time on desktop and web as the baseline. | 1, 2, 3 |
| 5 | Bacteriophage and Staphylococcus | Painters and animation sets. Contact sheet review. | 4 |
| 6 | Wall renderer | Connected segments, posts, damage tiers, break effects. Cached structure layer. | 1, 2 |
| 7 | Macrophage, B-Cell, Nucleus painters | Idle, hit and death sets. Tower aim. Attack animation needs issue 8. | 4, 6 |
| 8 | ~~Core: tower fire and projectiles~~ | Done in #18. `BattleSim._update_towers()` and `_update_projectiles()` emit `TOWER_FIRED`, `SPLASH` and `PROJECTILE_*`. No issue needed. | none |
| 9 | Effect layer | Projectiles, splash ring, bursts, scorch, health bars, intent lines, Reduce flashes setting. | 7, 8 |
| 10 | Polish and performance | Profile against the issue 4 baseline. Bake step only if needed. Cross-model timing review. | 9 |

Issues 5, 6 and 8 can run in parallel once their dependencies are met.

---

## 9. Risks

| Risk | Mitigation |
| --- | --- |
| Too many draw calls in the web build with a large swarm | Single draw pass, cached static layers, measured baseline in issue 4, bake step in reserve. |
| Details vanish at 14 px | Silhouette-level animation, size-based detail cutoff, review at in-game size in the viewer. |
| Animation drifts from sim timing | Windup derived from `attack_cooldown`, impact on the damage event, integration test on ordering. |
| View accidentally affects the sim | View reads only. Integration test compares `state_hash()` with and without the view. |
| Tower visuals blocked by empty sim methods | Issue 8 is tracked explicitly and does not need to finish before painters start. |
| Swarms look robotic | Per-entity phase offsets from a view-side hash, and small random scale and tint variation. |

---

## 10. Open questions

1. **Where do animation constants live?** Proposal: in the painter scripts (stride, windup cap, shake amplitude), because they are presentation and not game stats. If designers want to tune without code, move them to a new `data/model_anim.json` under its own issue. The existing JSON must not change (rule 5).
2. **Two facings or eight?** Proposal: two (mirror), which matches the current models. Revisit only if the ground-plane pathing makes units visibly walk "sideways".
3. **Bake threshold.** To be set from the issue 4 measurements.
4. **HUD icons.** Once painters exist, the tray icons and How to play badges can call the same painters at a small static pose.
5. **Nucleus shape key.** JSON says `rounded_square`. The dome painter ignores it. Keep, or update under its own issue.

## 11. Later art upgrade

The pose contract is the boundary. A painter can later be replaced by a sprite-sheet player or a skeletal rig, using in-house production art, without changing `AnimDriver`, `UnitLayer` or the sim.
