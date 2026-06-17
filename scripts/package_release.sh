#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Krill Floating Ball"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"

cd "$ROOT_DIR"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
ARCH="${RELEASE_ARCH:-$(uname -m)}"
ZIP_NAME="Krill-Floating-Ball-v${VERSION}-macOS-${ARCH}.zip"
ZIP_PATH="$ROOT_DIR/dist/$ZIP_NAME"

"$ROOT_DIR/scripts/build_app.sh" >/dev/null

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR"
fi

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "$ZIP_PATH"
