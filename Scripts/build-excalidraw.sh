#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="$ROOT/Scripts/excalidraw-host"

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required to rebuild the Excalidraw host." >&2
  exit 1
fi

cd "$HOST"
npm install
npm run build

ASSETS="$HOST/node_modules/@excalidraw/excalidraw/dist/excalidraw-assets"
OUT="$ROOT/Resources/Excalidraw"
if [[ -d "$ASSETS" ]]; then
  rm -rf "$OUT/excalidraw-assets"
  cp -R "$ASSETS" "$OUT/excalidraw-assets"
fi
echo "Wrote $OUT"
