"""Packaging contract tests; fake compiler/signing tools, real plist/ZIP/checksums."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import stat
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
        if [[ "$1" == scripts/launch-smoke-app.swift ]]; then
            exec "$(dirname "$0")/launch-smoke" "$2" "$3"
        fi
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
        portable_tools = self.tools / "fake-macos-tools.py"
        shutil.copyfile(ROOT / "Tests/Packaging/fake_macos_tools.py", portable_tools)
        portable_tools.chmod(0o755)
        for name in ("ditto", "plutil", "hdiutil", "launch-smoke"):
            (self.tools / name).symlink_to(portable_tools.name)

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
            executable = bundle.getinfo("Clicker.app/Contents/MacOS/Clicker")
            self.assertTrue(executable.external_attr >> 16 & stat.S_IXUSR)
            provenance = json.loads(bundle.read("Clicker.app/Contents/Resources/build-info.json"))
            self.assertEqual(provenance["sourceCommit"], "unknown")
            self.assertEqual(info["ClickerSourceCommit"], provenance["sourceCommit"])
            self.assertEqual(provenance["architecture"], "arm64")
            self.assertEqual(provenance["signing"], "ad-hoc")
            self.assertFalse(provenance["notarized"])
        checksum = Path(f"{archive}.sha256").read_text().strip()
        self.assertEqual(checksum, f"{hashlib.sha256(archive.read_bytes()).hexdigest()}  {archive.name}")
        self.assertIn("codesign --verify --deep --strict", self.log.read_text())

    def test_dmg_contains_same_app_applications_link_and_honest_install_note(self):
        result = self.run_script("package-release.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        dmg = self.root / "dist/Clicker-1.0.0-macos-arm64.dmg"
        # The test double is a ZIP, not a claimed real disk image. Real mount and
        # launch verification is mandatory in the macOS Actions workflow.
        with zipfile.ZipFile(dmg) as bundle:
            self.assertEqual(bundle.read("Applications"), b"/Applications")
            self.assertTrue(stat.S_ISLNK(bundle.getinfo("Applications").external_attr >> 16))
            self.assertIn("公证", bundle.read("安装说明.txt").decode())
            self.assertEqual(
                bundle.read("Clicker.app/Contents/MacOS/Clicker"),
                (self.binary_directory / "Clicker").read_bytes(),
            )
        for suffix in ("dmg", "build-info.json"):
            path = self.root / f"dist/Clicker-1.0.0-macos-arm64.{suffix}"
            checksum = Path(f"{path}.sha256").read_text().strip()
            self.assertEqual(checksum, f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}")
        self.assertIn("hdiutil verify", self.log.read_text())

    def test_source_provenance_matches_exact_checkout_and_marks_tracked_changes(self):
        def git(*arguments):
            return subprocess.check_output(["git", *arguments], cwd=self.root, text=True).strip()
        git("init", "-q")
        git("config", "user.name", "Packaging Test")
        git("config", "user.email", "packaging@example.invalid")
        git("add", "scripts", "Resources")
        git("commit", "-qm", "Fixture sources")
        commit = git("rev-parse", "HEAD")
        for dirty in (False, True):
            with self.subTest(dirty=dirty):
                if dirty:
                    with (self.root / "scripts/build-app.sh").open("a") as source:
                        source.write("\n# local modification\n")
                result = self.run_script("build-app.sh")
                self.assertEqual(result.returncode, 0, result.stderr)
                provenance = json.loads((self.root / "dist/Clicker.app/Contents/Resources/build-info.json").read_text())
                self.assertEqual(provenance["sourceCommit"], commit)
                self.assertEqual(provenance["sourceDirty"], str(dirty).lower())
        git("checkout", "--", "scripts/build-app.sh")
        (self.root / "Sources").mkdir()
        (self.root / "Sources/untracked.swift").write_text("// not in the claimed commit\n")
        result = self.run_script("build-app.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        provenance = json.loads((self.root / "dist/Clicker.app/Contents/Resources/build-info.json").read_text())
        self.assertEqual(provenance["sourceDirty"], "true")

    def test_smoke_script_installs_and_launches_each_format_in_safe_mode(self):
        # A process-level fake app tests argument forwarding, report validation,
        # ZIP executable bits, DMG installation, and the shell's success contract.
        (self.binary_directory / "Clicker").write_text('''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import plistlib
import sys
assert len(sys.argv) == 1
assert os.environ["CLICKER_SMOKE_TEST"] == "1"
app = Path(__file__).resolve().parents[2]
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
report = Path(os.environ["CLICKER_SMOKE_REPORT"])
report.write_text(json.dumps({"status": "passed", "safeMode": True,
    "globalInputServicesStarted": False, "mainViewAppeared": True,
    "arguments": sys.argv, "openFileRequest": [],
    "bundleIdentifier": info["CFBundleIdentifier"], "bundlePath": str(app),
    "sourceCommit": info["ClickerSourceCommit"], "windowTitle": "Clicker",
    "contentWidth": 760, "contentHeight": 480}))
''')
        result = self.run_script("package-release.sh")
        self.assertEqual(result.returncode, 0, result.stderr)
        result = self.run_script("smoke-test-package.sh", CLICKER_EXPECTED_ARCH="arm64")
        self.assertEqual(result.returncode, 0, result.stderr)
        for format in ("zip", "dmg"):
            report = json.loads((self.root / f"dist/smoke-evidence/{format}-launch.json").read_text())
            self.assertTrue(report["safeMode"])
            self.assertIn(f"{format}-install", report["bundlePath"])
        self.assertIn("hdiutil attach -nobrowse -readonly", self.log.read_text())
        self.assertEqual(self.log.read_text().count("swift scripts/launch-smoke-app.swift"), 2)

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
        self.assertTrue((self.root / "dist/Clicker-1.0.0-macos-x86_64.dmg").exists())

    def test_unsupported_architecture_fails_instead_of_mislabelling_installer(self):
        result = self.run_script("package-release.sh", MOCK_ARCH="arm64 x86_64")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsupported release architecture", result.stderr)
        self.assertFalse(list((self.root / "dist").glob("*.dmg")))


if __name__ == "__main__":
    unittest.main()
