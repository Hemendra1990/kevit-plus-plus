#!/usr/bin/env bash
# Re-vendors the Markdown preview host's third-party libraries into
# Resources/Markdown/vendor/. The vendored copies are committed, so this only
# needs running when bumping the pinned versions below.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/Resources/Markdown/vendor"

MARKDOWN_IT_VERSION="14.1.0"
HIGHLIGHTJS_VERSION="11.11.1"

mkdir -p "$VENDOR"

curl -fsSL -o "$VENDOR/markdown-it.min.js" \
  "https://cdn.jsdelivr.net/npm/markdown-it@${MARKDOWN_IT_VERSION}/dist/markdown-it.min.js"
curl -fsSL -o "$VENDOR/highlight.min.js" \
  "https://cdn.jsdelivr.net/npm/@highlightjs/cdn-assets@${HIGHLIGHTJS_VERSION}/highlight.min.js"

echo "Vendored markdown-it ${MARKDOWN_IT_VERSION} and highlight.js ${HIGHLIGHTJS_VERSION} into $VENDOR"
echo "The app files (index.html / markdown.css / preview.js) are edited in place — no build step."
