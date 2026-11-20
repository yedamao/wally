#!/usr/bin/env python3
"""Render AppIcon.svg into AppIcon.icns (and a 1024 master PNG).

Runs on Linux CI or macOS. Needs rsvg-convert (librsvg2-bin) and Pillow.
"""
from __future__ import annotations

import struct
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SVG = ROOT / "macos/Wally/Sources/Wally/Resources/AppIcon.svg"
OUT_DIR = ROOT / "macos/Wally/Sources/Wally/Resources"
ICNS = OUT_DIR / "AppIcon.icns"
PNG_MASTER = OUT_DIR / "AppIcon.png"

# (icns OSType, pixel size) — PNG payloads for modern macOS.
ICNS_ENTRIES: list[tuple[bytes, int]] = [
    (b"icp4", 16),
    (b"icp5", 32),
    (b"icp6", 48),
    (b"ic07", 128),
    (b"ic08", 256),
    (b"ic09", 512),
    (b"ic10", 1024),
    (b"ic11", 32),   # 16@2x
    (b"ic12", 64),   # 32@2x
    (b"ic13", 256),  # 128@2x
    (b"ic14", 512),  # 256@2x
]


def render_svg(size: int, dest: Path) -> None:
    subprocess.run(
        ["rsvg-convert", "-w", str(size), "-h", str(size), str(SVG), "-o", str(dest)],
        check=True,
    )


def png_bytes(img: Image.Image, size: int) -> bytes:
    resized = img.resize((size, size), Image.Resampling.LANCZOS)
    buf = tempfile.SpooledTemporaryFile()
    resized.save(buf, format="PNG")
    buf.seek(0)
    return buf.read()


def write_icns(master: Image.Image, path: Path) -> None:
    chunks: list[bytes] = []
    for ostype, size in ICNS_ENTRIES:
        data = png_bytes(master, size)
        chunks.append(ostype + struct.pack(">I", 8 + len(data)) + data)
    body = b"".join(chunks)
    path.write_bytes(b"icns" + struct.pack(">I", 8 + len(body)) + body)


def main() -> int:
    if not SVG.is_file():
        print(f"missing {SVG}", file=sys.stderr)
        return 1
    with tempfile.TemporaryDirectory() as tmp:
        master_path = Path(tmp) / "master.png"
        render_svg(1024, master_path)
        master = Image.open(master_path).convert("RGBA")
        master.save(PNG_MASTER, format="PNG")
        write_icns(master, ICNS)
    print(f"wrote {ICNS.relative_to(ROOT)} ({ICNS.stat().st_size} bytes)")
    print(f"wrote {PNG_MASTER.relative_to(ROOT)} ({PNG_MASTER.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
