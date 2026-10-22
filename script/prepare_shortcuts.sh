#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/App/Resources/Shortcuts"
mkdir -p "$OUTPUT_DIR"
for source in "$ROOT_DIR"/Shortcuts/*.wflow; do
  name="$(basename "$source" .wflow)"
  /usr/bin/shortcuts sign --mode anyone --input "$source" --output "$OUTPUT_DIR/$name.shortcut"
done
