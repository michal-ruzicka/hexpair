#!/bin/sh
# ===========================================================================
# Headless regression suite for the hexpair Vim plugin.
#
# Runs Vim in silent Ex mode (vim -es -u NONE) against generated binary
# fixtures and asserts byte-exact behaviour. Requires: vim (with xxd),
# python3 (fixture generation only — dash's printf does not expand \x
# escapes, so binary fixtures must not be generated with printf).
#
# Exit status: 0 when all tests pass, 1 otherwise.
# ===========================================================================
set -u

cd "$(dirname "$0")"
PLUGIN=../plugin/hexpair.vim
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
FAIL=0

check() { # name expected actual
    if [ "$2" = "$3" ]; then
        echo "ok   - $1"
    else
        echo "FAIL - $1"
        echo "       expected: $2"
        echo "       actual:   $3"
        FAIL=1
    fi
}

# --- Fixtures --------------------------------------------------------------
python3 - "$WORK" <<'EOF'
import sys, os
w = sys.argv[1]
# 100 uniform text lines -> 2900 bytes; known byte at offset 1422
with open(os.path.join(w, 'pos.bin'), 'wb') as f:
    for i in range(100):
        f.write(b'line %03d with some text here\n' % i)
# trailing-newline fixture
open(os.path.join(w, 'eol.bin'), 'wb').write(b'AB\n')
# insertion-write fixture
open(os.path.join(w, 'ins.bin'), 'wb').write(b'ABCDEFGH')
EOF

# --- Test 1: round trip preserves content and cursor byte offset -----------
cat > "$WORK/t1.vim" <<EOF
source $PLUGIN
execute 'goto 1423'
HexPairToggle
let dump = [line('.'), col('.'), strpart(getline('.'), col('.') - 1, 2)]
HexPairToggle
let off = line2byte(line('.')) + col('.') - 2
call writefile([string(dump), string(off)], '$WORK/t1.out')
qa!
EOF
vim -es -b -u NONE "$WORK/pos.bin" -S "$WORK/t1.vim"
check "round-trip dump position"  "[89, 53, '69']" "$(sed -n 1p "$WORK/t1.out")"
check "round-trip cursor offset"  "1422"           "$(sed -n 2p "$WORK/t1.out")"

# --- Test 2: final newline byte is visible in the dump ---------------------
cat > "$WORK/t2.vim" <<EOF
source $PLUGIN
HexPairToggle
call writefile([getline(1)], '$WORK/t2.out')
qa!
EOF
vim -es -b -u NONE "$WORK/eol.bin" -S "$WORK/t2.vim"
check "final newline in dump" \
    "00000000: 41 42 0a                                         AB." \
    "$(cat "$WORK/t2.out")"

# --- Test 3: write with inserted bytes; cursor stays on the typed byte -----
cat > "$WORK/t3.vim" <<EOF
source $PLUGIN
HexPairToggle
call append(1, '01 02 03 04 05')
call cursor(2, 7)
write
call writefile([line('.') . ',' . col('.') . '=' . strpart(getline('.'), col('.') - 1, 2)], '$WORK/t3.out')
qa!
EOF
vim -es -b -u NONE "$WORK/ins.bin" -S "$WORK/t3.vim"
check "insert-write cursor on typed byte" "1,41=03" "$(cat "$WORK/t3.out")"
check "insert-write file content" \
    "00000000: 41 42 43 44 45 46 47 48 01 02 03 04 05           ABCDEFGH....." \
    "$(xxd -g 1 "$WORK/ins.bin")"

# --- Test 4: non-default bytes_per_line geometry ---------------------------
cat > "$WORK/t4.vim" <<EOF
source $PLUGIN
let g:hexpair_bytes_per_line = 23
execute 'goto 1423'
HexPairToggle
let dump = line('.') . ',' . col('.') . '=' . strpart(getline('.'), col('.') - 1, 2)
HexPairToggle
call writefile([dump, string(line2byte(line('.')) + col('.') - 2)], '$WORK/t4.out')
qa!
EOF
vim -es -b -u NONE "$WORK/pos.bin" -S "$WORK/t4.vim"
check "n=23 dump position"  "62,68=69" "$(sed -n 1p "$WORK/t4.out")"
check "n=23 return offset"  "1422"     "$(sed -n 2p "$WORK/t4.out")"

# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED." >&2
fi
exit $FAIL
