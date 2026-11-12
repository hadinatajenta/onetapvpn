#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_ICON="$ROOT/onetapicon.jpeg"
OUTPUT_ICON="$ROOT/Resources/AppIcon.icns"
WORK_DIR="$(mktemp -d)"
ICONSET_DIR="$WORK_DIR/AppIcon.iconset"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

if [ ! -f "$SOURCE_ICON" ]; then
    echo "Missing source icon: $SOURCE_ICON" >&2
    exit 1
fi

mkdir -p "$ICONSET_DIR" "$(dirname "$OUTPUT_ICON")"

RENDERED_ICON="$WORK_DIR/AppIcon-1024.png"
swift "$ROOT/scripts/render-icon.swift" "$SOURCE_ICON" "$RENDERED_ICON"

for size in 16 32 128 256 512; do
    sips -s format png -z "$size" "$size" "$RENDERED_ICON" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -s format png -z "$retina_size" "$retina_size" "$RENDERED_ICON" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICON"

echo "Wrote $OUTPUT_ICON"
