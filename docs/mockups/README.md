# Design mockups (reference only)

Rendered from the locked "Bio Siege Screens" design canvas that
[`../MVP_UI_SPEC.md`](../MVP_UI_SPEC.md) is derived from. The M6 GitHub issues
embed these images.

- `01_*.png` to `15_*.png`: the fifteen screens, 1280x720 (spec section 2).
- `model_*.png`, `walls_sheet.png`, `lineup_14px.png`, `model_sheet.png`: model references (spec section 4).
- `island_field.png`, `ambient_background.png`: shared parts.
- `canvas/*.dc.html`: the canvas source for each artboard. Open a file to read exact pixel sizes,
  colours and copy. `canvas/Field.dc.html` holds the isometric island and every model's drawing
  code in tile units (`T`), which the painter issues port to GDScript.

These files are **reference material, not game assets**. CLAUDE.md rule 7 still applies:
nothing here may be loaded by the game. They live on this branch, not on `main`, so `main`
keeps passing the "no image files" check from #28.
