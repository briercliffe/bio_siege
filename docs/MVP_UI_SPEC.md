# Bio Siege: MVP UI and Art Spec

**Status: locked for the MVP (v1, 2026-09-29).**

This document freezes the screens, view projection, grid and models for the MVP. It is derived from the "Bio Siege Screens" design canvas (a Claude design artifact, private): https://claude.ai/artifact/9XG2xSPhUaXoshJFdC5DLF

Where this spec and `IMPLEMENTATION_PLAN.md` disagree about the grid, the projection or the look, **this spec wins**. Section 7 lists which plan sections it amends. Nothing in `src/` or `data/` has been changed to match yet. Section 6 lists that work so it can be raised as issues.

---

## 1. Locked decisions

| Area | Decision |
| --- | --- |
| Platform and layout | Landscape 1280x720 logical viewport. Touch-first: every tappable control is at least 48x48 px, and there are no hover-only features. |
| Projection | **Isometric (2:1 dimetric), view layer only.** The simulation stays a flat integer grid. The view projects it. |
| Grid | **40x40 tiles** (`grid_scale` 2), pulled forward from Phase 2 (plan section 11). |
| Deploy zone | Outer **2-tile band** around the island. Not buildable. |
| Footprints | Nucleus 4x4, Macrophage 3x3, B-Cell 3x3, Mucous Wall 1x1. |
| Look | Continuous organic island with no visible grid. Grid cues appear only around the piece being placed. |
| Themes | Defender phases (Synthesis, menus): **day**, blue and white. Attacker phases (Incubation, Infection, Results): **night**, crimson with green. |
| HUD | Floating rounded pills and cards over a full-bleed background. No full-width bars. |
| Type | Open Sans (Godot 4's default font) with the weights used in the canvas: 400, 600, 700, 800. |
| Art | Everything is drawn in code from geometric placeholders (plan section 0). No imported art, audio or fonts. |

---

## 2. Screens and flow

Fifteen screens. Each maps to an existing or planned scene.

| # | Screen | Purpose | Scene or script |
| --- | --- | --- | --- |
| 01 | Title | Play, Saved bases and armies, How to play, Settings | new `src/ui/title.tscn` |
| 02 | How to play | Four-step loop plus three rules to know | new |
| 03 | Saved bases and armies | Versioned JSON save slots, Bases and Armies tabs, Load, Share, Delete, Import | new (M5 save and load) |
| 04 | Settings | Master volume, sound effects, intent lines default, reduce flashes, telemetry consent, debug overlay, reset hints | new |
| 05 | Synthesis: new base | Empty island, Nucleus only, getting-started guide | `phases/synthesis_phase.tscn`, `hud_build` |
| 06 | Synthesis: placing | Selected-structure card, base status, placement ghost with range ring | same |
| 07 | Synthesis: finalize? | Confirm dialog showing base cost and army budget | `confirmation_popup` |
| 08 | Switching sides | Split day/night transition, "You are now the Pathogen" | `side_switch_overlay` |
| 09 | Incubation: empty army | Launch disabled until at least one unit is owned | `phases/incubation_phase.tscn`, `hud_spawn` |
| 10 | Incubation: deploying | Buy and deploy, glowing band, reserve counts | same |
| 11 | Infection: battle | Timer, alive count, intent-line toggle, Nucleus HP, health bars, cracks | `phases/infection_phase.tscn`, new `hud_combat` |
| 12 | Infection: paused | Resume, Restart raid, Settings, Quit to menu | new |
| 13 | Results: Nucleus destroyed | Stats, ATP split bar, Re-raid / Edit base / New base, pivot survey | `phases/results_phase.tscn` |
| 14 | Results: defense held | Same layout, timeout badge, grid-feel survey | same |
| 15 | Data error | Readable config validation errors, Copy report, Reload data | new (plan section 2.2) |

Flow:

```
Title -> Synthesis -> Finalize? -> Switching sides -> Incubation -> Infection -> Results
  |                                                       ^                          |
  +-> How to play / Saved / Settings                      +--- Re-raid --------------+
                                                Edit base -> Synthesis, New base -> Synthesis (1000 ATP)
Infection <-> Pause -> Restart raid (Incubation) / Quit (Title)
```

Deferred past the MVP: base upgrades (Amino Acids), Mutation Lab, raid target picker, Mitochondria and ATP storage, clan hub, Pandemic Mode (plan sections 10 to 13).

---

## 3. Isometric projection

The projection lives in `src/view/` (for example an `IsoProjection` helper). It is view code, so floats are allowed. `src/core/**` never sees it.

- Ground point `(gx, gy)` in tile units, tile size `T` px (14 by default), projection scale `s = 0.56`.
- Screen: `X = (gx - gy) * T * s + origin_x`, `Y = (gx + gy) * T * s / 2 + origin_y`.
- One tile is a diamond `2*T*s` wide and `T*s` tall (about 15.7 x 7.8 px at T = 14).
- The 40x40 island spans `2 * 40 * T * s` px wide (627 px) and half that in height, plus headroom for tall sprites (4.5 T) and slab thickness (1.6 T).
- **Input:** invert the transform to get ground coordinates from an `InputEventScreenTouch` or `InputEventScreenDrag`, then floor to a tile. Hit-test structures and units by tile occupancy, never by sprite pixels.
- **Depth order:** sort walls, towers, the Nucleus and units by `gx + gy` of their anchor (footprint centre), ascending, and draw in that order. Flat things (ground decals, deploy band, range ring, scorch, footprint highlights) always draw first.
- **Facing:** every unit sprite faces right by default and is mirrored when its target is left of it on screen. Mirror the placement, never the lighting.
- **Overlays in screen space:** health bars, intent lines and projectiles. Intent lines run between unit centres raised about 0.6 T. Projectiles fly about 1.5 T above the ground.

---

## 4. Model specs

Sizes are in `T` units (one tile). Every sprite is anchored at its ground centre, with negative y going up. Colours come from `data/*.json` placeholders wherever a JSON colour exists.

### Pathogens (attackers)

| Model | JSON shape and colour | Size | Silhouette cues |
| --- | --- | --- | --- |
| Rhinovirus | circle `#2ecc71` | 1.2 wide x 1.25 tall | Round capsid, ring of spike knobs, hexagonal facet, glossy highlight |
| Bacteriophage | lander `#e67e22` | 1.9 wide x 3.0 tall | Hexagonal head with light and dark facets, ridged tail sheath, baseplate, four splayed legs with foot pads |
| Staphylococcus | cluster `#f1c40f` | 2.8 wide x 2.35 tall | Eight shaded cocci stacked like grapes on a glossy biofilm base |

### Immune defenses and HQ

| Model | JSON shape and colour | Size | Silhouette cues |
| --- | --- | --- | --- |
| Macrophage | circle `#2e86de` | 3x3 footprint, 3.0 tall | Cylinder pedestal, amoeboid body, two pseudopod arms, translucent nucleus lobes, dark feeding cup on the front |
| B-Cell | triangle `#48dbfb` | 3x3 footprint, 4.3 tall | Cylinder pedestal, three stepped two-tone pyramid tiers, glowing Y-shaped antibody with a halo. The tallest defense. |
| Nucleus | rounded_square `#8e44ad` | 4x4 footprint, 4.1 tall | Dome on a plinth, envelope ring passing behind and in front, bright nucleolus, surface pores |

The Nucleus is drawn as a dome. `data/structures.json` still says `rounded_square`. Keep that key as the placeholder id and let the view draw the dome, or change it under a dedicated issue.

### Mucous Wall

- Built from connected segments: 0.72 T thick, 0.8 T tall, extruded with a lighter left face, a darker right face and a glossy top.
- Faces carry a faint vertical stripe texture. Colour is JSON `#c8b98a` in the tan family.
- Posts (0.84 T wide, 1.35 T tall, glossy cap) stand at corners, ends, junctions and on every fourth tile of a straight run (`(c + r) % 4 == 0`).
- **Damaged** (below 50% HP): the segment drops to 0.55 T and shows crossed cracks. **Destroyed**: the segment is removed and leaves a gap.
- Walls are never targeted (plan section 1.3). Cracks show only when a wall is being attacked as a blocker.

### Legibility aids

- Intent lines on by default (`feature_flags.intent_lines_default`), toggle in the HUD.
- Health bars appear only on damaged entities, green above 50%, amber to 25%, red below.
- A destroyed tower leaves a scorch decal with debris.

---

## 5. HUD rules

- Colours: defender ink `#12304f`, accent `#1e5aa8`, panels white at 90% opacity. Attacker ink `#f5e6e8`, panels `#2a0b10` at 90%, accent `#2ecc71` with dark text `#0a2414`.
- Primary buttons are pills at least 52 px high. Steppers and tray cards are at least 48 px.
- Text is 12 px minimum, and body copy is 14 to 16 px.
- Selected tray card: 3 px accent border plus a soft outer ring.
- Disabled controls use a flat muted fill and are never hidden. Launch Attack stays visible but disabled until the army is non-empty.
- A live selection card sits on the left and a status card on the right, both floating and about 300 px wide. The tray floats at the bottom, centred.

---

## 6. Work implied by the lock (not yet done)

These are proposals to raise as issues. None of them has been applied.

**Data and rules (`data/*.json`, needs an explicit issue per CLAUDE.md rule 5)**
- `game_rules.json`: `grid.width` and `grid.height` 40, `deploy_ring` 2, `grid_scale` 2, `tile_px` 14.
- `structures.json`: footprints Nucleus 4x4, Macrophage 3x3, B-Cell 3x3. Nucleus origin tile 18,18.
- Wall cost: the canvas assumes **5 ATP** (10 at 20x20), so a typical 52-wall ring costs about the same.
- Ranges, speeds and splash radii scale automatically through `grid_scale`. Re-run the balance sim and re-tune.

**Core and tests**
- Every test that assumes 20x20 needs the new size, and `PathService` and `Targeting` need coverage at 40x40. Check the recalculation budget (`max_path_recalcs_per_tick`) at the larger grid.

**View and UI**
- `IsoProjection`, a depth-sorted sprite layer, ground decals, wall extrusion and the model builders (sections 3 and 4).
- Input mapping through the inverse projection.
- The floating HUD components, and the screens 01 to 04, 12 and 15 that do not exist yet.

**Model and animation pipeline**
- How the models are built in Godot and animated, and the issue breakdown, are in [`MODEL_PIPELINE_PLAN.md`](MODEL_PIPELINE_PLAN.md).

**Schedule**
- Iso view work touches M1 (grid view), M2 (deploy band) and M4 (combat view). The plan's estimates need a re-check.

---

## 7. Amended plan sections

| Plan section | Change |
| --- | --- |
| 0 Key Decisions | Rendering is isometric (view only). The grid is 40x40. |
| 1.1 Grid and placement | Deploy ring 2 tiles. Footprints per section 1 above. Nucleus is 4x4. |
| 1.9 Grid size | Decided: go to the finer grid now, not in Phase 2. |
| 2.4 Built for the full game | `grid_scale` is used from the MVP. |
| 3 Milestones (M1, M2, M4) | Add iso view, depth sorting and model builders. |
| 4 Risk Register | Add the view work and the re-tune. |

---

## 8. Known gaps

- The tray cards, HUD icons and How-to-play badges still use flat shape icons. Cropped model renders could replace them.
- The Switching sides transition still uses flat shapes.
- **Readout convention (decided):** every player-facing distance or speed is shown in on-screen tiles, meaning 40x40 tiles. It is computed from the converted fields, never from the raw JSON number: range in tiles is `StructureDef.attack_range_mt / 1000.0`, and speed in tiles per second is `PathogenDef.speed_mt_per_tick * config.tick_rate / 1000.0`. This matches the mockups ("Sniper, 12-tile range", "Speed 5 tiles/s").
