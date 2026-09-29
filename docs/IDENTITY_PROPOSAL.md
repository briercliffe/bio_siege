# Bio Siege: Identity Proposal: "The Immune System Learns"

**Status: accepted (2026-09-29).** The numbers are starting values and will be tuned in playtests. Section 7 is tracked in epic #85 (issues #86 to #93). Every mechanic ships behind a feature flag that defaults to off, and a flag is switched on by default only after it passes the playtest gate in section 8. Section 9 lists the plan sections this amends. Nothing in `src/` or `data/` has been changed yet.

This document proposes making **adaptation** the core identity of Bio Siege. Defenses learn from what attacks them, and attackers have to evolve to get past what the defense remembers. Today the game and its roadmap are close to a Clash of Clans reskin. This proposal keeps what already works and replaces the parts that copy Clash with mechanics taken from how immune systems and pathogens actually behave.

---

## 1. Pitch

> **Your immune system remembers. Your pathogens mutate.**
>
> Every raid teaches the defense, and every defense forces the attack to evolve. A strategy that worked last time works less well the next time.

Clash progression is **accumulation**: wait on timers, raise levels, and the bigger numbers win. Bio Siege progression is **adaptation**: what your B-Cells have learned, what your strains have evolved to avoid, and how well you read the other side.

---

## 2. Why change

### 2.1 How close the current design is to Clash

| Bio Siege (built or planned) | Clash of Clans |
| --- | --- |
| Nucleus (4x4, destroy it to win) | Town Hall |
| Mucous Wall with weighted pathing (plan section 1.4) | Walls |
| Rhinovirus, Bacteriophage, Staphylococcus | Goblin, Wall Breaker, Giant |
| Macrophage (splash), B-Cell (long-range sniper) | Mortar or Wizard Tower, Archer Tower |
| 40x40 grid, 3x3 towers, deploy band, 3-minute timer | Home village |
| Mitochondria, Amino Acids, DNA/Plasmids | Gold mines, Elixir, Dark Elixir |
| Amino Acid `levels` upgrades, Mutation Lab | Building upgrades, Laboratory |
| Dendritic Cell (hidden until triggered) | Hidden Tesla |
| Parasite burrowing, bursting into spores | Miner, Golem and Lava Hound |
| Lymph Node, gene-transfer donations | Clan Castle, troop donations |
| Herd Immunity, Patient Zero | Clan Wars, Clan Capital raids |

If every phase ships as written, a player can learn Bio Siege by mapping it onto Clash. That makes it a harder sell than Clash, not an easier one.

### 2.2 What is already different

**Attack Your Own Base with one shared ATP pool.** Every ATP spent on the base is ATP the army doesn't get. Clash has nothing like it, and this proposal keeps it.

### 2.3 The gap in the current loop

- The results screen reports win or loss only. There is no score.
- The dominant strategy is to spend 0 ATP on defense. 1000 ATP of pathogens easily beats an undefended 2000 HP Nucleus.
- The player built the base, so there is nothing hidden to discover (plan section 8).

Without a goal, testers will find the dominant split and stop. Playtest question 1 (pivot friction) can't measure fun on a loop that has no objective.

---

## 3. Design pillars

Every mechanic, current or planned, is checked against these four pillars. A feature that fails two of them is cut or reworked.

1. **Adaptation over accumulation.** Power comes from learning and evolution, not from timers and flat stat upgrades.
2. **Repetition gets punished.** Using the same approach again makes its counter stronger. The game balances against its own meta by design.
3. **Readable biology.** Each mechanic matches a real immune or microbial process, and its state is always shown on screen. Hidden state that the player can't see or predict isn't allowed. This supports the legibility metric (plan section 5, question 2).
4. **Deterministic and fair.** Every adaptation rule is sim code using integer math, replayable from the seed and input log, so a server can verify it (plan section 12).

---

## 4. Core mechanics

The first three sections below make up the identity. Sections 4.4 to 4.6 support it.

### 4.1 Innate and adaptive defense

The defense roster is split along the real biological line:

| Layer | Structures | Behavior |
| --- | --- | --- |
| **Innate** | Mucous Wall, Macrophage | Fixed strength, active from the first tick, never learns. Reliable, but it can be planned around. |
| **Adaptive** | B-Cell (later T-Cells and memory cells) | Weak against something new and strong against something it has seen. |

This split becomes the basic defense tradeoff: pay for power that is predictable now, or for power that grows over time.

### 4.2 In-battle learning (B-Cell analysis, promoted to core)

This is plan section 9 "B-Cell analysis", moved from a stretch goal into the core design.

