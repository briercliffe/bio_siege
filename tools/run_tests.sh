#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

if ! command -v godot >/dev/null 2>&1; then
    echo "Error: godot executable not found on PATH. Please run tools/install_godot.sh first." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

echo "Importing project..."
if ! godot --headless --path . --import; then
    echo "Import flag failed; falling back to editor quit-after..."
    godot --headless --path . --editor --quit-after 2
fi

echo "Running GUT tests..."
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
