#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
GODOT_BIN="$INSTALL_DIR/godot"
GODOT_URL="https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip"

export PATH="$INSTALL_DIR:$PATH"

if ! command -v godot >/dev/null 2>&1; then
    echo "Godot not found on PATH. Installing to $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"

    TMP_DIR=$(mktemp -d)
    ZIP_FILE="$TMP_DIR/godot.zip"

    echo "Downloading Godot 4.4.1-stable..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$ZIP_FILE" "$GODOT_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$ZIP_FILE" "$GODOT_URL"
    else
        echo "Error: Neither curl nor wget found." >&2
        exit 1
    fi

    echo "Extracting Godot binary..."
    EXTRACT_DIR="$TMP_DIR/extracted"
    mkdir -p "$EXTRACT_DIR"
    if command -v unzip >/dev/null 2>&1; then
        unzip -q -o "$ZIP_FILE" -d "$EXTRACT_DIR"
    elif command -v python3 >/dev/null 2>&1; then
        python3 -m zipfile -e "$ZIP_FILE" "$EXTRACT_DIR"
    elif command -v python >/dev/null 2>&1; then
        python -m zipfile -e "$ZIP_FILE" "$EXTRACT_DIR"
    else
        echo "Error: No unzip or python found to extract zip file." >&2
        exit 1
    fi

    BINARY_PATH=$(find "$EXTRACT_DIR" -type f -name "Godot_v*" | head -n 1)
    if [ -z "$BINARY_PATH" ]; then
        echo "Error: Godot binary not found in zip archive." >&2
        exit 1
    fi

    mv "$BINARY_PATH" "$GODOT_BIN"
    chmod +x "$GODOT_BIN"
    rm -rf "$TMP_DIR"
    echo "Installed Godot to $GODOT_BIN"
fi

godot --version
