#!/usr/bin/env python3
"""Portable contract-test stand-ins, not evidence that real macOS packaging ran.

ZIP bytes, executable attributes, symlinks, plists and checksums are real. The
fake DMG is deliberately a ZIP container so these contracts also run on Linux;
macOS CI separately verifies and mounts the actual hdiutil-produced disk image.
"""
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import sys
import zipfile


def archive(source, destination, keep_parent):
    source = Path(source)
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as output:
        for path in sorted(source.rglob("*")):
            relative = path.relative_to(source.parent if keep_parent else source)
            if path.is_symlink():
                info = zipfile.ZipInfo(str(relative))
                info.create_system = 3
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
                output.writestr(info, os.readlink(path))
            elif path.is_file():
                output.write(path, str(relative))


def extract(source, destination):
    destination = Path(destination)
    with zipfile.ZipFile(source) as bundle:
        for info in bundle.infolist():
            output = destination / info.filename
            output.parent.mkdir(parents=True, exist_ok=True)
            mode = info.external_attr >> 16
            if stat.S_ISLNK(mode):
                output.symlink_to(bundle.read(info).decode())
            else:
                output.write_bytes(bundle.read(info))
                if mode:
                    output.chmod(stat.S_IMODE(mode))


name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["MOCK_LOG"], "a") as log:
    log.write(f"{name} {' '.join(args)}\n")
if name == "ditto":
    if "-c" in args:
        archive(args[-2], args[-1], keep_parent=True)
    elif "-x" in args:
        extract(args[-2], args[-1])
    else:
        shutil.copytree(args[0], args[1], symlinks=True, dirs_exist_ok=True)
elif name == "plutil":
    plistlib.loads(Path(args[-1]).read_bytes())
elif name == "hdiutil":
    if args[0] == "create":
        archive(args[args.index("-srcfolder") + 1], args[-1], keep_parent=False)
    elif args[0] == "verify":
        with zipfile.ZipFile(args[-1]) as bundle:
            assert bundle.testzip() is None
    elif args[0] == "attach":
        extract(args[-1], args[args.index("-mountpoint") + 1])
    elif args[0] != "detach":
        raise AssertionError(f"Unexpected hdiutil command: {args}")
elif name == "launch-smoke":
    assert len(args) == 2
    environment = {**os.environ, "CLICKER_SMOKE_TEST": "1", "CLICKER_SMOKE_REPORT": args[1]}
    sys.exit(subprocess.call([str(Path(args[0]) / "Contents/MacOS/Clicker")], env=environment))
else:
    raise AssertionError(f"Unexpected tool: {name}")