- Each B-Cell keeps an **exposure counter in ticks** for each strain it attacks (strains are defined in section 4.4).
- When the counter reaches a threshold, the tower has **analyzed** that strain and deals `multiplier_pct` damage to it for the rest of the battle. The proposed threshold is 200 ticks (10 s at 20 ticks/s), with `multiplier_pct` 300.
- Only integer math is used: `damage * multiplier_pct / 100`.
- The analysis belongs to the individual tower. Dendritic Cells can share it (section 4.6).
- **What the player sees:** a progress ring on the tower while it analyzes, then a strain badge on the tower once analysis completes. Intent lines are unchanged.
- **Balance flag:** 75 x 3 = 225 one-shots every unit except Staphylococcus. B-Cell base damage probably needs to drop to about 50. The balance sim decides.

**Why it matters:** against 30 identical Rhinoviruses, every B-Cell finishes analyzing within the first few kills, so a single-type swarm gets weaker the longer the fight lasts. Mixed armies spread exposure across strains. That makes army diversity a skill.

### 4.3 Immune memory between raids (new)

Learning carries over from one raid to the next. This is the mechanic Clash doesn't have.

- Each base stores a **memory table**: `strain_key -> level` with levels 0 to 3.
- **Gain:** after a raid, every strain that at least one B-Cell fully analyzed gains 1 level, up to the cap.
- **Effect:** at level L, each B-Cell starts the battle with `L * 25%` of the analysis threshold already filled for that strain. Level 3 therefore means B-Cells need only a quarter of the usual exposure.
- **Waning immunity:** a remembered strain loses 1 level after `memory_decay_raids` raids in a row without it (proposed value: 2).
- **Repertoire cap:** a base remembers at most `memory_slots` strains (proposed value: 3). When a new strain comes in, the one with the lowest level is dropped, and ties go to the oldest.
- Memory lives on the **base snapshot**, not on individual towers. Selling a B-Cell doesn't erase memory, and a base with no B-Cells can't use it.
- **What the player sees:** a "Memory" panel in Synthesis and Incubation lists each remembered strain with its level pips. The attacker sees it before choosing an army. Memory is never hidden.

Decay and the repertoire cap keep memory from ratcheting upward forever. An attacker who rotates three or four strains stays ahead. An attacker who repeats one strain runs into level 3.

### 4.4 Strains and mutation (replaces the Clash-style Laboratory)

Memory tracks **strains**, not unit types, so mutation is how an attacker gets around memory.

- A strain is a pathogen type plus an **antigen variant**, for example `rhinovirus/wild` (the unmutated form every type has) or `rhinovirus/capsid_hardening`.
- Every pathogen type has 2 to 4 variants besides `wild`, listed in `pathogens.json` under a new `strains` array. Each variant carries a **trait with a tradeoff**, applied to the unit's stats when it spawns:

| Example variant | Upside | Downside | Biology |
| --- | --- | --- | --- |
| Capsid Hardening | +15% HP | -10% speed | Tougher protein coat |
| Rapid Replication | -20% ATP cost | -15% HP | Faster but sloppier copying |
| Antigenic Masking | Analysis against it is 50% slower | -10% damage | Surface proteins hidden from antibodies |

- **Antigenic drift:** a strain's memory gives **50% of its level** (rounded down) against other variants of the same type. Switching variant gets past most of the memory, not all of it.
- **Antigenic shift:** a type the base has never seen gets no cross-protection at all.
- The attacker picks one variant per pathogen type during Incubation. The Mutation Lab (plan section 10) becomes the place where **new variants are unlocked**, not the place where flat stats are raised.

This replaces "Capsid Hardening: +15% HP forever" (a Clash lab upgrade) with "Capsid Hardening: a new antigen that trades speed for HP" (a choice that has a counter).

### 4.5 Pathogen collective behavior (promoted to core)

These two mechanics give pathogens behavior that no Clash troop has. Both are specified in plan section 9 and change from stretch goals to core features.

- **Biofilm (Staphylococcus):** nearby units link up, split incoming damage evenly across the group, and take 25% less damage. Formation becomes part of planning an attack.
- **Bacteriophage hijack:** a 2 s injection channel that disables a tower for 8 s and consumes the phage. This uses `StatusEffects.Kind.DISABLED`, which already exists. The phage becomes the attacker's answer to a strongly adapted B-Cell: switch off the tower that remembers you.

### 4.6 Supporting defenses (reframed)

| Planned item | Current framing | Proposed framing |
| --- | --- | --- |
| Dendritic Cell | Hidden trap that reveals itself and buffs attack speed (Hidden Tesla) | **Antigen presenter:** always visible. It shares any analysis completed within 4 tiles with every B-Cell in that radius. Hiding it goes against pillar 3. |
| Fever | Configured global damage with self-harm | Kept as is. It fits pillar 1: it is the defender's authored rule, and it costs them too. |
| Mucous Membrane trap | Roots `small` units | Kept, and it counts as innate. |
| Parasite burrow and spores | Miner plus Golem | **Deprioritized.** It copies Clash directly. If it is built, burrowing should avoid *analysis* (untargetable, so it builds no exposure), not only walls. |

