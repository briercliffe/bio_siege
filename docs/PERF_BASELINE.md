# Performance baseline: procedural Rhinovirus painter (issue #67)

This is the first measurement of procedural model painting (`docs/MODEL_PIPELINE_PLAN.md` sections 5 and 6). It sets the frame budget that #72 works against. Every number below was measured on the machine described here; nothing is estimated.

## What is measured

`tests/perf/rhino_bench.tscn` builds a `Session` with `Scenarios.walled_nucleus()` (the Nucleus and a ring of walls) and 200 Rhinoviruses spread evenly over the 40x40 deploy ring, with a fixed seed. It runs the full Infection view: ground, biofilm, `UnitLayer`, intent lines, battle overlay and HUD. The overlay reports the last 5 s: average frame ms, p95 frame ms, minimum fps, draw calls (`RENDER_TOTAL_DRAW_CALLS_IN_FRAME`) and alive units. A finished battle restarts, so the bench always measures a live fight.

The bench scene is the same 1280x720 project viewport. Tile size in the view was 23 px on desktop (`canvas_items` stretch, `expand` aspect). Units start on the ring and walk to the Nucleus, so the state changes over time; all rows below were read after about 20 s of wall time, with the battle clock at 2:56 to 2:59 on the web (the sim runs slower than real time there) and mid-battle on desktop.

Desktop numbers come from a scripted run that skips a 2 s warm-up and writes the result to a file:

```
godot --path . --disable-vsync tests/perf/rhino_bench.tscn -- --bench-seconds=20 --bench-out=<absolute path to a .txt>
```

Without `--disable-vsync` the frame time is quantised by the display refresh rate (an earlier run with vsync on read 29.2 ms, the same as below, but the placeholder run was pinned at exactly 16.7 ms and told us nothing).

## Machines

| | Desktop | Web |
|---|---|---|
| OS | Windows 11 Home (10.0.26200) | same machine |
| CPU | Intel Core i9-12900K | same |
| GPU | NVIDIA GeForce GTX 1070 (driver 566.14) | same, through ANGLE / Direct3D 11 |
| Runtime | Godot 4.7.2 editor binary running the project, GL Compatibility | Chrome 153, Godot Web release export, single-threaded, WebGL 2 |

## Results

Rhinovirus painter (this issue), 200 units:

| Device | Browser | Units | Avg ms | p95 ms | Draw calls |
|---|---|---|---|---|---|
| Desktop, GTX 1070 (run 1) | native | 200 | 29.2 | 30.6 | 2116 |
| Desktop, GTX 1070 (run 2) | native | 200 | 28.9 | 29.6 | 2116 |
| Desktop, GTX 1070 (run 3) | native | 200 | 29.8 | 33.3 | 2116 |
| Web export, same machine (run 1) | Chrome 153 | 200 | 113.7 | 128.7 | 2145 |
| Web export, same machine (run 2) | Chrome 153 | 200 | 106.3 | 132.2 | 2127 |

For comparison, the same bench with the old placeholder painters (no Rhinovirus painter registered), which isolates what painting adds:

| Device | Browser | Units | Avg ms | p95 ms | Draw calls |
|---|---|---|---|---|---|
| Desktop, GTX 1070 (run 1) | native | 200 | 12.1 | 12.5 | 1116 |
| Desktop, GTX 1070 (run 2) | native | 200 | 12.1 | 13.0 | 1116 |
| Web export, same machine (1 run) | Chrome 153 | 200 | 39.2 | 48.4 | 1116 |

Reading the two tables together:

- The rest of the Infection view (sim, grid, intent lines, HUD) costs about 12 ms on desktop and about 39 ms on the web with 200 units.
- The Rhinovirus painter adds about 17 ms on desktop and about 70 ms on the web.
- On desktop, most of the frame is GDScript time in `UnitLayer._draw`: a temporary timer (taken one iteration before the final painter) read about 20 ms of a 31 ms frame, which is about 100 microseconds per unit, and the rest is the engine's per-command cost. The web build runs GDScript in WebAssembly, which is why the same code is about 4x slower there.
- The web numbers are from a headed Chrome 153 window that was visible and not throttled (`document.visibilityState` was `visible`; a first attempt with the window hidden behind other windows read about 140 ms because Chrome throttled it, and was discarded). The numbers will differ on a phone, which is the real target and was not available.

## What was not measured

- No mobile device (Android or iOS browser), and no low-end laptop. Only the one desktop above.
- No browser other than Chrome.
- The web numbers have two to three samples at one window size (1284x725 px), read from a screenshot of the overlay, not scripted.
- A desktop export template build (release GDScript) was not measured; the desktop numbers are from the editor binary running the project.

## Cost reductions already taken

The first version of the painter, with a four-layer sphere for every spike and knob, measured 125 ms average and 8300 draw calls per frame on desktop. Every draw command costs roughly 10 to 15 microseconds here, so the fix was fewer commands:

- **This deviates from the issue, for performance.** The issue only drops the facet, knobs and gloss below 10 px. The code drops more, below 28 px per tile: the three front knobs, the rim ring and the hexagonal facet are not drawn at all, the spikes are one flat circle each instead of a four-layer sphere, and the body is two circles. What remains below 28 px is the shadow, the five back spikes, the two-circle body and (from 10 px up) the gloss. Below 10 px the gloss is dropped too. The bench runs at 23 px per tile, so **no knobs are drawn in the bench**. At 28 px and above the knobs (with their strike flare), rim, facet and four-layer spheres all return, as seen on the contact sheet and in the viewer at 56 px.
- Circles use `draw_circle` (`PaintKit.ellipse` now takes that path when the rect is round), and the ground shadow is a circle under a squashed transform.
- Every colour is computed once per `paint()` call, not once per part.

That took desktop from 125 ms to 29 ms and draw calls from 8316 to 2116. About 9 painter commands per unit remain at 23 px (1 shadow, 5 spikes, 2 body, 1 gloss). The bench draw-call total is higher than 9 per unit because it also counts the rest of the view: the placeholder run, which has no painter detail, already reports 1116.

## Budget for #72

The target is 60 fps on desktop and at most 20 ms average frame time with 200 units on the web, with the p95 under 25 ms.

Measured against that target:

- Desktop: over budget. 29 ms is 34 fps, and the Rhinovirus is the simplest painter. The placeholder view alone uses 12 ms.
- Web: far over budget at 106 to 114 ms average, and the placeholder view alone (39 ms) is already over 20 ms.

Two decisions follow for #72, and they should be made before the other three painters are written:

1. **Enable the bake step (plan section 6, option C).** Procedural GDScript painting does not fit the web budget at 200 units, even after trimming. Bake each model into a `SubViewport` atlas at load (idle 8, move 8, attack 6, hit 3, death 8 frames) and draw one `draw_texture_rect_region` per unit. That is about one draw command per unit instead of nine (at 23 px) to about forty-five (at 56 px), with no per-unit GDScript painting.
2. **Budget the rest of the view separately.** About 12 ms desktop and 39 ms web with 200 units is spent outside the painters (intent lines, sim, grid and HUD). Baking will not fix that part, so #72 should measure it on its own and decide whether the intent lines need a cheaper path.

The bench stays as the regression check: re-run it after each painter or bake change and update the tables above.
