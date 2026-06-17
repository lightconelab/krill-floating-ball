#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Krill Floating Ball"
EXECUTABLE_NAME="TrellisFloatingBall"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
for resource in "$ROOT_DIR"/Resources/*; do
  if [[ -f "$resource" && "$(basename "$resource")" != "Info.plist" ]]; then
    cp "$resource" "$RESOURCES_DIR/"
  fi
done
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

echo "$APP_DIR"
