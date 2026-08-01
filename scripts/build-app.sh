#!/bin/bash
# 将 SPM 可执行产物打包为标准 .app（dist/Clicker.app）
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=dist/Clicker.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Clicker "$APP/Contents/MacOS/Clicker"
./scripts/build-icon.sh Resources/AppIcon.svg "$APP/Contents/Resources/Clicker.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
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
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>Clicker 需要辅助功能权限来录制和回放鼠标键盘操作。</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"

echo "打包完成：$APP"
