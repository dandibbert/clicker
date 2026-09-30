#!/bin/bash
# 将 SPM 可执行产物打包为标准 .app（dist/Clicker.app）
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${CLICKER_VERSION:-1.0.0}"
BUILD_NUMBER="${CLICKER_BUILD_NUMBER:-1}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "CLICKER_VERSION must have the form X.Y.Z (without a v prefix)." >&2
    exit 64
fi
if [[ ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "CLICKER_BUILD_NUMBER must be a positive integer." >&2
    exit 64
fi

# Forward Swift build options (e.g. --triple) and resolve the matching output path.
swift build -c release "$@"
BIN_PATH=$(swift build -c release "$@" --show-bin-path)

APP=dist/Clicker.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_PATH/Clicker" "$APP/Contents/MacOS/Clicker"
./scripts/build-icon.sh Resources/AppIcon.svg "$APP/Contents/Resources/Clicker.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Clicker</string>
    <key>CFBundleIdentifier</key><string>local.rayscripts.clicker</string>
    <key>CFBundleName</key><string>Clicker</string>
    <key>CFBundleDisplayName</key><string>Clicker</string>
    <key>CFBundleIconFile</key><string>Clicker</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Clicker 需要辅助功能权限来录制和回放鼠标键盘操作。</string>
    <key>NSInputMonitoringUsageDescription</key>
    <string>Clicker 需要输入监控权限来录制键盘操作并响应停止快捷键。</string>
</dict>
</plist>
PLIST

SIGNING_IDENTITY="${CLICKER_SIGNING_IDENTITY:--}"
if [ "$SIGNING_IDENTITY" = "-" ]; then
    codesign --force --deep --sign - --identifier local.rayscripts.clicker "$APP"
    echo "提示：当前为 ad-hoc 签名；更新应用后 macOS 可能要求重新授权辅助功能和输入监控。"
    echo "如已安装 Apple Development 证书，请设置 CLICKER_SIGNING_IDENTITY 后重新打包。"
else
    codesign --force --deep --sign "$SIGNING_IDENTITY" \
        --identifier local.rayscripts.clicker \
        "$APP"
fi

plutil -lint "$APP/Contents/Info.plist"
codesign --verify --deep --strict "$APP"
echo "打包完成：$APP ($VERSION, build $BUILD_NUMBER)"
