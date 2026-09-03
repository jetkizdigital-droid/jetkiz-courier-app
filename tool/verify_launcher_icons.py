#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

EXPECTED = {
    "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": (48, "27b485d85e1168c66b9e1ae73053baee75f536c52e31d822607671cd4a58a54e"),
    "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": (72, "ee7f55f2881d9d472a7bad8a087051f169cdce529e37c8417ad21c17a8adb1dc"),
    "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": (96, "756b0b7eb90cf4c77236d33801db4769ed432c867d4f7aaa5b1efe4826a65312"),
    "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": (144, "74aae659c99971fb68e25b9db2c91ee8290cf7a5d9eb76c0604fd2a6631dc540"),
    "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": (192, "fd986705af31a7a254817f7862050b5cb749f3dcf960b95b9b0dab0456455521"),
    "android/app/src/main/res/mipmap-mdpi/ic_launcher_round.png": (48, "058c02e92cae780ba76051d5cd7457c6377c4719ca8317e11d0532ab5089e0f8"),
    "android/app/src/main/res/mipmap-hdpi/ic_launcher_round.png": (72, "1ac10827adc5f3c79027a6b5f862b6191f6c894d91efc191844ce2b1d71f5a77"),
    "android/app/src/main/res/mipmap-xhdpi/ic_launcher_round.png": (96, "12e927189ed1bfe369a85b312df0ba9ef158dc68009e1c238c54003ea709a48f"),
    "android/app/src/main/res/mipmap-xxhdpi/ic_launcher_round.png": (144, "2287209ef49d47bde2e898e5afefe0e5156a91e19e309d1b820c93cf28e1cdad"),
    "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png": (192, "56a4d47ac3b9094781d55deab76816fc5db000dc265c64b35e1ccdf132975423"),
    "android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png": (432, "c34d2db62d16ad8e6f568d793469a4be2c81e86be01b92897311510e4384b433"),
}


def png_dimensions(data: bytes) -> tuple[int, int]:
    if not data.startswith(b"\x89PNG\r\n\x1a\n") or data[12:16] != b"IHDR":
        raise AssertionError("not a PNG with IHDR")
    return struct.unpack(">II", data[16:24])


for relative, (expected_size, expected_sha) in EXPECTED.items():
    path = ROOT / relative
    if not path.is_file():
        raise SystemExit(f"Missing launcher resource: {relative}")
    data = path.read_bytes()
    width, height = png_dimensions(data)
    if (width, height) != (expected_size, expected_size):
        raise SystemExit(
            f"Wrong launcher size for {relative}: {width}x{height}, expected {expected_size}x{expected_size}"
        )
    actual_sha = hashlib.sha256(data).hexdigest()
    if actual_sha != expected_sha:
        raise SystemExit(
            f"Unexpected launcher content for {relative}; branded JETKIZ resource changed"
        )

manifest = (ROOT / "android/app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
for required in (
    'android:label="JETKIZ Курьер"',
    'android:icon="@mipmap/ic_launcher"',
    'android:roundIcon="@mipmap/ic_launcher_round"',
):
    if required not in manifest:
        raise SystemExit(f"Manifest launcher contract missing: {required}")

for name in ("ic_launcher.xml", "ic_launcher_round.xml"):
    xml = (ROOT / "android/app/src/main/res/mipmap-anydpi-v26" / name).read_text(
        encoding="utf-8"
    )
    if '@color/launcher_icon_background' not in xml:
        raise SystemExit(f"Adaptive icon background missing in {name}")
    if '@drawable/ic_launcher_foreground' not in xml:
        raise SystemExit(f"Adaptive icon foreground missing in {name}")

colors = (ROOT / "android/app/src/main/res/values/colors.xml").read_text(encoding="utf-8")
if "#4EAD35" not in colors.upper():
    raise SystemExit("JETKIZ launcher brand green is missing")

build_gradle = (ROOT / "android/app/build.gradle.kts").read_text(encoding="utf-8")
if 'applicationId = "asia.jetkiz.courier"' not in build_gradle:
    raise SystemExit("Courier package id changed unexpectedly")

pubspec = (ROOT / "pubspec.yaml").read_text(encoding="utf-8")
match = re.search(r"(?m)^version:\s*[^+\s]+\+(\d+)\s*$", pubspec)
if not match or int(match.group(1)) < 2:
    raise SystemExit("Courier versionCode must be at least 2 after the Play rejection")

print("JETKIZ courier launcher source verification passed")
