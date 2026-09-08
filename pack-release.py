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

import bz2
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
    "hexpair/autoload/hexpair.vim",
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


# What the MINIMAL package leaves out: the files that are not the plugin
# and are a click away on GitHub anyway. Two of them are written for
# somebody working ON hexpair rather than with it; the third is the
# changelog, which is not redundant in general but IS on vim.org, where
# every version carries its own release notes in a field of its own.
#
# It exists because vim.org refuses a POST body somewhere between 224 and
# 250 KiB, measured: the limit is documented nowhere and arrives as a bare
# 413 from the web server, or as an internal error just under it. The
# uncompressed release tarball is 900 KiB. Should a future upload be
# refused anyway, this is the ladder, all bzip2 -9 and measured on
# v2.4.0-devel:
#
#     nothing omitted                     223 373
#     CLAUDE.md                           185 421
#     + CONTRIBUTING.md                   174 949
#     + CHANGELOG.md                      161 339   <- what this list does
#
# Adding a name here is the whole change; the suite holds the list to
# being a subset of FILES, so a typo cannot silently omit nothing.
MINIMAL_OMITS = [
    "hexpair/CHANGELOG.md",
    "hexpair/CLAUDE.md",
    "hexpair/CONTRIBUTING.md",
]


def parse_header(plugin: Path):
    text = plugin.read_text(encoding="utf-8")
    version = re.search(r'^" Version:\s+(\S+)', text, re.MULTILINE)
    date = re.search(r'^" Date:\s+(\d{4}-\d{2}-\d{2})', text, re.MULTILINE)
    if not version or not date:
        sys.exit("pack-release: could not parse Version:/Date: from %s" % plugin)
    return version.group(1), date.group(1)


def build_tar(root: Path, mtime: int, files=None) -> bytes:
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        for name in files if files is not None else FILES:
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

    # The minimal package: a release artifact in its own right, and the
    # one vim.org will take. Compressed, because that site will not take
    # the plain tarball at any file list this project would ship.
    #
    # bzip2, and measured rather than assumed. On this content, which is
    # one very large and very repetitive text file plus some smaller ones:
    #
    #     bzip2 -9                 185 421     <- this
    #     xz -9e                   188 816     (= 7-Zip's "ultra", LZMA2)
    #     gzip -9                  246 475
    #     7-Zip PPMd, order 32     160 048
    #
    # PPMd wins by 14%, and is not used. A .7z needs 7-Zip or p7zip to
    # open - not on a stock Linux, not on macOS, not on Windows before 11
    # - and 185 KiB already uploads, so the only thing that saving could
    # buy is a package some readers cannot unpack. tar and bzip2 are
    # everywhere Vim is. Note also that 7-Zip's "ultra" preset is LZMA2,
    # which LOSES here: the win is PPMd specifically, and only if asked
    # for by name.
    #
    # It does NOT end in ".tar", and that is load-bearing: CI matches the
    # canonical tarball with `dist/*.tar`, which wants exactly one file.
    #
    # Its bytes are compared across platforms too, and that is a claim
    # worth stating carefully.
    #
    # GZIP WOULD NOT DO, and not only for the reason CONTRIBUTING.md gives
    # about deflate streams differing between compressor builds (zlib-ng
    # is a real and widely shipped drop-in). The gzip HEADER carries the
    # source file's mtime and its name: compress the same bytes from a
    # file checked out at a different time and the output differs, which
    # is exactly what a second CI runner does. `gzip -n` drops both, and
    # then there is still zlib-ng.
    #
    # A bzip2 stream has nowhere to put either. Its header is "BZh" plus
    # one digit of block size, and then blocks - no time, no name, no
    # flags. And there is no second implementation in the library path:
    # libbzip2 1.0.x has been algorithmically still for a very long time,
    # and the bytes this module produces here are the same bytes the
    # standalone bzip2(1) binary produces from the same input.
    #
    # So this is EXPECTED to be reproducible - and expectation is not
    # proof, which is why CI compares it across Linux and Windows rather
    # than trusting it. If a platform ever diverges, that check says so.
    reduced = [f for f in FILES if f not in MINIMAL_OMITS]
    inner = build_tar(root, mtime, reduced)
    small = root / "dist" / ("hexpair.v%s.minimal.tar.bz2" % version)
    small.write_bytes(bz2.compress(inner, 9))

    print("%s  %s" % (hashlib.sha256(small.read_bytes()).hexdigest(), small))
    print("%s  (its uncompressed tar, %d bytes)"
          % (hashlib.sha256(inner).hexdigest(), len(inner)))
    print("pack-release: packaged version %s (dated %s)" % (version, date))


if __name__ == "__main__":
    main()
