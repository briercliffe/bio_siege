#!/usr/bin/env bash
# Runs the headless validation worker against a local Nakama (tools/run_server.sh).
# Extra arguments go to the worker, e.g. `tools/run_worker.sh --once`.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

URL="${BIO_SIEGE_SERVER_URL:-http://127.0.0.1:7350}"
HTTP_KEY="${BIO_SIEGE_HTTP_KEY:-bio_siege_dev_http_key}"

# Refresh the class cache so new class_name scripts resolve.
godot --headless --path . --import >/dev/null 2>&1 || true

exec godot --headless --path . -s tools/worker/worker.gd -- --url="$URL" --http-key="$HTTP_KEY" "$@"
