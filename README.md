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