---

## 5. Giving the self-raid loop a goal

### 5.1 Score the base you beat

When the attack wins, the **score is the ATP value of the base at the start of the raid**. When the defense holds, the score is 0.

- Spending 0 on defense gives a win and a score of 0.
- Spending 900 on defense leaves 100 ATP of army, which will probably fail and also score 0.
- The puzzle is to find the **strongest base you can still break**. That turns the shared budget from a free choice into a real optimization, and it removes the dominant strategy.
- This is computed in core from `BattleSim` state and the base snapshot, and needs unit tests (CLAUDE.md rule 6). The Results screen shows the score next to the ATP split bar.

### 5.2 Outbreak run (the main single-player mode)

A run is a series of **generations** against one base that keeps learning:

1. Start with a new base and 1000 ATP. Build, then raid (the current loop).
2. If the raid succeeds, the generation scores (section 5.1) and the base **updates its memory** (section 4.3).
3. The next generation starts with the same base and a fresh 1000 ATP. The player can edit the base (sales keep the 100% refund) and pick a new army and new strains.
4. The run ends on the first raid where the defense holds. **Run score = the sum of generation scores.**

Repeating an army makes each generation harder. To keep a run going, the player has to rotate strains, mutate, bring phages to hijack adapted towers, or lower defense spend and accept a smaller score. That tension is the identity loop, and it works in single-player without any server.

The existing single-battle sandbox stays as **Lab** mode: no scoring, memory can be edited, and it is the place to experiment.

---

## 6. How identity reshapes the roadmap

| Plan item (Part II) | Decision | New shape |
| --- | --- | --- |
| Section 9 stretch mechanics | **Promote** | B-Cell analysis, Biofilm and hijack become core Phase 1.5 work (section 7) |
| Mitochondria and ATP generation | Keep, lower priority | The economy stays, but it is no longer what the game is about |
| Amino Acid `levels` upgrades | **Cut or shrink** | Flat HP and damage levels go against pillar 1. If upgrades are kept, they unlock *breadth* (another memory slot, faster analysis), not size |
| DNA/Plasmids and the Mutation Lab | **Reframe** | They unlock strain variants (section 4.4), not stat upgrades |
| Async raids (Phase 3) | Keep, and memory makes them deeper | Every defended raid updates the defender's memory. **Popular strains become less effective on their own**, because more bases remember them. The meta rebalances itself with no global rule (see below) |
| Lymph Node (clan castle) | **Reframe as vaccination** | Clanmates donate memory of strains they've seen to your base, up to 1 level per strain. It is the clan version of immunization, not a box of donated troops |
| Gene transfer (donations) | Keep, and it now fits | Donating a *variant* for the requester's next raid is how plasmids really work |
| Patient Zero (Phase 5a) | **Reframe** | The boss base's memory builds up across every clan member's attack in the 48 h window. The clan has to coordinate strain rotation, which is a coordination problem no Clash mode poses |
| Herd Immunity (Phase 5b) | Keep the name and make it literal | Memory spreads between neighbouring bases in the clan network |

**Self-balancing meta (Phase 3).** Matchmaking hands each attacker a real defended base. Bases get raided most often by the most popular strains, so the popular strains are what bases remember. A dominant army should counter itself over time. The balance team still tunes, but the game already pushes back against a single dominant strategy. Server telemetry should track strain usage share against win rate to confirm this happens.

---

## 7. Proposed work (Phase 1.5: Identity)

Each item is a GitHub issue under epic #85 (item 1 is #86, through item 8 as #93), one PR per issue (CLAUDE.md rule 9). Every item is behind a feature flag in `game_rules.json` so a second playtest round can A/B it (plan section 9). Items that change `data/*.json` need an issue that explicitly asks for it (CLAUDE.md rule 5).

| # | Work | Main areas | Flag |
| --- | --- | --- | --- |
| 1 | Self-raid score (section 5.1) and the Results screen readout | `src/core` scoring, `results_phase`, telemetry | `raid_score` |
| 2 | B-Cell analysis: an exposure map for each tower and strain, a multiplier, an `analysis_complete` sim event, the progress ring and badge | `structure_state.gd`, `battle_sim.gd`, `sim_events.gd`, view, `structures.json` (`analysis` block) | `bcell_analysis` |
| 3 | Strains: a strain id on each army entry and pathogen state, variant traits applied to unit stats at spawn, a variant picker in Incubation | `army.gd`, `pathogen_state.gd`, `battle_setup.gd`, `hud_spawn`, `pathogens.json` (`strains`) | `strains` |
| 4 | Immune memory: a memory table as an optional block in the base snapshot, a memory update after each raid, pre-seeded exposure through `BattleSetup`, the Memory panel | `snapshot_io.gd`, `session.gd`, `battle_setup.gd`, UI | `immune_memory` |
| 5 | Outbreak run mode: tracking generations, the run score, and end-of-run results | `game_state_machine.gd`, `session.gd`, UI | `outbreak_mode` |
| 6 | Biofilm (plan section 9) | `battle_sim.gd`, union-find helper in core | `biofilm` |
| 7 | Bacteriophage hijack (plan section 9) | `battle_sim.gd`, `StatusEffects.DISABLED` | `phage_hijack` |
| 8 | Balance sim: flags, strains and memory as inputs, multi-generation runs. Telemetry report: the section 8 metrics split by flag set | `tools/balance_sim.gd`, `tools/telemetry_report.py` | — |

