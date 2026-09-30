# Bio Siege

[![CI](https://github.com/briercliffe/bio_siege/actions/workflows/ci.yml/badge.svg)](https://github.com/briercliffe/bio_siege/actions/workflows/ci.yml)

Bio Siege is a biological reverse tower defense and base-building game where players design immune defenses in a cellular environment and attack their own base with pathogen swarms in an "Attack Your Own Base" sandbox loop. Players balance ATP resources across defense construction (Synthesis), army composition and perimeter deployment (Incubation), and deterministic combat simulation (Infection).

## Play it

**[Play the latest build in your browser](https://briercliffe.github.io/bio_siege/)**: no install needed. The first launch shows a short "How to play" walkthrough (reopen it any time with the "?" button), and the speaker button mutes the sound effects. The build is deployed to GitHub Pages from `main` by `.github/workflows/deploy-pages.yml`.

## How to run

Ensure Godot 4.7.2 is installed (you can run `tools/install_godot.sh` on Linux / WSL to install Godot to `$HOME/.local/bin/godot`).

To launch the project:
```bash
godot --path .
```
Or open the project in the Godot 4.7 editor and run the main scene (`src/main.tscn`).

## How to test

Run the automated test suite using GUT:
```bash
tools/install_godot.sh
tools/run_tests.sh
```
`tools/run_tests.sh` imports the project headlessly and executes all GUT test suites under `res://tests`.

## Balance simulator

The balance simulator CLI runs batch headless battles with deploy jitter, stat overrides, parameter sweeps, and CSV output:

```bash
# 1. Run 100 battles on a built-in scenario with deploy jitter
godot --headless --path . -s tools/balance_sim.gd -- --scenario=mixed --runs=100

# 2. Run battles with stat overrides
godot --headless --path . -s tools/balance_sim.gd -- --scenario=stress --set=pathogens.rhinovirus.hp=40 --runs=50 --jitter=3

# 3. Sweep a stat across a range and export results to CSV
godot --headless --path . -s tools/balance_sim.gd -- --scenario=short_wall --sweep=structures.mucous_wall.hp:100:500:100 --runs=20 --out=sweep_results.csv
```

Identity options (all optional; old command lines behave as before):

```bash
# --flag=<name> (repeatable): turn on a feature flag, same as --set=rules.feature_flags.<name>=true
godot --headless --path . -s tools/balance_sim.gd -- --scenario=repeat_swarm --flag=bcell_analysis --runs=20

# --strain=<type>:<variant> (repeatable): give every unit of a type a strain (needs --flag=strains)
godot --headless --path . -s tools/balance_sim.gd -- --scenario=repeat_swarm --flag=strains --strain=rhinovirus:capsid_hardening --runs=20

# --memory=<key>:<level>[,<key>:<level>...]: starting immune memory (needs bcell_analysis + immune_memory)
godot --headless --path . -s tools/balance_sim.gd -- --scenario=repeat_swarm --flag=bcell_analysis --flag=immune_memory --memory=rhinovirus/wild:3 --runs=20

# --generations=G (1-50): consecutive battles per run with memory carried forward; prints a gen=<g> summary line per generation
godot --headless --path . -s tools/balance_sim.gd -- --scenario=repeat_swarm --flag=bcell_analysis --flag=immune_memory --generations=5 --runs=20
```

`repeat_swarm` is the reference scenario for "repeating one strain gets punished": Nucleus, two B-Cells and a Macrophage defending against 20 Rhinoviruses. The CSV gains trailing columns `generation,score,analyzed_strains,memory_after,hijacks_completed,biofilm_max_group`. With `--generations=1` a run uses the plain run seed, so rows match the old output apart from the new columns.

### Telemetry report

`python3 tools/telemetry_report.py <logs...> --out report` writes `battles.csv` and `summary.txt`. `battles.csv` includes `flags_key`, `largest_strain_share`, `defense_share` and `score`, and `summary.txt` has an "Identity metrics" section with one block per flag set. Old logs still parse, with the new columns left empty.

