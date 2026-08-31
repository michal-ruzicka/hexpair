#!/bin/sh
# check-large-file.sh - prove hexpair's writes on a file over 2 GiB
#
# Maintainer:  Michal Ruzicka <ruzicka.mich@gmail.com>
# URL:         https://github.com/michal-ruzicka/hexpair
# License:     Vim License - same terms as Vim itself (see LICENSE.md
#              or :help license); SPDX-License-Identifier: Vim
#
#     test/check-large-file.sh [SIZE_IN_GIB]      (default 3, minimum 3)
#
# POSIX sh, and on Windows it runs under Git Bash - the same way
# test/run-tests.sh does, and the same way CI runs that one there. Which
# means the same trap: Git Bash rewrites paths in the ARGUMENTS it hands a
# native program, but not inside a file that Vim opens itself, so every
# path written into a generated .vim script has to be in the drive-letter
# form first. Hence the cygpath conversions below.
#
# Needs SIZE_IN_GIB of free disk for the fixture, and the same again while
# the ':w {file}' check runs - so six free gigabytes at the default.
#
# The regression suite cannot do this. Every check in it that touches the
# code paths past 2 GiB either runs at a small offset - which exercises the
# same functions, and is worth something - or is skipped, because the one
# fixture that would settle it is a multi-gigabyte file nobody wants CI to
# build. So this is separate, run by hand, on a machine that can spare the
# disk.
#
# It matters most on native Windows, where past 2 GiB every byte that moves
# is moved by PowerShell rather than by xxd (see |hexpair-windows-2gib|):
# an overwrite seeks and writes, a grow extends with SetLength and slides
# the tail, a shrink slides the tail back and cuts the file. None of that
# can be exercised where the plugin is developed.
#
# What it does, and why in this order: it builds a file with a KNOWN byte at
# every offset - a repeating pattern, so any byte can be predicted from its
# position without storing a copy - then edits it past the 2 GiB mark and
# checks THREE things after each edit, because a write can go wrong in three
# different ways:
#
#   1. the bytes that were meant to change did;
#   2. the bytes on either side did NOT - a write at the wrong offset shows
#      up here and nowhere else;
#   3. the file's length is what the edit implied.
#
# A hash of the whole file would answer none of those three separately, and
# on a file this size would cost more than the test.
set -u

GIB=${1:-3}
# The whole point is the offsets past 2 GiB, which is where xxd stops being
# able to seek on Windows. A smaller file would run every check against the
# ORDINARY paths and report success without having tested anything this
# script exists for - a green run that means nothing is worse than none.
if [ "$GIB" -lt 3 ]; then
    echo "check-large-file.sh: needs at least 3 GiB - the point is the" >&2
    echo "  offsets past 2 GiB, and a smaller file never reaches them." >&2
    exit 1
fi
VIM=${HEXPAIR_VIM:-vim}
XXD=${HEXPAIR_XXD:-xxd}
cd "$(dirname "$0")" || exit 1
ROOT=$(cd .. && pwd)

PY=
for c in python3 python; do
    if command -v "$c" >/dev/null 2>&1 && "$c" -c 'import sys' >/dev/null 2>&1; then
        PY=$c
        break
    fi
