#!/usr/bin/env python3
"""Render icons/*.ico from design.py - the three Explorer context-menu
icons vimhex-contex-entry.add.reg points its "Icon" values at.

    python3 icons/build.py

Deterministic (no timestamps, no randomness), so re-running it after an
unrelated change produces byte-identical .ico files - a real code review,
not noise, is what a diff here means. Only the .ico output ships in the
release tarball (pack-release.py's FILES); this script and rasticon.py/
design.py stay development-only, same treatment pack-release.py itself
gets from the thing it packages.
"""

from pathlib import Path

from design import ICONS
from rasticon import ico_encode, render_png

SIZES = [16, 24, 32, 48, 256]


def main():
    out_dir = Path(__file__).resolve().parent
    for name, spec in ICONS.items():
        images = [(size, render_png(spec, size)) for size in SIZES]
        data = ico_encode(images)
        path = out_dir / f"{name}.ico"
        path.write_bytes(data)
        print(f"{path.name}: {len(data)} bytes, sizes {SIZES}")


if __name__ == "__main__":
    main()
