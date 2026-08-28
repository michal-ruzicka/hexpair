#!/bin/sh
# hexpair - record docs/hexpair-demo.gif, the animation at the top of README.md
#
# Maintainer:  Michal Růžička <ruzicka.mich@gmail.com>
# URL:         https://github.com/michal-ruzicka/hexpair
# License:     Vim License - same terms as Vim itself (see LICENSE.md
#              or :help license); SPDX-License-Identifier: Vim
#
# Usage:  docs/hexpair-demo.sh [OUTPUT.gif]
#
# Needs vhs (https://github.com/charmbracelet/vhs), ffmpeg, vim, curl and a
# network connection: the tape downloads the v2.1.0 release tarball and edits
# that, so what is on the screen is a file anybody can fetch and follow along in.
# Linux only, deliberately - vhs is.
#
# The recording goes to MP4 and ffmpeg makes the GIF from it. vhs's own GIF
# writer builds the whole file in memory and is OOM-killed on a recording this
# long, leaving a zero-byte file and no error; the two-pass palette conversion
# below streams and does not care how long the tape is.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
out=${1:-$here/hexpair-demo.gif}
fps=${HEXPAIR_DEMO_FPS:-8}
colors=${HEXPAIR_DEMO_COLORS:-24}

for tool in vhs ffmpeg vim curl; do
    command -v "$tool" >/dev/null 2>&1 ||
        { echo "hexpair-demo: $tool is not on PATH" >&2; exit 1; }
done

# Under $HOME rather than in /tmp, which is a tmpfs on most systems: vhs writes
# two full-size PNGs per captured frame and this tape is minutes of them.
# TMPDIR points here too, since that is where vhs puts them - and where the
# headless browser it renders with puts its control socket, which is why the
# name is short. A unix socket path may be about 104 characters; vhs adds some
# fifty of its own, and a work directory a few levels down a project tree is
# already over the line ("Socket path too long", and nothing recorded).
work=$(mktemp -d "${HEXPAIR_DEMO_TMP:-$HOME}/hpdemo.XXXXXX")
trap 'rm -rf "$work"' EXIT INT TERM
TMPDIR=$work
export TMPDIR

# The `vim` the tape gets: this repository's plugin and a configuration that is
# about the recording rather than about whoever is recording it.
# --cmd, not a line in the vimrc: Vim asks the terminal for its background
# colour during startup, and by the time a vimrc is read the question has been
# sent. The answer then arrives seconds later - after Vim has exited - and the
# shell at the prompt echoes it as a line of escape rubbish in the middle of
# the recording. Nothing here wants the answer; 'background' is set by hand.
printf '#!/bin/sh\nexec vim --cmd %s -u %s/hexpair-demo.vimrc "$@"\n' \
    "'set t_RB= t_RF='" "$here" > "$work/vim"
chmod +x "$work/vim"
HEXPAIR_DEMO_VIM="$work/vim"
HEXPAIR_DEMO_BASHRC="$here/../hexpair.bashrc"
export HEXPAIR_DEMO_VIM HEXPAIR_DEMO_BASHRC

( cd "$work" && vhs "$here/hexpair-demo.tape" )
[ -s "$work/hexpair-demo.mp4" ] || { echo "hexpair-demo: vhs produced nothing" >&2; exit 1; }

# Two passes, because one shared palette for the whole recording is what keeps
# a terminal's few colours looking like themselves.
#
# No dithering, and few colours: a terminal has a dozen or so to begin with, so
# dithering invents noise that nothing can compress and the palette is nearly
# empty even at 24 - a terminal theme, a handful of highlight groups, and the
# anti-aliasing of one font at one size.
#
# Both knobs matter, and how much depends on the recording, which is worth
# knowing before turning either. Measured on the seven-minute tape in this
# directory:
#
#            fps=6   fps=8   fps=10
#   16 col   4.8M    5.4M    6.0M
#   24 col   5.2M    6.1M    6.6M
#   32 col   5.7M      -     7.5M
#
# A short recording is mostly a still screen and the frame rate then costs
# almost nothing - three per cent between 10 and 15 on the two-minute version
# of this tape, which is where the defaults used to come from. This one moves
# most of the time, and the frame rate is worth as much as the palette. 24 and
# 8 are a fifth off the file against 32 and 10 with nothing visible to show for
# it on a terminal recording; 16 colours costs nothing visible either, and is
# there if a future tape grows again.
# HEXPAIR_DEMO_FPS and HEXPAIR_DEMO_COLORS are the knobs.
ffmpeg -v warning -y -i "$work/hexpair-demo.mp4" \
    -vf "fps=$fps,palettegen=stats_mode=diff:max_colors=$colors" \
    -update 1 -frames:v 1 "$work/palette.png"
ffmpeg -v warning -y -i "$work/hexpair-demo.mp4" -i "$work/palette.png" \
    -filter_complex "fps=$fps[v];[v][1:v]paletteuse=dither=none:diff_mode=rectangle" \
    -loop 0 "$work/hexpair-demo.gif"

mv -- "$work/hexpair-demo.gif" "$out"
# The MP4 is kept beside it, and gitignored: only one of the two belongs in a
# repository, and the one README.md points at is the GIF. This one is a tenth
# of the size and a better thing to link from a blog post - and it is what a
# different GIF can be made from (another frame rate, another palette) without
# recording anything again.
mv -- "$work/hexpair-demo.mp4" "${out%.gif}.mp4"
ls -l -- "$out" "${out%.gif}.mp4"
