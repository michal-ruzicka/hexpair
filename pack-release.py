#!/usr/bin/env python3
"""Reproducible release packaging for the hexpair Vim plugin.

The single packaging implementation for every platform: the
pack-release (POSIX) and pack-release.cmd (Windows) wrappers both run
this script, so the released tarball is byte-identical wherever it is
produced -- by construction, not by aligning different system tar
toolchains (whose ustar writers genuinely differ).

Reads Version: and Date: from the header of plugin/hexpair.vim (the
single source of truth) and produces dist/hexpair.v<version>.tar --
an uncompressed tarball that extracts into a hexpair/ directory ready
for ~/.vim/pack/plugins/start/.

Normalized sources of non-determinism (see CONTRIBUTING.md,
"Reproducible Builds"):
  - entry mtimes    -> <Date:> 00:00:00 UTC
  - entry order     -> explicit fixed sorted file list below
  - owner/mode      -> uid/gid 0, no names, mode 0644
  - tar format      -> ustar, standard 10 KiB record padding
  - compression     -> none, deliberately: compressed deflate streams
                       are not stable across compressor builds
                       (classic zlib vs zlib-ng), and the archive is
                       small; integrity and authenticity of published
                       artifacts are covered by their GPG signature

Python 3.8+, standard library only.
"""

import datetime
import hashlib
import io
import re
import sys
import tarfile
from pathlib import Path

# Fixed, sorted entry order; paths inside the archive. Each entry's
# source file is the repo-relative path without the leading "hexpair/".
FILES = [
    "hexpair/CHANGELOG.md",
    "hexpair/CLAUDE.md",
    "hexpair/CONTRIBUTING.md",
    "hexpair/LICENSE.md",
    "hexpair/NOTICE.md",
    "hexpair/README.md",
    "hexpair/doc/hexpair.txt",
    "hexpair/ftplugin/xxd.vim",
    "hexpair/gvimhex.cmd",
    "hexpair/gvimhexdiff.cmd",
    "hexpair/hexpair.bashrc",
    "hexpair/hexpair.vimrc",
    "hexpair/icons/hexpair-open.ico",
    "hexpair/icons/hexpair-pick.ico",
    "hexpair/icons/hexpair-with.ico",
    "hexpair/plugin/hexpair.vim",
    "hexpair/vimhex-contex-entry.add.reg",
    "hexpair/vimhex-contex-entry.remove.reg",
    "hexpair/vimhex.cmd",
    "hexpair/vimhexdiff.cmd",
]


def parse_header(plugin: Path):
    text = plugin.read_text(encoding="utf-8")
    version = re.search(r'^" Version:\s+(\S+)', text, re.MULTILINE)
    date = re.search(r'^" Date:\s+(\d{4}-\d{2}-\d{2})', text, re.MULTILINE)
    if not version or not date:
        sys.exit("pack-release: could not parse Version:/Date: from %s" % plugin)
    return version.group(1), date.group(1)


def build_tar(root: Path, mtime: int) -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        for name in FILES:
            data = (root / name[len("hexpair/"):]).read_bytes()
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mtime = mtime
            info.mode = 0o644
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            tar.addfile(info, io.BytesIO(data))
    return buf.getvalue()


def main():
    root = Path(__file__).resolve().parent
    version, date = parse_header(root / "plugin" / "hexpair.vim")
    mtime = int(
        datetime.datetime.strptime(date, "%Y-%m-%d")
        .replace(tzinfo=datetime.timezone.utc)
        .timestamp()
    )

    tarball = build_tar(root, mtime)

    out = root / "dist" / ("hexpair.v%s.tar" % version)
    out.parent.mkdir(exist_ok=True)
    out.write_bytes(tarball)

    print("%s  %s" % (hashlib.sha256(tarball).hexdigest(), out))
    print("pack-release: packaged version %s (dated %s)" % (version, date))


if __name__ == "__main__":
    main()