Suggested order: 1, then 2, then 3 and 4 together, then 5. Items 6 and 7 are independent and can run alongside. Item 1 is a small change and fixes the loop's missing goal on its own.

---

## 8. Measuring whether it worked

These add to the playtest metrics in plan section 5. Each is compared with the flag switched off.

| Question | Measure | Go target (proposal) |
| --- | --- | --- |
| Does learning change what players field? | Army diversity: the share of the army's ATP in its largest single strain | Median share falls by at least 15 points with `bcell_analysis` on |
| Does the loop have a goal? | Share of sessions where defense spend is above 20% of the budget | At least 70% with `raid_score` on (today's dominant strategy is 0%) |
| Does memory create an arms race? | Outbreak run length; how often the army changes between generations | Median run of at least 3 generations; strain mix changes in at least 60% of generations |
| Is it still readable? | Prediction accuracy (plan section 5, question 2); survey question "I understood why my B-Cells got stronger" | Prediction accuracy stays at 60% or above; median survey answer 4 or above |
| Is it fun? | Pivot rating and a new "one more generation" rating | Both medians at 3.5 or above |

If `bcell_analysis` and `immune_memory` don't beat the flag-off baseline, the identity doesn't work as designed. Don't start Phase 2 until that is solved.

---

## 9. Amended plan sections

| Plan section | Change |
| --- | --- |
| 1.8 Post-battle loop | Add the score to Results. Add the Outbreak "next generation" action next to Re-raid, Edit base and New base. |
| 8 Full vision fit | Rows for B-Cell analysis, hijack and Biofilm move from "stretch goal" to "core, Phase 1.5". |
| 9 Stretch mechanics | Becomes Phase 1.5: Identity (section 7 above). |
| 10 Dual economy | Amino Acid upgrades are cut or become breadth-only. The Mutation Lab unlocks strain variants. |
| 11 Extended roster | Dendritic Cell becomes the antigen presenter (visible). Parasite is deprioritized. |
| 12 Async multiplayer | Memory is part of the defended snapshot and is updated by the server's re-simulated result. |
| 13 Clans | Lymph Node becomes vaccination. Patient Zero gets boss-base memory. |
| 14 Roadmap | Phase 1.5 grows to about 3–4 weeks. Its gate is section 8 above. |

---

## 10. Risks

| Risk | Mitigation |
| --- | --- |
| **Hidden complexity.** Players can't tell why a fight went differently. | Pillar 3: progress rings, strain badges and the Memory panel. The legibility metric is a hard gate (section 8). |
| **Snowballing.** Memory makes bases unbeatable. | Waning immunity, the repertoire cap and the 50% drift rule. All three are in JSON and swept in the balance sim. |
| **Degenerate mutation.** One variant dominates. | Every variant has a real downside. The balance sim sweeps strain mixes. |
| **Scope creep.** Phase 1.5 grows. | Item 1 ships first on its own. Everything else sits behind flags and can be cut item by item. |
| **Determinism.** New state breaks replay or hash checks. | Exposure counters and multipliers are integers. Memory is part of the snapshot. `state_hash()` covers the new fields, with tests. |
| **Biological accuracy.** The mechanics drift into fantasy. | Keep the mapping honest (memory B-cells, antigenic drift and shift, plasmids, biofilms). The how-to-play text names the real process. |

---

## 11. Open questions for design

1. Is the per-tower analysis (section 4.2) correct, or should analysis belong to the whole base? The plan's open question 7 also asks this. This proposal answers "per tower, shared by Dendritic Cells".
2. Should Macrophages gain a small innate bonus against strains in memory (trained immunity), or stay fixed?
3. Should memory be visible to the attacker in async raids (current proposal: yes, pillar 3), or should it be scouted?
4. Outbreak scoring: ATP value of the whole base (proposed), or only the value of structures destroyed?
5. Can the player spend ATP to "vaccinate" their own base in single-player, or does memory only come from raids?
6. How many variants per type at launch: 2 (simpler) or 3 (more rotation room)?
