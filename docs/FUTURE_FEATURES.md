# Bio Siege: Future Features

Ideas that were considered and parked. They are **not** in the roadmap. Revisit them after the phase gates in [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) section 14 pass.

## Fever (global defense)

Removed from Phase 2 (decision recorded in plan section 15, item 4).

- **What it was.** A once-per-battle global defense that deals damage per second to every pathogen for about 6 s. It wipes out low-HP units but also drains the defender's own structures at a lower rate.
- **Why it was hard.** In a raid the defender is an AI or offline, so nobody is there to press it. The plan's answer was an auto-trigger the defender configures in advance, such as "Nucleus HP below 50%" or "20 or more pathogens inside the walls".
- **Options if it returns.**
  - The configured auto-trigger above.
  - A live-defense mode where a human defender presses it, which needs a live defense feature that doesn't exist.
- **Interactions to remember.**
  - Fever is global damage with no attacker genome, so it should not be scaled by the coevolution receptor match (epic #141).
  - The "Antibiotic Resistance" gene-transfer trait was meant to reduce Fever damage. That trait stays on the donation list but needs a different effect if Fever stays out.

## Parasite (burrowing dropship)

Parked on 2026-10-01 (decision D2 in epic #147, plan section 15 row 13).

- **What it was.** Plan section 11's large, slow unit. It burrows: underground it can't be targeted, it ignores walls, and it surfaces next to its target after a travel time. On death it bursts into 4 fast, low-HP spores tagged `small`.
- **Why it was parked.** Identity proposal 4.6: it copies Clash directly (Miner plus Golem).
- **If it returns.**
  - Burrowing should also avoid *analysis exposure*, since it can't be targeted underground, not only walls.
  - Spores inherit the parent's genome index, and their damage is credited to it so the burst doesn't double-count fitness.
  - The Mucous trap (`small` tag) would catch its spores.
