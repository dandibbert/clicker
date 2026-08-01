#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <svg-source> <icns-output>" >&2
    exit 64
fi

SOURCE_SVG=$1
OUTPUT_ICNS=$2

if [[ ! -f "$SOURCE_SVG" || "$SOURCE_SVG" != *.svg ]]; then
    echo "SVG source must be an existing .svg file: $SOURCE_SVG" >&2
    exit 66
fi

if [[ "$OUTPUT_ICNS" != *.icns ]]; then
    echo "ICNS output must end with .icns: $OUTPUT_ICNS" >&2
    exit 64
fi

WORKSPACE=$(mktemp -d)
trap 'rm -rf "$WORKSPACE"' EXIT
ICONSET="$WORKSPACE/Clicker.iconset"
RENDERED_PNG="$WORKSPACE/Clicker.png"

mkdir -p "$ICONSET" "$(dirname "$OUTPUT_ICNS")"
sips -s format png -z 1024 1024 "$SOURCE_SVG" --out "$RENDERED_PNG" >/dev/null

while IFS=: read -r filename size; do
    sips -z "$size" "$size" "$RENDERED_PNG" --out "$ICONSET/$filename" >/dev/null
done <<'REPRESENTATIONS'
icon_16x16.png:16
icon_16x16@2x.png:32
icon_32x32.png:32
icon_32x32@2x.png:64
icon_128x128.png:128
icon_128x128@2x.png:256
icon_256x256.png:256
icon_256x256@2x.png:512
icon_512x512.png:512
icon_512x512@2x.png:1024
REPRESENTATIONS

iconutil -c icns "$ICONSET" -o "$OUTPUT_ICNS"
