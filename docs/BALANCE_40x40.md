# Balance re-tune at 40x40 (issue #84)

Status: **PROPOSAL ONLY. NOTHING IN `data/*.json` HAS BEEN CHANGED.** The owner has not yet approved any numbers.
Every "after tuning" figure below was produced with the simulator's `--set` overrides, which do not edit files.
Every proposed value is labelled PROPOSED, NOT APPLIED.

## Method

Same flags everywhere: `--runs=100 --jitter=3 --seed=12345`. Median columns are medians over the 100 runs.

- **20x20 baseline:** a throwaway worktree at commit `ae91d4f` (main before #62), removed afterwards.
- **40x40 before tuning:** current main (`data/*.json` untouched).
- **40x40 after tuning:** current main plus the `--set` overrides listed at the end of this file.

```bash
# per scenario, run in the 20x20 worktree and in this repo
for s in open_field walled_nucleus short_wall long_wall phage_priority mixed stress; do
  godot --headless --path . -s tools/balance_sim.gd -- --scenario=$s --runs=100 --jitter=3 --seed=12345 --out=out/${tag}_$s.csv
done
# knob sweeps used to pick values (30 runs each)
godot --headless --path . -s tools/balance_sim.gd -- --scenario=phage_priority --sweep=pathogens.bacteriophage.speed_tiles_s:0.8:1.5:0.1 --runs=30 --jitter=3 --seed=12345
godot --headless --path . -s tools/balance_sim.gd -- --scenario=stress --sweep=pathogens.rhinovirus.speed_tiles_s:1.0:2.5:0.25 --runs=30 --jitter=3 --seed=12345
godot --headless --path . -s tools/balance_sim.gd -- --scenario=stress --sweep=structures.mucous_wall.hp:300:900:100 --runs=30 --jitter=3 --seed=12345
godot --headless --path . -s tools/balance_sim.gd -- --scenario=stress --sweep=pathogens.rhinovirus.hp:30:90:10 --runs=30 --jitter=3 --seed=12345
```

Medians and win rates were computed from the `--out` CSVs. Columns: attacker win rate, battle time (s), first contact (s), structures destroyed, pathogens alive at the end. No run hit `battle_timeout_s` (180 s) in any table.

## 20x20 baseline (`ae91d4f`)

| scenario | win % | battle s | contact s | destroyed | alive |
|---|---|---|---|---|---|
| open_field | 100 | 37.2 | 3.2 | 1 | 5 |
| walled_nucleus | 100 | 75.3 | 2.8 | 3 | 3 |
| short_wall | 100 | 60.1 | 4.4 | 1 | 3 |
| long_wall | 100 | 75.3 | 1.6 | 3 | 3 |
| phage_priority | 100 | 63.4 | 10.7 | 2 | 2 |
| mixed | 0 | 21.9 | 3.2 | 1 | 0 |
| stress | 100 | 20.6 | 1.6 | 12 | 15 |

Caveat: the 20x20 `phage_priority` result is bimodal. About 40% of runs finish near 47 s (three phages survive) and the rest near 64 s (two survive), so its median sits on the upper mode (mean 56.2 s). I used the median as the issue specifies. Judged against the mean (56.2 s), the 40x40 value of 47 s is -16%, still not in band.

## 40x40 before tuning (current main)

Band = win rate within 10 pp of baseline and battle time within +-20% of baseline.

| scenario | win % | battle s | vs baseline | contact s | destroyed | alive | in band |
|---|---|---|---|---|---|---|---|
| open_field | 100 | 37.4 | +0.5% | 3.4 | 1 | 5 | yes |
| walled_nucleus | 100 | 75.3 | 0.0% | 3.2 | 3 | 3 | yes |
| short_wall | 100 | 59.4 | -1.2% | 3.8 | 1 | 3 | yes |
| long_wall | 100 | 75.2 | -0.1% | 1.8 | 3 | 3 | yes |
| phage_priority | 100 | 47.0 | -25.9% | 10.3 | 2 | 3 | **no** |
| mixed | 0 | 24.8 | +13.2% | 2.4 | 1 | 0 | yes |
| stress | 100 | 12.0 | -41.7% | 1.4 | 10 | 35 | **no** |

Out of band: `phage_priority` (too fast, 3 phages survive every run, the unimodal fast mode) and `stress` (the Nucleus falls in 12 s, with 35 of 100 Rhinoviruses alive). In `stress` the Rhinovirus attack range scales with `grid_scale`, so more units can reach the 56-wall ring at once. Contact time is unchanged, but walls and the Nucleus go down much faster.

## PROPOSED, NOT APPLIED: changes

Only the first knob in the issue's preference order (pathogen `speed_tiles_s`) is needed. No `hp`, range, cost or timeout changes.

```diff
--- a/data/pathogens.json
+++ b/data/pathogens.json
   "rhinovirus": {
-    "speed_tiles_s": 2.5,
+    "speed_tiles_s": 1.4,
   "bacteriophage": {
-    "speed_tiles_s": 1.5,
+    "speed_tiles_s": 1.15,
```

Reasons:

- **Rhinovirus 2.5 -> 1.4.** The stress sweep gives 11.95 s at 2.5, 16.65 s at 1.5 (the edge of the band, 16.5 s), and 22.2 s at 1.0. 1.4 gives 17.6 s, safely inside the band. Wall `hp` was a poor lever: 300 -> 900 only moved stress from 12.0 s to 14.7 s, and it would change the wall economy. Rhinovirus `hp` had no useful effect.
- **Bacteriophage 1.5 -> 1.15.** The `phage_priority` sweep has a cliff: 1.3 gives 48.7 s, 1.2 gives 50.3 s, 1.1 gives 68.3 s, and 1.0 gives 70.6 s. Below 1.0 the phages start losing: 0.9 gives 123 s and 0.8 gives only 63% attacker wins. 1.15 gives 67.5 s with a tight distribution (p10-p90 66.6 to 67.9 s) and two phages surviving, which matches the baseline's upper mode. 1.2 is just outside the band (50.3 s vs the 50.7 s lower edge).

## 40x40 after tuning (via `--set`)

| scenario | win % | battle s | vs baseline | contact s | destroyed | alive | in band |
|---|---|---|---|---|---|---|---|
| open_field | 100 | 40.5 | +8.9% | 6.0 | 1 | 5 | yes |
| walled_nucleus | 100 | 78.1 | +3.7% | 5.7 | 3 | 3 | yes |
| short_wall | 100 | 62.5 | +4.0% | 6.8 | 1 | 3 | yes |
| long_wall | 100 | 78.0 | +3.6% | 3.2 | 3 | 3 | yes |
| phage_priority | 100 | 67.5 | +6.5% | 13.4 | 2 | 2 | yes |
| mixed | 0 | 23.3 | +6.4% | 4.6 | 1 | 0 | yes |
| stress | 100 | 17.6 | -14.6% | 2.5 | 10 | 30 | yes |

All seven scenarios are in band. Trade-offs and caveats:

- First contact is now noticeably later in several scenarios (open_field 3.4 -> 6.0 s, walled_nucleus 3.2 -> 5.7 s). Time to first contact is not a band metric, but players will see slower approaches. The 20x20 contact times were about 3 s, and the slower speeds are what keep the total battle length in band.
- `stress` has the least margin: 17.6 s against a lower band edge of 16.5 s.
- `phage_priority` sits on a speed cliff (1.2 vs 1.1). 1.15 is inside the stable region only on this seed and jitter; a different seed could differ slightly.
- Rhinovirus speed in map terms is now about 1.4 x 2 = 2.8 tiles/s over a 40-tile map, i.e. about 1.4 tiles/s per 20-tile-equivalent, roughly 44% slower than at 20x20. That is a visible change to the swarm's feel. If the owner prefers to keep the Rhinovirus fast, `stress` can be left out of band as a documented exception, or tuned with a wall `hp` raise (which changes the wall economy).
- `battle_timeout_s` (180) is untouched. The longest median battle is about 78 s.

## Wall-ring economy check (about the same cost)

Definition: a square ring at the same share of the map area. At 20x20 the typical ring is 14x14, with 4 x 13 = 52 walls (49% of the map area, around the 2x2 Nucleus). The 40x40 ring holding the same area share is 28x28, with 4 x 27 = 108 walls.

| | walls | cost per wall | total |
|---|---|---|---|
| 20x20 ring (14x14) | 52 | 10 ATP | **520 ATP** |
| 40x40 ring (28x28, same area share) | 108 | 5 ATP | **540 ATP** |

The difference is +3.8%, so the "about the same" claim in the spec holds. No cost change is needed.

## Path budget (`max_path_recalcs_per_tick` = 20) in `stress`

Measured at the current data values with a throwaway script that steps `Scenarios.stress` over the full 40x40 deploy band, for both a 1-deep and 2-deep ring (`computations_this_tick` per tick, plus the number of ticks each pathogen stood still while not attacking). Both runs were identical:

- 238 ticks (11.9 s), 212 path computations in total, peak 20 per tick (the budget).
- 5 saturated ticks, all consecutive: 0.25 s at 20 ticks/s, well under the 1 s threshold.
- No pathogen was motionless (and not attacking) for more than 3 ticks (0.15 s).

Finding: the budget saturates briefly at the start of the battle but never for anything close to 1 s, and no unit visibly freezes. **No change to `max_path_recalcs_per_tick` is proposed.** This was not re-measured with the proposed speeds. Slower units spread repaths over more ticks, so saturation should not get worse.

## Reproducing the "after" table

```bash
for s in open_field walled_nucleus short_wall long_wall phage_priority mixed stress; do
  godot --headless --path . -s tools/balance_sim.gd -- --scenario=$s --runs=100 --jitter=3 --seed=12345 \
    --set=pathogens.rhinovirus.speed_tiles_s=1.4 \
    --set=pathogens.bacteriophage.speed_tiles_s=1.15 \
    --out=out/after_$s.csv
done
```

## Follow-up if the owner approves

- Apply the diff above to `data/pathogens.json`.
- Update tests that assert the old speeds (search `tests/` for the 2.5 and 1.5 speeds, e.g. `tests/unit/test_config.gd`).
- Update `docs/MVP_UI_SPEC.md` section 8's stat readout note if the speeds are displayed.
- Re-run the 20x20 vs 40x40 comparison.
