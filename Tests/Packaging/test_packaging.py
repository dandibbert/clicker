"""Packaging contract tests; fake compiler/signing tools, real plist/ZIP/checksums."""
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[2]


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory()
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        shutil.copytree(ROOT / "scripts", self.root / "scripts")
        shutil.copytree(ROOT / "Resources", self.root / "Resources")
        self.tools = self.root / "tools"
        self.tools.mkdir()
        self.binary_directory = self.root / "compiled"
        self.binary_directory.mkdir()
        (self.binary_directory / "Clicker").write_bytes(b"fake executable\n")
        (self.binary_directory / "Clicker").chmod(0o755)
        self.log = self.root / "tools.log"
        self.env = os.environ.copy()
        for name in ("CLICKER_VERSION", "CLICKER_BUILD_NUMBER", "CLICKER_SIGNING_IDENTITY"):
            self.env.pop(name, None)
        self.env.update({
            "PATH": f"{self.tools}:{self.env['PATH']}",
            "MOCK_BIN_PATH": str(self.binary_directory),
            "MOCK_LOG": str(self.log),
            "MOCK_ARCH": "arm64",
        })
        stub = self.tools / "mock-tool"
        stub.write_text('''#!/bin/bash
set -euo pipefail
name=$(basename "$0")
printf '%s %s\\n' "$name" "$*" >> "$MOCK_LOG"
case "$name" in
    swift)
        if [[ " $* " == *" --show-bin-path "* ]]; then
            printf '%s\\n' "$MOCK_BIN_PATH"
        fi
        ;;
    sips)
        while [[ $# -gt 0 ]]; do
            if [[ "$1" == --out ]]; then touch "$2"; break; fi
            shift
        done
        ;;
    iconutil)
        while [[ $# -gt 0 ]]; do
            if [[ "$1" == -o ]]; then touch "$2"; break; fi
            shift
        done
        ;;
    codesign) ;;
    lipo) printf '%s\\n' "$MOCK_ARCH" ;;
esac
''')
        stub.chmod(0o755)
        for name in ("swift", "sips", "iconutil", "codesign", "lipo"):
            (self.tools / name).symlink_to(stub.name)

    def run_script(self, name, *args, **env):
        return subprocess.run(
            ["bash", str(self.root / "scripts" / name), *args],
            cwd=self.root,
            env={**self.env, **env},
            capture_output=True,
            text=True,
        )

    def test_release_archive_metadata_contents_and_checksum(self):
        result = self.run_script(
            "package-release.sh", CLICKER_VERSION="2.3.4", CLICKER_BUILD_NUMBER="42"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        archive = self.root / "dist" / "Clicker-2.3.4-macos-arm64.zip"
        with zipfile.ZipFile(archive) as bundle:
            info = plistlib.loads(bundle.read("Clicker.app/Contents/Info.plist"))
            self.assertEqual(info["CFBundleShortVersionString"], "2.3.4")
            self.assertEqual(info["CFBundleVersion"], "42")
            self.assertEqual(info["LSMinimumSystemVersion"], "14.0")
            self.assertIn("Clicker.app/Contents/MacOS/Clicker", bundle.namelist())
            self.assertIn("Clicker.app/Contents/Resources/Clicker.icns", bundle.namelist())
        checksum = Path(f"{archive}.sha256").read_text().strip()
        self.assertEqual(checksum, f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}")
        self.assertIn("codesign --verify --deep --strict", self.log.read_text())

    def test_default_version_and_custom_signing_identity_with_build_arguments(self):
        result = self.run_script(
            "build-app.sh", "--triple", "x86_64-apple-macosx14.0",
            CLICKER_SIGNING_IDENTITY="Apple Development: Test",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        info = plistlib.loads((self.root / "dist/Clicker.app/Contents/Info.plist").read_bytes())
        self.assertEqual(info["CFBundleShortVersionString"], "1.0.0")
        log = self.log.read_text()
        self.assertIn("swift build -c release --triple x86_64-apple-macosx14.0", log)
        self.assertIn("--show-bin-path", log)
        self.assertIn("--sign Apple Development: Test", log)

    def test_invalid_metadata_is_rejected_before_building(self):
        for env in (
            {"CLICKER_VERSION": "v1.2.3"},
            {"CLICKER_VERSION": "1.2.3</string>"},
            {"CLICKER_VERSION": "1.2.3-rc1"},
            {"CLICKER_BUILD_NUMBER": "not-a-number"},
            {"CLICKER_BUILD_NUMBER": "0"},
        ):
            with self.subTest(env=env):
                result = self.run_script("build-app.sh", **env)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(self.log.exists(), "Invalid metadata must fail before building")

    def test_intel_archive_uses_binary_architecture(self):
        result = self.run_script("package-release.sh", MOCK_ARCH="x86_64")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "dist/Clicker-1.0.0-macos-x86_64.zip").exists())


if __name__ == "__main__":
    unittest.main()