done
[ -n "$PY" ] || { echo "no working python3 (or python) on PATH" >&2; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# BOTH of them: $WORK is written into the generated .vim scripts, and so is
# $ROOT by way of the `source` line. Converting only one is a bug that shows
# up on Windows alone, as a Vim that cannot find the plugin it was told to
# load - which is exactly what happened here before this line grew its
# second half.
if command -v cygpath >/dev/null 2>&1; then
    WORK=$(cygpath -m "$WORK")
    ROOT=$(cygpath -m "$ROOT")
fi
PLUGIN=$ROOT/plugin/hexpair.vim
# Said here rather than left to Vim: a failed :source in Ex mode abandons the
# rest of the -S script silently, and every check below then fails for a
# reason that has nothing to do with the plugin.
if [ ! -f "$PLUGIN" ]; then
    echo "check-large-file.sh: no plugin at $PLUGIN - run this from the" >&2
    echo "  test/ directory of a hexpair checkout." >&2
    exit 1
fi
BIG=$WORK/large.bin

FAIL=0
check() {
    if [ "$2" = "$3" ]; then
        echo "ok   - $1"
    else
        echo "FAIL - $1"
        echo "       expected: $2"
        echo "       actual:   $3"
        FAIL=1
    fi
}

# The pattern is one byte per offset and depends only on the offset, so the
# expected content of any range can be worked out rather than stored. 251 is
# prime and coprime with every power of two, so the pattern does not line up
# with page or block boundaries and an off-by-a-page error cannot land on
# bytes that happen to match.
expected_hex() {
    "$PY" -c "
import sys
off, n = int(sys.argv[1]), int(sys.argv[2])
sys.stdout.write(''.join('%02x' % ((off + i) % 251) for i in range(n)))
" "$1" "$2"
}

actual_hex() {
    "$XXD" -p -s "$1" -l "$2" "$BIG" | tr -d '\n\r'
}

file_size() {
    "$PY" -c "import os,sys; print(os.path.getsize(sys.argv[1]))" "$BIG"
}

# PREFLIGHT, before the disk goes anywhere. Every check below drives Vim
# the same way and reads bytes through the same helper, so if that does not
# work there is nothing to learn from building the fixture first - and
# finding out afterwards cost this project a working day on Windows.
"$PY" -c "
import sys
open(sys.argv[1], 'wb').write(bytes(range(256)))
" "$WORK/preflight.bin"
cat > "$WORK/preflight.vim" <<EOF
source $PLUGIN
try
  let g:hp = HexPairPagedSeekReadHexForTest('$WORK/preflight.bin', 0, 8)
  call writefile([g:hp ==# '0001020304050607' ? 'ok' : 'read came back as [' . g:hp . ']'], '$WORK/preflight.out')
catch
  call writefile(['THREW ' . v:exception], '$WORK/preflight.out')
endtry
qa!
EOF
"$VIM" -es -u NONE -S "$WORK/preflight.vim" < /dev/null
if [ "$(sed -n 1p "$WORK/preflight.out" 2>/dev/null)" != "ok" ]; then
    echo "check-large-file.sh: the preflight read FAILED, so nothing below" >&2
    echo "  would mean anything. No fixture was built." >&2
    echo "  $(sed -n 1p "$WORK/preflight.out" 2>/dev/null)" >&2
    exit 1
fi
echo "  preflight read ok, so the fixture is worth building"

echo "Building a ${GIB} GiB file with a known byte at every offset..."
"$PY" - "$BIG" "$GIB" <<'EOF'
import sys
path, gib = sys.argv[1], int(sys.argv[2])
total = gib * 1024**3
block = bytes(i % 251 for i in range(251 * 4096))
with open(path, 'wb') as f:
    written = 0
    while written < total:
        take = min(len(block), total - written)
        # The pattern is a function of absolute offset, so each block starts
        # where the last left off rather than at zero.
        start = written % 251
        f.write((block * 2)[start:start + take])
        written += take
EOF

SIZE=$(file_size)
echo "  $BIG is $SIZE bytes"

# Past 2 GiB, and far enough from either end that a grow and a shrink both
# have a real tail to move. Derived from the actual size rather than fixed,
# so a bigger fixture still edits somewhere sensible.
OFF=$(( 2147483647 + (SIZE - 2147483647) / 2 ))
# Aligned DOWN to a dump line, because the edits below rewrite the first
# byte columns of the line the cursor is on. Unaligned, the line would start
# up to fifteen bytes earlier and every expectation here would be off by
# that much - which is a bug in this script, not in the plugin, and cost one
# three-gigabyte run to find.
BYTES_PER_LINE=16
OFF=$(( OFF / BYTES_PER_LINE * BYTES_PER_LINE ))
PAGE_SIZE=$((128 * 1024))
BASE=$(( OFF / PAGE_SIZE * PAGE_SIZE ))
if [ "$OFF" -le 2147483647 ]; then
    echo "check-large-file.sh: $BIG is only $SIZE bytes - nothing to test" >&2
    exit 1
fi
echo "  editing at byte $OFF, whose page starts at $BASE"
echo "  (that is past the 2147483647 xxd can seek to on Windows)"

# Before anything is edited: the fixture really does hold the byte the
# pattern predicts, at the offset the edits will use. If this fails, every
# check below would be comparing against the wrong expectation and the run
# would be meaningless rather than red.
check "the fixture holds the predicted byte where the edits go" \
    "$(expected_hex $OFF 8)" "$(actual_hex $OFF 8)"

run_vim() {
    cat > "$WORK/edit.vim" <<EOF
source $PLUGIN
let g:hexpair_page_confirm = 0
try
  $1
  call writefile(['ok'], '$WORK/edit.out')
catch
  call writefile(['THREW ' . v:exception], '$WORK/edit.out')
endtry
qa!
EOF
    "$VIM" -es -u NONE -S "$WORK/edit.vim" < /dev/null
    sed -n 1p "$WORK/edit.out"
}

# --- 1. Same length: overwrite four bytes -----------------------------------
BEFORE=$(expected_hex $((OFF - 16)) 16)
AFTER=$(expected_hex $((OFF + 4)) 16)
check "a same-length write is accepted" "ok" \
    "$(run_vim "HexPairOpen $BIG
HexPairGoOffset $((OFF + 1))
call setline(line('.'), substitute(getline('.'), '^\\(\\x\\+: \\)\\x\\x \\x\\x \\x\\x \\x\\x', '\\1de ad be ef', ''))
write")"
check "  the four bytes are what was typed" "deadbeef" "$(actual_hex $OFF 4)"
check "  the 16 bytes before are untouched" "$BEFORE" "$(actual_hex $((OFF - 16)) 16)"
check "  the 16 bytes after are untouched"  "$AFTER"  "$(actual_hex $((OFF + 4)) 16)"
check "  the length is unchanged" "$SIZE" "$(file_size)"

# --- 2. Grow: insert two bytes ----------------------------------------------
# Everything after the insertion point moves right by two, so the bytes that
# were at OFF+4 are now at OFF+6 - which is the assertion that a tail slide
# actually slid, rather than the file merely being longer.
TAIL_BEFORE=$(actual_hex $((OFF + 4)) 32)
FAR_BEFORE=$(actual_hex $((SIZE - 32)) 32)
check "a growing write is accepted" "ok" \
    "$(run_vim "HexPairOpen $BIG
HexPairGoOffset $((OFF + 1))
call setline(line('.'), substitute(getline('.'), '^\\(\\x\\+: \\)', '\\1ca fe ', ''))
write")"
check "  the file grew by two bytes" "$((SIZE + 2))" "$(file_size)"
check "  the inserted bytes are at the cursor" "cafe" "$(actual_hex $OFF 2)"
check "  what followed moved along, intact" "$TAIL_BEFORE" \
    "$(actual_hex $((OFF + 6)) 32)"
check "  and the far end of the file moved too" "$FAR_BEFORE" \
    "$(actual_hex $((SIZE + 2 - 32)) 32)"

# --- 3. Shrink: delete those two bytes again --------------------------------
# The one no other platform can do in place. After it the file must be back
# to its original length AND its far end back where it started.
check "a shrinking write is accepted" "ok" \
    "$(run_vim "HexPairOpen $BIG
HexPairGoOffset $((OFF + 1))
call setline(line('.'), substitute(getline('.'), '^\\(\\x\\+: \\)\\x\\x \\x\\x ', '\\1', ''))
write")"
check "  the file is back to its original length" "$SIZE" "$(file_size)"
check "  what followed is back where it was" "$TAIL_BEFORE" \
    "$(actual_hex $((OFF + 4)) 32)"
check "  and so is the far end" "$FAR_BEFORE" "$(actual_hex $((SIZE - 32)) 32)"
# The head of the file is the part no edit should ever have touched, and the
# part a mis-seeked write is most likely to have landed in.
check "  the start of the file was never touched (asked of xxd)" "$(expected_hex 0 32)" \
    "$(actual_hex 0 32)"

# --- 4. ':w {file}' writes the whole thing ----------------------------------
COPY=$WORK/copy.bin
check "':w {file}' is accepted" "ok" \
    "$(run_vim "HexPairOpen $BIG
HexPairGoOffset $((OFF + 1))
write $COPY")"
if [ -f "$COPY" ]; then
    check "  the copy is the same length" "$SIZE" \
        "$("$PY" -c "import os,sys; print(os.path.getsize(sys.argv[1]))" "$COPY")"
    check "  and matches at a large offset" \
        "$(expected_hex 2400000000 16)" \
        "$("$XXD" -p -s 2400000000 -l 16 "$COPY" | tr -d '\n\r')"
else
    check "  the copy exists" "yes" "no"
fi

echo
if [ "$FAIL" -eq 0 ]; then
    echo "All large-file checks passed."
else
    echo "Some large-file checks FAILED."
fi
exit "$FAIL"
