#!/usr/bin/env bash
# Rebuilds Resources/AppIcon.icns from icon.svg.
# Each size is rendered directly from the vector (via QuickLook) rather than
# downscaled from the 1024 master, so small dock/menu sizes stay crisp.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DIR="$ROOT/Scripts/app-icon"
OUT="$DIR/out"
ICONSET="$OUT/AppIcon.iconset"

mkdir -p "$OUT"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

render() { # render <pixels> <output-file>
  local size="$1" dst="$2"
  qlmanage -t -s "$size" -o "$OUT" "$DIR/icon.svg" >/dev/null 2>&1
  mv "$OUT/icon.svg.png" "$dst"
}

for base in 16 32 128 256 512; do
  double=$((base * 2))
  render "$base"   "$ICONSET/icon_${base}x${base}.png"
  render "$double" "$ICONSET/icon_${base}x${base}@2x.png"
done

iconutil -c icns "$ICONSET" -o "$OUT/AppIcon.icns"
cp "$OUT/AppIcon.icns" "$ROOT/Resources/AppIcon.icns"

# 1024 master for reference / App Store style use
render 1024 "$ROOT/Resources/AppIcon-1024.png"

echo "Wrote $ROOT/Resources/AppIcon.icns and AppIcon-1024.png"
