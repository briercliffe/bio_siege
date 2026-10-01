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

## Macrophage, B-Cell and Nucleus painters (issue #70)

The three structure painters replace the placeholder billboards in `UnitLayer` (Infection) and in `GridView` (Synthesis and Incubation, where the island now redraws at 30 Hz so the idle loops run). Same Linux VM as the two previous sections (Mesa llvmpipe under Xvfb), so only comparable within this section. Each row is the mean of runs interleaved before, after, before, after, with the build before #70 in a separate worktree.

| Scene | Build | Avg ms | p95 ms | Draw calls |
|---|---|---|---|---|
| `tests/perf/rhino_bench.tscn` (200 Rhinoviruses, the Nucleus and walls), 15 s, 3 runs | before #70 | 48.54 | 56.15 | 2085 |
| | after #70 | 48.30 | 54.04 | 2099 |
| `tests/perf/stress_battle.tscn` (4 B-Cells, 2 Macrophages, the Nucleus), 12 s after a 3 s warm-up, 4 runs | before #70 | 24.96 | 33.18 | 813 |
| | after #70 | 25.06 | 33.68 | 866 |
| Synthesis island: `GridView` alone with a walled Nucleus, 2 Macrophages and a B-Cell, 12 s after a 3 s warm-up, 3 runs | before #70 | 14.75 | 15.75 | 310 |
| | after #70 | 16.01 | 18.52 | 365 |

- **Battle: at parity.** Both battle scenes are within the 1 to 2 ms run-to-run spread of this VM (the Rhino bench came out 0.2 ms faster, the stress scene 0.1 ms slower on average and 0.5 ms slower at p95). There are at most seven towers on the field against 200 units, so the per-unit painters still dominate. The stress scene issues about 53 more draw commands, about 9 per tower at 23 px.
- **Synthesis: about +1.3 ms average and +2.8 ms p95.** Before #70 the island was redrawn only on changes; now the idle animation of the towers and the Nucleus redraws the whole island at 30 Hz while structures are shown (it stops in Infection, where `UnitLayer` draws them, and while the view is hidden). That frame has no army, so it stays far inside the budget.
- **This deviates from the issue, for performance, like the earlier painters.** The issue only skips the granules and lobes, the halo and Y glow, and the pores and streaks below 10 px. Below 28 px per tile (the battle runs at 23 px) the painters also draw a flat path: the Macrophage body is a smooth two-circle oval without the 24-point lumpy outline (the 4% lumps are under a pixel there) or its rim, the arms are plain lines, hands and cup one circle each; the B-Cell's Y is plain lines without round caps and each glow is one circle; the Nucleus dome and nucleolus are two circles each, without the dome rim, the pore rings or the outer glow rings; and every pedestal is one quad and one top oval. At 28 px and above everything returns, as seen on the contact sheet (32 px cells) and in the T = 80 close-ups.
- Above 28 px the large spheres (the dome, the nucleolus and the lumpy Macrophage body) are one `PaintKit.RadialMesh` each: the canvas radial gradient as a cached indexed triangle list through `canvas_item_add_triangle_array`, one command instead of the four stacked circles of `PaintKit.sphere`, which banded visibly at close-up sizes.

## Effect layer (issue #71)

