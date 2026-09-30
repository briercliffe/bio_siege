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

## Mixed army: Bacteriophage and Staphylococcus painters (issue #68)

`--bench-mix=rhinovirus,bacteriophage,staphylococcus` cycles the 200 units through the three pathogen types (67, 67 and 66). There was no GPU machine for this run, so both rows come from the same Linux VM with Mesa llvmpipe (software GL, 4 cores) under Xvfb, 15 s each after the warm-up, vsync left on. They are only comparable to each other, not to the tables above.

| Army | Avg ms | p95 ms | Min fps | Draw calls |
|---|---|---|---|---|
| 200 Rhinoviruses | 45.3 | 52.3 | 17.1 | 2123 |
| Mixed, 200 units | 63.8 | 68.5 | 13.9 | 3066 |

The mixed army costs about 40% more per frame and about 950 more draw commands (about 14 painter commands per unit at 23 px, against 9 for the Rhinovirus). The Bacteriophage (legs, plate, sheath, collar and head) and the Staphylococcus (eight cocci, base and trail) have more parts than the Rhinovirus, even after the flat path below 28 px. That makes the bake step in the next section more pressing, not less.

## Mucous Wall renderer (issue #69)

The connected-segment walls replace three flat polygons per wall with extruded faces, a glossy top with its outline, ground shadows and posts. Same Linux VM as the previous section (Mesa llvmpipe under Xvfb), so again only comparable within the section. The run-to-run spread on this VM is 1 to 2 ms on the same build, so each row is the mean of runs interleaved before, after, before, after.

| Scene | Build | Avg ms | p95 ms | Draw calls |
|---|---|---|---|---|
| `tests/perf/stress_battle.tscn`, 12 s after a 3 s warm-up, 8 runs | before #69 | 24.07 | 32.21 | 902 |
| | after #69 | 24.45 | 34.39 | 809 |
| `tests/perf/rhino_bench.tscn`, 15 s, 3 runs | before #69 | 48.39 | 53.37 | 2116 |
| | after #69 | 49.71 | 55.15 | 2083 |

In the stress scene the average frame time is at parity within the noise (+0.4 ms, and two of the eight interleaved pairs came out faster after the change), but the p95 regressed by about 2 ms on llvmpipe: 32.21 to 34.39 ms, with all eight after-runs above the before-median p95 of 31.71 ms. In the Rhino bench the walls cost about +1.3 ms average and +1.8 ms p95. #72 owns the frame budget, so these costs go into its accounting. The first full-detail build measured about 2 ms slower in the stress scene average, and on llvmpipe the cost followed the number of small triangles rather than the number of commands. These reductions brought the average back:

- **This deviates from the issue, for performance.** The issue only skips the stripes and the post highlight below 10 px. Below 28 px per tile (the battle runs at 23 px), the geometry is built coarse: square top corners, no face stripes, 8-point ellipses, a 4-point highlight and a post cap shaded per vertex instead of from its focus. At 28 px and above everything returns (rounded tops, stripes, 18-point ellipses, the radial cap), as seen in the viewer at 40 and 56 px.
- Each cell's geometry is one cached, indexed triangle list, so quads and fans share their corner vertices. The core's side faces that a neighbour's bridge always covers are not built.
- A post that sorts right after its own segment is painted in the same command. All shadows are one command, and the cracks are cached triangles with the alpha taken from 33 cached colour steps.
- `draw_mesh` is not used: on the GL Compatibility renderer it costs about 26 us per call, several times a polygon command.

## Budget for #72

The target is 60 fps on desktop and at most 20 ms average frame time with 200 units on the web, with the p95 under 25 ms.

Measured against that target:

- Desktop: over budget. 29 ms is 34 fps, and the Rhinovirus is the simplest painter. The placeholder view alone uses 12 ms.
- Web: far over budget at 106 to 114 ms average, and the placeholder view alone (39 ms) is already over 20 ms.

Two decisions follow for #72, and they should be made before the other three painters are written:

1. **Enable the bake step (plan section 6, option C).** Procedural GDScript painting does not fit the web budget at 200 units, even after trimming. Bake each model into a `SubViewport` atlas at load (idle 8, move 8, attack 6, hit 3, death 8 frames) and draw one `draw_texture_rect_region` per unit. That is about one draw command per unit instead of nine (at 23 px) to about forty-five (at 56 px), with no per-unit GDScript painting.
2. **Budget the rest of the view separately.** About 12 ms desktop and 39 ms web with 200 units is spent outside the painters (intent lines, sim, grid and HUD). Baking will not fix that part, so #72 should measure it on its own and decide whether the intent lines need a cheaper path.

The bench stays as the regression check: re-run it after each painter or bake change and update the tables above.
