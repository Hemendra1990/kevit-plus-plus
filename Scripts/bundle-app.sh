#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIGURATION="${1:-debug}"
APP_NAME="Kevit++"
EXEC_NAME="KevitPlusPlus"
APP_DIR="$ROOT/.build/${APP_NAME}.app"

echo "Building ${EXEC_NAME} (${CONFIGURATION})..."
if [[ "$CONFIGURATION" == "release" ]]; then
  swift build -c release --product "$EXEC_NAME"
  BIN="$ROOT/.build/release/${EXEC_NAME}"
else
  swift build --product "$EXEC_NAME"
  BIN="$ROOT/.build/debug/${EXEC_NAME}"
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN" "$APP_DIR/Contents/MacOS/${EXEC_NAME}"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

if [[ -d "$ROOT/Resources/Excalidraw" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources/Excalidraw"
  cp -R "$ROOT/Resources/Excalidraw/." "$APP_DIR/Contents/Resources/Excalidraw/"
fi

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP_DIR/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$APP_DIR/Contents/Info.plist"
fi

# Copy SwiftPM resource bundles if present
shopt -s nullglob
for bundle in "$ROOT/.build/${CONFIGURATION}"/*.bundle "$ROOT/.build/${CONFIGURATION}/"*.bundle; do
  [[ -e "$bundle" ]] || continue
  cp -R "$bundle" "$APP_DIR/Contents/Resources/" 2>/dev/null || true
done
# Also search deeper for dependency bundles
while IFS= read -r bundle; do
  cp -R "$bundle" "$APP_DIR/Contents/Resources/" 2>/dev/null || true
done < <(find "$ROOT/.build" -type d -name "*.bundle" 2>/dev/null | head -50)

echo "Built app: $APP_DIR"
echo "Run with: open \"$APP_DIR\""