`EffectLayer` replaces `IntentLinesView` and the projectile, splash and health-bar parts of `BattleOverlay`. Every effect pass is one command however many effects are on screen: the intent lines are one `draw_multiline`, the shots, vesicles, puffs and sparks one triangle array, the health bars one triangle array, and the scorch decals and splash rings one triangle array each in `UnitLayer`'s ground pass (scorch before the tower plates, splash rings after; each skipped when empty). Same Linux VM as the three previous sections (Mesa llvmpipe under Xvfb, vsync on), so only comparable within this section. These rows are not comparable to the earlier sections. The Infection HUD from #81 fits the island between its cards, so the bench runs at 14.3 px per tile, not 23, but most of the jump to about 73 ms comes from #81's night `AmbientBackground` behind the battle: its `_draw_gradient` draws a full-screen rect and 24 near-full-screen ellipses every frame, about 25 ms on llvmpipe (the #81 build with the gradient replaced by a flat fill reads about 47 ms against about 73 ms). #72 will fix the background. Each row is the mean of three 15 s runs of `tests/perf/rhino_bench.tscn`, interleaved with the build before #71 in a separate worktree and alternating which build runs first.

| Army | Build | Avg ms | p95 ms | Draw calls |
|---|---|---|---|---|
| 200 Rhinoviruses | before #71 | 73.10 | 79.91 | 2241 |
| | after #71 | 72.78 | 76.47 | 2241 |
| Mixed, 200 units | before #71 | 84.61 | 91.36 | 3219 |
| | after #71 | 84.15 | 89.11 | 3218 |

- **At parity**, within the 1 to 2 ms run-to-run spread of this VM. Timed inside the bench, `EffectLayer._draw` takes about 0.66 ms per frame, against 0.72 ms for the old `IntentLinesView` and `BattleOverlay` together. Building the batches is under 0.2 ms; the rest is handing them to the server.
- A first build that always wrapped the empty ground pass in its own pair of transform commands measured about 4.7 ms slower in the Rhinovirus bench (70.6 against 75.4 ms over six interleaved pairs) and 3.2 ms slower with the mixed army. Skipping the pass when there is no scorch or splash removed the difference, so `draw_scorch()` and `draw_splashes()` now return early when their batch is empty. Skipping the screen-space batches themselves changed less than 1.6 ms, which is within the noise.

## Budget for #72

The target is 60 fps on desktop and at most 20 ms average frame time with 200 units on the web, with the p95 under 25 ms.

Measured against that target:

- Desktop: over budget. 29 ms is 34 fps, and the Rhinovirus is the simplest painter. The placeholder view alone uses 12 ms.
- Web: far over budget at 106 to 114 ms average, and the placeholder view alone (39 ms) is already over 20 ms.

Two decisions follow for #72, and they should be made before the other three painters are written:

1. **Enable the bake step (plan section 6, option C).** Procedural GDScript painting does not fit the web budget at 200 units, even after trimming. Bake each model into a `SubViewport` atlas at load (idle 8, move 8, attack 6, hit 3, death 8 frames) and draw one `draw_texture_rect_region` per unit. That is about one draw command per unit instead of nine (at 23 px) to about forty-five (at 56 px), with no per-unit GDScript painting.
2. **Budget the rest of the view separately.** About 12 ms desktop and 39 ms web with 200 units is spent outside the painters (intent lines, sim, grid and HUD). Baking will not fix that part, so #72 should measure it on its own and decide whether the intent lines need a cheaper path.

The bench stays as the regression check: re-run it after each painter or bake change and update the tables above.

## After M6 (issue #72)

Budget from the section above: 60 fps on desktop, at most 20 ms average and under 25 ms p95 on the web with 200 units.

**Machines.** The same one as the first section: Intel i9-12900K, GTX 1070, Windows 11. Desktop is the Godot 4.7.2 binary running the project (GL Compatibility), `--disable-vsync`, 15 s after the warm-up, the mean of two runs interleaved before, after (cheap wins), after (bake). The web rows are a release Web export (single-threaded) in a visible Chrome window of 1284x725 px, a fresh profile, two runs each; the bench scene was the main scene of those exports, and the page was visible and in front. The Infection HUD from #81 fits the island between its cards, so the bench runs at 14.3 px per tile on desktop and 18.1 on the web, not at the 23 px of the first sections: these numbers are not comparable to those.

"Before" is #71 (`18d5537`) plus only the bench options of this branch (`--bench-seconds`, `--bench-out`, counts in `--bench-mix`). "Mixed" is `--bench-mix=rhinovirus:120,bacteriophage:50,staphylococcus:30`.

### Desktop

| Scene | Build | Avg ms | p95 ms | Draw calls |
|---|---|---|---|---|
| `rhino_bench`, 200 Rhinoviruses | before #72 | 33.58 | 34.72 | 2244 |
| | cheap wins (cache, redraw policy, no allocation, background) | 33.54 | 35.11 | 1996 |
| | + baked sprites | **5.59** | 6.06 | 213 |
| `rhino_bench`, mixed 120/50/30 | before #72 | 37.61 | 39.65 | 2600 |
| | cheap wins | 37.81 | 39.66 | 2354 |
| | + baked sprites | **7.91** | 9.41 | 315 |
| `stress_battle` | before #72 | 9.80 | 17.07 | 865 |
| | cheap wins | 3.62 | 11.67 | 618 |
| | + baked sprites | 2.12 | 5.27 | 305 |

### Web (Chrome)

| Scene | Build | Avg ms | p95 ms | Draw calls |
|---|---|---|---|---|
| 200 Rhinoviruses | before #72 (2 runs) | 58.4, 59.3 | 62.5, 66.7 | 2251 |
| | after #72 (2 runs) | 16.67, 16.67 | 16.67, 16.67 | 223 |
| Mixed 120/50/30 | before #72 (2 runs) | 70.2, 69.6 | 75.0, 75.0 | 2606 |
| | after #72 (2 runs) | 16.67, 16.67 | 16.67, 16.67 | 325 |

The web page is capped at 60 fps by the browser, so 16.67 ms is the cap, not the cost: the real frame time is at or under it, and the headroom is not known. The budget is met with 200 units, both for the Rhinovirus and for the mixed army.

### What the numbers say

- **The cheap wins did not move the desktop battle on this GPU.** The static island cache, the redraw policy, the allocation clean-up and the flat-band background took the Rhino bench from 33.58 to 33.54 ms. Their effect shows only in the stress scene (9.8 to 3.6 ms), where the full-screen background gradient was the main cost, and on the llvmpipe VM of the earlier sections, where that gradient cost about 25 ms. The draw-call counts dropped by about 250.
- **The frame was the painters.** Baking took about 28 ms off the 33 ms frame, so that is what per-unit painting in `UnitLayer._draw` cost. It is now one textured quad per unit, 213 draw calls instead of 2244.
- **The bake step is therefore on** (`USE_BAKED_SPRITES = true` in `unit_layer.gd`), for the reasons the section above predicted: without it desktop sits at 30 fps and the web at 15 fps.

### Baked sprites: what changed in the look

`SpriteBaker` renders every pathogen painter into one atlas at battle start, at the current T and screen scale (idle 8, move 8, attack 6, hit 3, death 8 frames), and again when either changes. Until the atlas is drawn, units are painted live. Differences from the live painters: the per-entity size and light variance (+-4%) is not baked; a hit flash shows as the HIT clip instead of a tint on the current pose, and only while the unit is not attacking; the 1 px antialiased edges are slightly darker, because the atlas holds premultiplied colour and is drawn with normal blending; sprites are drawn at fractional positions with linear filtering. Trails and shockwaves (`paint_ground`) still run live. Towers, walls and the Nucleus are not baked: there are at most seven towers on the field.

### Not measured

- Firefox, Safari, any phone or low-end laptop; web numbers have two runs at one window size.
- The web cost of the cheap wins on their own (only before, and after both).
- The headroom under the 60 fps cap on the web.
