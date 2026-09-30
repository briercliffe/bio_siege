#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
GODOT_BIN="$INSTALL_DIR/godot"
GODOT_VERSION="4.7.2"
GODOT_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"

export PATH="$INSTALL_DIR:$PATH"

if ! command -v godot >/dev/null 2>&1 || ! godot --version 2>&1 | grep -q "$GODOT_VERSION"; then
    echo "Godot $GODOT_VERSION not found on PATH. Installing to $INSTALL_DIR..."
    mkdir -p "$INSTALL_DIR"

    TMP_DIR=$(mktemp -d)
    ZIP_FILE="$TMP_DIR/godot.zip"

    echo "Downloading Godot ${GODOT_VERSION}-stable..."
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

configure_android_sdk() {
  # Only run if ANDROID_SDK_ROOT is set (i.e. in CI via android-actions/setup-android)
  if [ -z "${ANDROID_SDK_ROOT:-}" ]; then
    echo "ANDROID_SDK_ROOT not set — skipping Android SDK editor settings configuration"
    return 0
  fi

  local settings_dir="$HOME/.config/godot"
  local settings_file="$settings_dir/editor_settings-4.tres"
  mkdir -p "$settings_dir"

  if grep -q "export/android/android_sdk_path" "$settings_file" 2>/dev/null; then
    echo "Android SDK path already in editor settings — skipping"
    return 0
  fi

  cat >> "$settings_file" << EOF

[resource]
export/android/android_sdk_path = "$ANDROID_SDK_ROOT"
EOF

  echo "Wrote Android SDK path to $settings_file: $ANDROID_SDK_ROOT"
}

configure_android_sdk
