#!/bin/bash
# Build a signed .app and archive it without losing executable bits or bundle metadata.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh "$@"

VERSION="${CLICKER_VERSION:-1.0.0}"
ARCH=$(lipo -archs dist/Clicker.app/Contents/MacOS/Clicker)
case "$ARCH" in
    arm64|x86_64) ;;
    *) echo "Unsupported release architecture: $ARCH" >&2; exit 65 ;;
esac

ARCHIVE="Clicker-${VERSION}-macos-${ARCH}.zip"
ditto -c -k --sequesterRsrc --keepParent dist/Clicker.app "dist/$ARCHIVE"
(
    cd dist
    shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
)
echo "发布包：dist/$ARCHIVE"
