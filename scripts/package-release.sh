#!/bin/bash
# Build both install formats without losing executable bits or bundle metadata.
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
DMG="Clicker-${VERSION}-macos-${ARCH}.dmg"
PROVENANCE="Clicker-${VERSION}-macos-${ARCH}.build-info.json"
cp dist/Clicker.app/Contents/Resources/build-info.json "dist/$PROVENANCE"

# A plain, read-only drag-to-Applications disk image. It has the same ad-hoc
# signature as the ZIP app; a DMG is not Developer ID signing or notarization.
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/clicker-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto dist/Clicker.app "$STAGING/Clicker.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/安装说明.txt" <<'INSTRUCTIONS'
将 Clicker.app 拖到 Applications（应用程序）后打开。
需要 macOS 14 或更新版本；请下载匹配处理器的版本。

此安装包未执行 Apple 公证。自动构建默认使用 ad-hoc 签名，没有 Developer ID 签名。
首次打开可能被 macOS 阻止。确认下载来源后，可在系统设置 → 隐私与安全性中允许打开。
组织管理的 Mac 可能不允许运行此类应用。
请仅向你信任的应用授予辅助功能与输入监控权限。
INSTRUCTIONS
hdiutil create -volname Clicker -srcfolder "$STAGING" -format UDZO -ov "dist/$DMG"
hdiutil verify "dist/$DMG"
(
    cd dist
    for file in "$ARCHIVE" "$DMG" "$PROVENANCE"; do
        shasum -a 256 "$file" > "$file.sha256"
    done
)
echo "安装镜像：dist/$DMG"
echo "兼容 ZIP：dist/$ARCHIVE"
