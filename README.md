# Bio Siege

Bio Siege is a biological reverse tower defense and base-building game where players design immune defenses in a cellular environment and attack their own base with pathogen swarms in an "Attack Your Own Base" sandbox loop. Players balance ATP resources across defense construction (Synthesis), army composition and perimeter deployment (Incubation), and deterministic combat simulation (Infection).

## How to run

Ensure Godot 4.4.1 is installed (you can run `tools/install_godot.sh` on Linux / WSL to install Godot to `$HOME/.local/bin/godot`).

To launch the project:
```bash
godot --path .
```
Or open the project in the Godot 4.4 editor and run the main scene (`src/main.tscn`).

## How to test

Run the automated test suite using GUT:
```bash
tools/install_godot.sh
tools/run_tests.sh
```
`tools/run_tests.sh` imports the project headlessly and executes all GUT test suites under `res://tests`.
