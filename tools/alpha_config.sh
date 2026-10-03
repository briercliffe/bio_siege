#!/usr/bin/env bash
# Prepares a checkout for a closed-alpha build (CI only, never commit the result):
#   1. Turns on every flag in infra/alpha_flags.txt in data/game_rules.json. Run it before building the APK,
#      the server bundle and the worker image so all three share one content hash.
#   2. With BIO_SIEGE_SERVER_URL and BIO_SIEGE_SERVER_KEY set, writes the bio_siege/server/url and /key
#      project settings for the APK.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

RULES=data/game_rules.json
FLAGS_FILE=infra/alpha_flags.txt

while IFS= read -r line || [ -n "$line" ]; do
	flag="${line%%#*}"
	flag="${flag//[[:space:]]/}"
	[ -z "$flag" ] && continue
	if [ "$(grep -c "\"$flag\": \(true\|false\)" "$RULES")" != "1" ]; then
		echo "alpha_config: flag '$flag' must appear exactly once in $RULES" >&2
		exit 1
	fi
	sed -i "s/\"$flag\": false/\"$flag\": true/" "$RULES"
	echo "alpha_config: $flag on"
done < "$FLAGS_FILE"

if [ -n "${BIO_SIEGE_SERVER_URL:-}" ] || [ -n "${BIO_SIEGE_SERVER_KEY:-}" ]; then
	: "${BIO_SIEGE_SERVER_URL:?BIO_SIEGE_SERVER_URL is required with BIO_SIEGE_SERVER_KEY}"
	: "${BIO_SIEGE_SERVER_KEY:?BIO_SIEGE_SERVER_KEY is required with BIO_SIEGE_SERVER_URL}"
	case "$BIO_SIEGE_SERVER_URL" in
		https://*) ;;
		*) echo "alpha_config: BIO_SIEGE_SERVER_URL must be https:// (Android blocks cleartext HTTP)" >&2; exit 1 ;;
	esac
	if grep -q "^\[bio_siege\]" project.godot; then
		echo "alpha_config: project.godot already has a [bio_siege] section" >&2
		exit 1
	fi
	printf '\n[bio_siege]\n\nserver/url="%s"\nserver/key="%s"\n' "$BIO_SIEGE_SERVER_URL" "$BIO_SIEGE_SERVER_KEY" >> project.godot
	echo "alpha_config: server url $BIO_SIEGE_SERVER_URL"
fi
