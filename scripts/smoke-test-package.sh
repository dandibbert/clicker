#!/bin/bash
# Install the ZIP and DMG into disposable folders, then launch the actual app.
# --smoke-test disables input services and exits after the native window appears.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${CLICKER_VERSION:-1.0.0}"
ARCH="${CLICKER_EXPECTED_ARCH:-$(uname -m)}"
BASE="Clicker-${VERSION}-macos-${ARCH}"
DIST="$PWD/dist"
EVIDENCE="$DIST/smoke-evidence"
mkdir -p "$EVIDENCE"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/clicker-install-smoke.XXXXXX")
MOUNT="$WORK/volume"
APP_PID=
MOUNTED=false
cleanup() {
    if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    if [[ "$MOUNTED" == true ]]; then hdiutil detach "$MOUNT" >/dev/null || true; fi
    rm -rf "$WORK"
}
trap cleanup EXIT

for suffix in zip dmg build-info.json; do
    (cd "$DIST" && shasum -a 256 -c "$BASE.$suffix.sha256")
done

launch_and_verify() {
    local app="$1" format="$2"
    test -x "$app/Contents/MacOS/Clicker"
    test "$(lipo -archs "$app/Contents/MacOS/Clicker")" = "$ARCH"
    codesign --verify --deep --strict "$app"
    local report="$EVIDENCE/$format-launch.json"
    local home="$WORK/$format-home"
    mkdir -p "$home"
    HOME="$home" CFFIXED_USER_HOME="$home" \
        "$app/Contents/MacOS/Clicker" --smoke-test --smoke-report "$report" \
        > "$EVIDENCE/$format-launch.log" 2>&1 &
    APP_PID=$!
    local elapsed=0
    while kill -0 "$APP_PID" 2>/dev/null; do
        if [[ "$elapsed" -ge 30 ]]; then
            echo "Packaged $format app did not finish its safe launch within 30 seconds" >&2
            cat "$EVIDENCE/$format-launch.log" >&2
            return 1
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    local status=0
    wait "$APP_PID" || status=$?
    APP_PID=
    if [[ "$status" -ne 0 ]]; then
        cat "$EVIDENCE/$format-launch.log" >&2
        return "$status"
    fi
    python3 - "$report" "$app" "$DIST/$BASE.build-info.json" <<'PY'
import json
from pathlib import Path
import sys

report = json.loads(Path(sys.argv[1]).read_text())
provenance = json.loads(Path(sys.argv[3]).read_text())
assert report["status"] == "passed", report
assert report["safeMode"] is True, report
assert report["globalInputServicesStarted"] is False, report
assert report["bundleIdentifier"] == "local.rayscripts.clicker", report
assert Path(report["bundlePath"]).resolve() == Path(sys.argv[2]).resolve(), report
assert report["sourceCommit"] == provenance["sourceCommit"], report
assert report["windowTitle"] == "Clicker", report
assert report["contentWidth"] >= 760 and report["contentHeight"] >= 480, report
print(json.dumps(report, indent=2))
PY
}

mkdir -p "$WORK/zip-install" "$WORK/dmg-install" "$MOUNT"
ditto -x -k "$DIST/$BASE.zip" "$WORK/zip-install"
launch_and_verify "$WORK/zip-install/Clicker.app" zip

hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DIST/$BASE.dmg"
MOUNTED=true
test "$(readlink "$MOUNT/Applications")" = /Applications
ditto "$MOUNT/Clicker.app" "$WORK/dmg-install/Clicker.app"
hdiutil detach "$MOUNT"
MOUNTED=false
launch_and_verify "$WORK/dmg-install/Clicker.app" dmg
echo "Both installed package formats passed their native-window smoke launch."
