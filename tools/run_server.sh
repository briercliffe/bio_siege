#!/usr/bin/env bash
# Starts a local Nakama (Docker) with the Bio Siege TypeScript module built from server/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../server"
npm ci
npm run build
docker compose up "$@"
