#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT_DIR/Brand/AppIcon.png"
DEST="$ROOT_DIR/App/Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$DEST"
for size in 16 32 64 128 256 512 1024; do
  sips -z "$size" "$size" "$SOURCE" --out "$DEST/icon-$size.png" >/dev/null
done
echo "Prepared iOS and macOS icons from Brand/AppIcon.png"
