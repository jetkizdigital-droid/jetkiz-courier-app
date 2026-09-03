#!/usr/bin/env python3
from __future__ import annotations

import sys
import zipfile
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: verify_release_launcher_archive.py <apk-or-aab>")

archive = Path(sys.argv[1])
if not archive.is_file():
    raise SystemExit(f"Release archive not found: {archive}")

with zipfile.ZipFile(archive) as zf:
    names = zf.namelist()

launcher = [name for name in names if "ic_launcher" in name]
if not launcher:
    raise SystemExit(f"No launcher resources found in {archive}")

required_suffixes = (
    "/ic_launcher.png",
    "/ic_launcher_round.png",
    "/ic_launcher_foreground.png",
    "/ic_launcher.xml",
    "/ic_launcher_round.xml",
)
for suffix in required_suffixes:
    if not any(name.endswith(suffix) for name in launcher):
        raise SystemExit(f"Compiled release is missing launcher resource {suffix}: {archive}")

legacy = [name for name in launcher if name.endswith("/ic_launcher.png")]
round_legacy = [name for name in launcher if name.endswith("/ic_launcher_round.png")]
if len(legacy) < 5 or len(round_legacy) < 5:
    raise SystemExit(
        f"Compiled release does not contain all launcher density buckets: legacy={len(legacy)}, round={len(round_legacy)}"
    )

print(f"Release launcher archive verification passed: {archive}")
print("Launcher entries:")
for name in sorted(launcher):
    print(f"  {name}")
