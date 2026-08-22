#!/bin/sh
# ===========================================================================
# Headless regression suite for the hexpair Vim plugin.
#
# Runs Vim in silent Ex mode ("$HEXPAIR_VIM" -es -u NONE) against generated binary
# fixtures and asserts byte-exact behaviour. Requires: vim (with xxd),
# python3 (fixture generation only — dash's printf does not expand \x
# escapes, so binary fixtures must not be generated with printf).
#
# Runs on Windows too, under Git Bash with a native Vim on PATH; see the
# path and interpreter notes below for the two things that differ there.
#
# Exit status: 0 when all tests pass, 1 otherwise.
# ===========================================================================
set -u

cd "$(dirname "$0")"

# Python is python3 everywhere except Windows, where the installers name it
# python - and where a `python3` that merely opens the Microsoft Store is a
# common decoy, so the candidate has to actually run before it is believed.
PY=
for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1 \
        && "$candidate" -c 'raise SystemExit(0)' >/dev/null 2>&1; then
        PY=$candidate
        break
    fi
done
if [ -z "$PY" ]; then
    echo "run-tests.sh: no working python3 (or python) on PATH" >&2
    exit 1
fi

# The Vim and the xxd under test. Overridable because PATH order is not a
# reliable way to say which one that is: in a Git Bash step on Windows,
# Git's own MSYS Vim comes first whatever else was added, and testing that
# one proves nothing about native Windows - it understands POSIX paths,
# which is exactly what this suite exists not to rely on. Not named VIM:
# that variable tells Vim where its runtime lives.
HEXPAIR_VIM=${HEXPAIR_VIM:-vim}
HEXPAIR_XXD=${HEXPAIR_XXD:-xxd}

ROOT=$(cd .. && pwd)
PLUGIN=../plugin/hexpair.vim
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A native Vim on Windows cannot follow an MSYS path like /tmp/xxx. Git Bash
# rewrites such paths in the arguments it passes to a native program, but not
# inside the generated .vim scripts, which Vim opens itself - so every path
# this suite writes into one has to be in the drive-letter form to begin
# with. cygpath -m gives that with forward slashes, which keeps them usable
# as 'runtimepath' entries and as arguments to the MSYS tools here.
if command -v cygpath >/dev/null 2>&1; then
    ROOT=$(cygpath -m "$ROOT")
    WORK=$(cygpath -m "$WORK")
fi

# Then have Vim spell them: fnamemodify(':p') is what the plugin stores and
# what its banners therefore show, and on Windows it resolves an 8.3 short
# name - MSYS maps /tmp to %TEMP%, which can be C:/Users/RUNNER~1/... - to
# the long form. Asserting a banner against the other spelling of the same
# directory fails on a difference that is not one. On Unix this is a no-op.
cat > "$WORK/canon.vim" <<EOF
call writefile([fnamemodify('$ROOT', ':p:h'), fnamemodify('$WORK', ':p:h')], '$WORK/canon.out')
qa!
EOF
if "$HEXPAIR_VIM" -es -u NONE -S "$WORK/canon.vim" < /dev/null 2>/dev/null \
    && [ -s "$WORK/canon.out" ]; then
    canon_root=$(sed -n 1p "$WORK/canon.out" | tr '\\' '/')
    canon_work=$(sed -n 2p "$WORK/canon.out" | tr '\\' '/')
    rm -f "$WORK/canon.vim" "$WORK/canon.out"
    [ -n "$canon_root" ] && ROOT=$canon_root
    [ -n "$canon_work" ] && WORK=$canon_work
else
    rm -f "$WORK/canon.vim" "$WORK/canon.out"
fi

FAIL=0

# Same, for an expected string carrying a path: Windows spells the
# separator the other way round - fnamemodify(':p') returns backslashes
# there - which says nothing about whether the plugin found the right
# file. Fold both spellings; everything else stays exact.
check_path() { # name expected actual
    check "$1" "$(printf '%s' "$2" | tr '\\' '/')" "$(printf '%s' "$3" | tr '\\' '/')"
}

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

# A file's size, and the SHA-256 of a byte range of it. Both go through
# python3, which this suite already needs for its binary fixtures, rather
# than through wc/dd/sha256sum: sha256sum is GNU-only (macOS ships shasum
# instead), and the suite is meant to need nothing beyond vim, xxd and
# python3.
file_size() { # file
    "$PY" -c 'import os,sys; print(os.path.getsize(sys.argv[1]))' "$1"
}

hash_range() { # file offset length (-1 = to the end of the file)
    "$PY" - "$1" "$2" "$3" <<'PYHASH'
import hashlib, sys
name, off, length = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
with open(name, 'rb') as f:
    f.seek(off)
    print(hashlib.sha256(f.read() if length < 0 else f.read(length)).hexdigest())
PYHASH
}

# --- Fixtures --------------------------------------------------------------
"$PY" - "$WORK" <<'EOF'
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
# validation / reload fixture (must stay unmodified by the tests)
open(os.path.join(w, 'val.bin'), 'wb').write(b'ABCDEFGH')
# the degenerate cases around an empty file: nothing at all, and a lone 0a
open(os.path.join(w, 'empty.bin'), 'wb').write(b'')
open(os.path.join(w, 'nl.bin'), 'wb').write(b'\n')
open(os.path.join(w, 'wipe.bin'), 'wb').write(b'ABCDEFGH')
# modified-flag fixtures: separate copies so a write in one test cannot
# affect another test's expectations
for name in ('mod12.bin', 'mod13.bin', 'mod14.bin', 'mod15.bin'):
    open(os.path.join(w, name), 'wb').write(b'ABCDEFGH')
# :HexPairRefresh fixtures
for name in ('ref1.bin', 'ref2.bin', 'ref3.bin', 'ref4.bin', 'ref5.bin'):
    open(os.path.join(w, name), 'wb').write(b'ABCDEFGH')
# paged-mode fixture: 5000 bytes, byte i has value i % 256 - at 512
# bytes/page that is 10 pages, the last one short (392 bytes)
for name in ('paged21.bin', 'paged22.bin', 'paged23.bin', 'paged31.bin', 'paged32.bin', 'undo1.bin', 'layout1.bin', 'jump1.bin', 'paste1.bin', 'abandon1.bin', 'ulocal1.bin', 'src1.bin', 'off1.bin', 'multi.bin', 'multi2.bin', 'same1.bin', 'vis1.bin', 'pos1.bin', 'ip1.bin', 'ip2.bin', 'ip3.bin', 'w1.bin', 'w2.bin', 'w3.bin', 'w4.bin', 'w5.bin', 'sp1.bin', 'sp2.bin', 'sp3.bin', 'sp4.bin', 'tv1.bin', 'tv2.bin', 'tv3.bin', 'tv4.bin'):
    with open(os.path.join(w, name), 'wb') as f:
        f.write(bytes(i % 256 for i in range(5000)))
# whole-page scan fixtures: big enough for ONE default-size page to hold
# thousands of dump lines, which is the only scale at which a regex over
# the whole page can behave differently from the same regex over one line
for name in ('scan1.bin', 'scan2.bin'):
    with open(os.path.join(w, name), 'wb') as f:
        f.write(bytes((i * 7) % 256 for i in range(100000)))
# marks fixture
open(os.path.join(w, 'mark1.bin'), 'wb').write(bytes(i % 256 for i in range(5000)))
# stepping fixture
open(os.path.join(w, 'step1.bin'), 'wb').write(bytes(i % 256 for i in range(5000)))
# two-views fixtures
for name in ('split1.bin', 'split2.bin', 'split3.bin', 'split4.bin'):
    with open(os.path.join(w, name), 'wb') as f:
        f.write(bytes(i % 256 for i in range(5000)))
# data-inspector fixture: a little-endian double and float at known
# offsets, so the conversions can be checked against python's packing
import struct
_insp = bytearray(bytes(i % 256 for i in range(512)))
_insp[0:8] = struct.pack('<d', 1234.5678)
_insp[8:12] = struct.pack('<f', -3.25)
open(os.path.join(w, 'insp1.bin'), 'wb').write(bytes(_insp))
# same-second tampering fixture
open(os.path.join(w, 'digest1.bin'), 'wb').write(bytes(i % 256 for i in range(5000)))
# page-goto fixture
open(os.path.join(w, 'pgoto1.bin'), 'wb').write(bytes(i % 256 for i in range(5000)))
# selection fixture
open(os.path.join(w, 'sel1.bin'), 'wb').write(bytes(i % 256 for i in range(5000)))
# statusline fixture
open(os.path.join(w, 'status1.bin'), 'wb').write(bytes(i % 256 for i in range(5000)))
# ruler fixture
open(os.path.join(w, 'ruler1.bin'), 'wb').write(bytes(i % 256 for i in range(5000)))
# cursor-byte fixture
open(os.path.join(w, 'cbo1.bin'), 'wb').write(bytes(i % 256 for i in range(5000)))
# trace fixture
open(os.path.join(w, 'dbg1.bin'), 'wb').write(bytes(i % 256 for i in range(5000)))
# and a 32-byte one, for the lines a scan must not be thrown by
open(os.path.join(w, 'scan3.bin'), 'wb').write(bytes(range(32)))
# single-page fixture, so a shrinking write can empty the file entirely
open(os.path.join(w, 'sp5.bin'), 'wb').write(bytes(range(16)))
# a real file past the 4 GiB mark, where xxd's offset column widens from
# eight to nine hex digits. Sparse: a few KiB on disk, not 4 GiB.
with open(os.path.join(w, 'huge.bin'), 'wb') as f:
    f.truncate(4 * 1024**3 + 4096)
    f.seek(4 * 1024**3)
    f.write(bytes(range(16)))
# fixture with a name that is awkward for Ex command-line argument
# parsing: a space and a literal '$NAME' substring
special_dir = os.path.join(w, 'space dir')
os.mkdir(special_dir)
with open(os.path.join(special_dir, 'dollar $HOSTNAME name.bin'), 'wb') as f:
    f.write(b'ABCDEFGH')
EOF

# ===========================================================================
# Hex mode: one mode, always paged
# ===========================================================================
# :HexPairToggle moves PLAIN -> HEX-PAGE -> WINDOWED-TEXT -> HEX-PAGE ...
# A small file simply has one page. Most of these use a 512-byte page so a
# 2900-byte fixture has several of them.
HEX="source $PLUGIN\nlet g:hexpair_page_size = 512\nlet g:hexpair_page_confirm = 0"

# --- Test 1: every transition keeps the cursor on the same byte -------------
# The cursor's byte also picks the page hex mode opens on - not page 1.
cat > "$WORK/t1.vim" <<EOF
$(printf "$HEX")
execute 'goto 1423'
HexPairToggle
let hex = [b:hexpair_page_index, line('.'), col('.'), strpart(getline('.'), col('.') - 1, 2), HexPairPagedByteOffset()]
HexPairToggle
let text = [b:hexpair_view, line('.'), col('.')]
HexPairToggle
let back = [b:hexpair_view, line('.'), col('.'), strpart(getline('.'), col('.') - 1, 2), HexPairPagedByteOffset()]
call writefile([string(hex), string(text), string(back)], '$WORK/t1.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/pos.bin" -S "$WORK/t1.vim" < /dev/null
check "hex mode opens on the cursor's page, on its byte" \
    "[2, 26, 53, '69', 1422]" "$(sed -n 1p "$WORK/t1.out")"
check "the text view keeps the byte"  "['text', 16, 2]" "$(sed -n 2p "$WORK/t1.out")"
check "and so does the way back"      "['hex', 26, 53, '69', 1422]" "$(sed -n 3p "$WORK/t1.out")"

# --- Test 2: the banner, and a final newline byte in the dump --------------
cat > "$WORK/t2.vim" <<EOF
$(printf "$HEX")
HexPairToggle
call writefile([getline(1), getline(2), getline('\$'), string(line('\$'))], '$WORK/t2.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/eol.bin" -S "$WORK/t2.vim" < /dev/null
check_path "a one-page file still gets a banner" \
    "\" hexpair: page 1/1  bytes 1-3 of 3  $WORK/eol.bin" "$(sed -n 1p "$WORK/t2.out")"
check "final newline in dump" \
    "00000000: 41 42 0a                                         AB." \
    "$(sed -n 2p "$WORK/t2.out")"
check "and a closing banner" "\" hexpair: end of page 1/1" "$(sed -n 3p "$WORK/t2.out")"
check "banner, dump line, banner"     "3" "$(sed -n 4p "$WORK/t2.out")"

# --- Test 3: inserting bytes and writing ------------------------------------
cat > "$WORK/t3.vim" <<EOF
$(printf "$HEX")
HexPairToggle
call append(2, '01 02 03 04 05')
call cursor(3, 7)
write
call writefile([line('.') . ',' . col('.') . '=' . strpart(getline('.'), col('.') - 1, 2)], '$WORK/t3.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/ins.bin" -S "$WORK/t3.vim" < /dev/null
check "insert-write cursor on typed byte" "2,41=03" "$(cat "$WORK/t3.out")"
check "insert-write file content" \
    "00000000: 41 42 43 44 45 46 47 48 01 02 03 04 05           ABCDEFGH....." \
    "$("$HEXPAIR_XXD" -g 1 "$WORK/ins.bin")"

# --- Test 4: non-default bytes_per_line geometry ---------------------------
# g:hexpair_page_size must stay a multiple of it, so both move together.
cat > "$WORK/t4.vim" <<EOF
source $PLUGIN
let g:hexpair_bytes_per_line = 23
let g:hexpair_page_size = 23 * 20
execute 'goto 1423'
HexPairToggle
let dump = line('.') . ',' . col('.') . '=' . strpart(getline('.'), col('.') - 1, 2)
call writefile([dump, string(HexPairPagedByteOffset())], '$WORK/t4.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/pos.bin" -S "$WORK/t4.vim" < /dev/null
check "n=23 dump position"  "3,68=69" "$(sed -n 1p "$WORK/t4.out")"
check "n=23 cursor byte"    "1422"     "$(sed -n 2p "$WORK/t4.out")"

# --- Test 5: ftplugin defaults and 'paste' across the three states ---------
# The xxd editing defaults belong to a dump: they apply in the hex view and
# are reverted in the text view, which shows raw bytes. 'paste' stays on for
# both - it is the buffer that is a hex buffer, not the view.
cat > "$WORK/t5.vim" <<EOF
" Hermetic runtimepath: only the repo and \$VIMRUNTIME, so a developer's
" personal ~/.vim/ftplugin/xxd.vim cannot leak into the assertions.
let &runtimepath = '$ROOT,' . \$VIMRUNTIME
filetype plugin on
$(printf "$HEX")
HexPairToggle
let on = [&l:tabstop, &l:shiftwidth, &l:expandtab, &paste]
HexPairToggle
let text = [&l:tabstop, &l:shiftwidth, &l:expandtab, &paste, exists('b:did_ftplugin')]
HexPairToggle
let re = [&l:tabstop, &l:expandtab, &paste]
call writefile([string(on), string(text), string(re)], '$WORK/t5.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/ins.bin" -S "$WORK/t5.vim" < /dev/null
check "ftplugin + paste active in the hex view"  "[10, 3, 1, 1]"   "$(sed -n 1p "$WORK/t5.out")"
check "ftplugin reverted in the text view"       "[8, 8, 0, 1, 0]" "$(sed -n 2p "$WORK/t5.out")"
check "ftplugin re-applied back in the hex view" "[10, 1, 1]"      "$(sed -n 3p "$WORK/t5.out")"

# --- Test 6: a user ftplugin with b:did_ftplugin suppresses the bundled one -
mkdir -p "$WORK/user-rtp/ftplugin"
cat > "$WORK/user-rtp/ftplugin/xxd.vim" <<'EOF'
let b:did_ftplugin = 1
setlocal tabstop=4
EOF
cat > "$WORK/t6.vim" <<EOF
let &runtimepath = '$WORK/user-rtp,$ROOT,' . \$VIMRUNTIME
filetype plugin on
$(printf "$HEX")
HexPairToggle
call writefile([string([&l:tabstop, &l:shiftwidth])], '$WORK/t6.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/ins.bin" -S "$WORK/t6.vim" < /dev/null
check "user ftplugin overrules bundled defaults" "[4, 8]" "$(cat "$WORK/t6.out")"

# --- Test 7: g:hexpair_paste opt-out; restore on leaving the hex buffer ----
cat > "$WORK/t7.vim" <<EOF
let &runtimepath = '$ROOT,' . \$VIMRUNTIME
filetype plugin on
$(printf "$HEX")
let g:hexpair_paste = 0
HexPairToggle
let optout = &paste
let g:hexpair_paste = 1
HexPairPageGoto 1
let inhex = &paste
new
let outside = &paste
wincmd p
let back = &paste
call writefile([string([optout, inhex, outside, back])], '$WORK/t7.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/ins.bin" -S "$WORK/t7.vim" < /dev/null
check "paste opt-out and restore on buffer switch" "[0, 1, 0, 1]" "$(cat "$WORK/t7.out")"

# --- Test 8: a non-hex character aborts :w; file and dump stay intact ------
cat > "$WORK/t8.vim" <<EOF
$(printf "$HEX")
HexPairToggle
call setline(2, substitute(getline(2), '41', '4x', ''))
let caught = ''
try
  write
catch /^hexpair:/
  let caught = 'caught'
endtry
let state = string([get(b:, 'hexpair_page_active', 0), line('.'), col('.')])
call writefile([caught, state, getline(2)], '$WORK/t8.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/val.bin" -S "$WORK/t8.vim" < /dev/null
check "invalid char aborts the write"  "caught"     "$(sed -n 1p "$WORK/t8.out")"
check "cursor parked on the offender"  "[1, 2, 12]" "$(sed -n 2p "$WORK/t8.out")"
check "dump kept after aborted write" \
    "00000000: 4x 42 43 44 45 46 47 48                          ABCDEFGH" \
    "$(sed -n 3p "$WORK/t8.out")"
check "file kept after aborted write" \
    "00000000: 41 42 43 44 45 46 47 48                          ABCDEFGH" \
    "$("$HEXPAIR_XXD" -g 1 "$WORK/val.bin")"

# --- Test 9: a non-hex character refuses the switch to the text view -------
cat > "$WORK/t9.vim" <<EOF
$(printf "$HEX")
HexPairToggle
call append(2, '01 0g 03')
redir => msg
HexPairToggle
redir END
call writefile([string([b:hexpair_view, line('.'), col('.'), msg =~# 'still in the hex view'])], '$WORK/t9.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/val.bin" -S "$WORK/t9.vim" < /dev/null
check "invalid char refuses the text view" "['hex', 3, 5, 1]" "$(cat "$WORK/t9.out")"

# --- Test 10: an odd total number of hex digits aborts :w ------------------
cat > "$WORK/t10.vim" <<EOF
$(printf "$HEX")
HexPairToggle
call append(2, '01 2')
let caught = ''
try
  write
catch /^hexpair:/
  let caught = v:exception =~# 'odd' ? 'odd' : 'other'
endtry
call writefile([caught], '$WORK/t10.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/val.bin" -S "$WORK/t10.vim" < /dev/null
check "odd digit count aborts the write" "odd" "$(cat "$WORK/t10.out")"

# --- Test 11: :e re-reads the page from disk -------------------------------
cat > "$WORK/t11.vim" <<EOF
$(printf "$HEX")
HexPairToggle
call cursor(2, 20)
" :e resets the cursor before BufReadCmd runs, so the plugin restores it
" from the position noted on every CursorMoved - which no autocommand
" fires for in Ex mode, hence the explicit jump command here.
HexPairGoHex
call setline(2, substitute(getline(2), '41', 'ff', ''))
silent edit!
let state = string([get(b:, 'hexpair_page_active', 0), b:hexpair_view, line('.'), col('.'), &l:modified])
call writefile([getline(2), state], '$WORK/t11.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/val.bin" -S "$WORK/t11.vim" < /dev/null
check "reload regenerates the page" \
    "00000000: 41 42 43 44 45 46 47 48                          ABCDEFGH" \
    "$(sed -n 1p "$WORK/t11.out")"
check "reload keeps hex mode and the cursor" "[1, 'hex', 2, 20, 0]" \
    "$(sed -n 2p "$WORK/t11.out")"

# --- Test 12: an edit made in the hex view marks the buffer modified -------
# It used to be cleared on the way out of hex mode, so :q discarded it.
cat > "$WORK/t12.vim" <<EOF
$(printf "$HEX")
HexPairToggle
call setline(2, substitute(getline(2), '41', 'ff', ''))
let inhex = &l:modified
HexPairToggle
call writefile([string([inhex, &l:modified, char2nr(getline(2)[0])])], '$WORK/t12.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/mod12.bin" -S "$WORK/t12.vim" < /dev/null
check "an edit in the hex view survives into the text view, still modified" \
    "[1, 1, 255]" "$(cat "$WORK/t12.out")"

# --- Test 13: an edit-free round trip stays unmodified ---------------------
cat > "$WORK/t13.vim" <<EOF
$(printf "$HEX")
HexPairToggle
HexPairToggle
let text = &l:modified
HexPairToggle
call writefile([string([text, &l:modified])], '$WORK/t13.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/mod13.bin" -S "$WORK/t13.vim" < /dev/null
check "an edit-free round trip stays unmodified" "[0, 0]" "$(cat "$WORK/t13.out")"

# --- Test 14: an edit made in the text view survives back into the dump ----
cat > "$WORK/t14.vim" <<EOF
$(printf "$HEX")
HexPairToggle
HexPairToggle
call setline(2, 'ZZ' . getline(2)[2:])
let intext = &l:modified
HexPairToggle
call writefile([string([intext, &l:modified]), getline(2)], '$WORK/t14.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/mod14.bin" -S "$WORK/t14.vim" < /dev/null
check "an edit in the text view keeps the buffer modified" "[1, 1]" \
    "$(sed -n 1p "$WORK/t14.out")"
check "and shows up in the dump" \
    "00000000: 5a 5a 43 44 45 46 47 48                          ZZCDEFGH" \
    "$(sed -n 2p "$WORK/t14.out")"

# --- Test 15: a write clears 'modified' and reaches the file ---------------
cat > "$WORK/t15.vim" <<EOF
$(printf "$HEX")
HexPairToggle
call setline(2, substitute(getline(2), '41', 'ff', ''))
write
let afterwrite = &l:modified
HexPairToggle
call writefile([string([afterwrite, &l:modified])], '$WORK/t15.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/mod15.bin" -S "$WORK/t15.vim" < /dev/null
check "a write clears 'modified' and the text view keeps it clear" "[0, 0]" \
    "$(cat "$WORK/t15.out")"
check "the write reached the file" \
    "00000000: ff 42 43 44 45 46 47 48                          .BCDEFGH" \
    "$("$HEXPAIR_XXD" -g 1 "$WORK/mod15.bin")"

# --- Test 16: :HexPairRefresh self-heals offsets/ASCII without writing -----
cat > "$WORK/t16.vim" <<EOF
$(printf "$HEX")
HexPairToggle
call setline(2, '41 42 43 44 45 46 47 48')
call cursor(2, 17)
HexPairRefresh
call writefile([getline(2), string([line('.'), col('.'), &l:modified])], '$WORK/t16.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/ref1.bin" -S "$WORK/t16.vim" < /dev/null
check "refresh: offsets and ASCII column regenerated" \
    "00000000: 41 42 43 44 45 46 47 48                          ABCDEFGH" \
    "$(sed -n 1p "$WORK/t16.out")"
check "refresh: cursor stays on the same byte, buffer still modified" \
    "[2, 26, 1]" "$(sed -n 2p "$WORK/t16.out")"

# --- Test 17: a no-op refresh leaves 'modified' alone ----------------------
cat > "$WORK/t17.vim" <<EOF
$(printf "$HEX")
HexPairToggle
HexPairRefresh
call writefile([string([&l:modified, getline(2) ==# '00000000: 41 42 43 44 45 46 47 48                          ABCDEFGH'])], '$WORK/t17.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/ref2.bin" -S "$WORK/t17.vim" < /dev/null
check "a no-op refresh changes nothing" "[0, 1]" "$(cat "$WORK/t17.out")"

# --- Test 18: an invalid dump refuses the refresh --------------------------
cat > "$WORK/t18.vim" <<EOF
$(printf "$HEX")
HexPairToggle
call setline(2, substitute(getline(2), '41', '4x', ''))
redir => msg
HexPairRefresh
redir END
call writefile([getline(2), string([msg =~# 'invalid character', line('.'), col('.')])], '$WORK/t18.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/ref3.bin" -S "$WORK/t18.vim" < /dev/null
check "an invalid dump is left as typed" \
    "00000000: 4x 42 43 44 45 46 47 48                          ABCDEFGH" \
    "$(sed -n 1p "$WORK/t18.out")"
check "and the refresh is refused with the cursor on it" "[1, 2, 12]" \
    "$(sed -n 2p "$WORK/t18.out")"

# --- Test 19: refresh outside hex mode, and in the text view ---------------
cat > "$WORK/t19.vim" <<EOF
$(printf "$HEX")
redir => outside
HexPairRefresh
redir END
HexPairToggle
HexPairToggle
redir => intext
HexPairRefresh
redir END
call writefile([string([outside =~# 'not active', intext =~# 'no offset or ASCII columns', b:hexpair_view])], '$WORK/t19.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/ref4.bin" -S "$WORK/t19.vim" < /dev/null
check "refresh says so outside hex mode and in the text view" "[1, 1, 'text']" \
    "$(cat "$WORK/t19.out")"

# --- Test 20: the banner cannot be faked away in the text view -------------
# A dump line always starts with a hex digit, so '"' marks a banner there
# unambiguously - but a page of raw bytes may start with one, so the text
# view checks the banner text itself and refuses to guess.
cat > "$WORK/t20.vim" <<EOF
$(printf "$HEX")
HexPairToggle
HexPairToggle
call setline(1, '" hexpair: page 1/1  bytes 1-8 of 8  tampered')
let caught = ''
try
  write
catch /^hexpair:/
  let caught = v:exception =~# 'banner was edited' ? 'refused' : v:exception
endtry
call writefile([caught, string(&l:modified)], '$WORK/t20.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/ref5.bin" -S "$WORK/t20.vim" < /dev/null
check "an edited banner refuses the write"      "refused" "$(sed -n 1p "$WORK/t20.out")"
check "and leaves the buffer unwritten"         "1"       "$(sed -n 2p "$WORK/t20.out")"
check "the file is untouched" \
    "00000000: 41 42 43 44 45 46 47 48                          ABCDEFGH" \
    "$("$HEXPAIR_XXD" -g 1 "$WORK/ref5.bin")"

# --- Test 21: :HexPairOpen shows page 1 with banner and absolute offsets ---
cat > "$WORK/t21.vim" <<EOF
source $PLUGIN
let g:hexpair_page_size = 512
HexPairOpen $WORK/paged21.bin 1
let state = string([line('\$'), line('.'), col('.'), strpart(getline('.'), col('.') - 1, 2)])
call writefile([getline(1), getline(2), getline('\$'), state], '$WORK/t21.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/t21.vim"
check_path "page 1 top banner" \
    "\" hexpair: page 1/10  bytes 1-512 of 5000  $WORK/paged21.bin" \
    "$(sed -n 1p "$WORK/t21.out")"
check "page 1 first data line" \
    "00000000: 00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f  ................" \
    "$(sed -n 2p "$WORK/t21.out")"
check "page 1 bottom banner" "\" hexpair: end of page 1/10" "$(sed -n 3p "$WORK/t21.out")"
check "page 1 line count and cursor on first byte" "[34, 2, 11, '00']" \
    "$(sed -n 4p "$WORK/t21.out")"

# --- Test 22: :HexPairPageNext / :HexPairPageGoto move between pages -------
cat > "$WORK/t22.vim" <<EOF
source $PLUGIN
let g:hexpair_page_size = 512
HexPairOpen $WORK/paged22.bin 1
HexPairPageNext
let next = getline(1)
HexPairPageGoto 10
let last = [getline(1), getline('\$'), line('\$')]
try
  HexPairPageNext
  let pastend = 'no-error'
catch
  let pastend = 'error'
endtry
let unchanged = getline(1) ==# last[0]
call writefile([next, string(last), pastend, string(unchanged)], '$WORK/t22.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/t22.vim"
check_path "next page shows page 2" \
    "\" hexpair: page 2/10  bytes 513-1024 of 5000  $WORK/paged22.bin" \
    "$(sed -n 1p "$WORK/t22.out")"
check_path "goto last (short) page banner and size" \
    "['\" hexpair: page 10/10  bytes 4609-5000 of 5000  $WORK/paged22.bin', '\" hexpair: end of page 10/10', 27]" \
    "$(sed -n 2p "$WORK/t22.out")"
check "next past the last page does not throw"  "no-error" "$(sed -n 3p "$WORK/t22.out")"
check "next past the last page leaves the page unchanged" "1" "$(sed -n 4p "$WORK/t22.out")"

# --- Test 23: navigation guard refuses to discard unsaved edits ------------
cat > "$WORK/t23.vim" <<EOF
source $PLUGIN
let g:hexpair_page_size = 512
HexPairOpen $WORK/paged23.bin 1
call setline(2, substitute(getline(2), '00 01', 'ff ee', ''))
HexPairPageNext
let refused = [getline(1), &l:modified]
HexPairPageNext!
let forced = [getline(1), &l:modified]
call writefile([string(refused), string(forced)], '$WORK/t23.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/t23.vim"
check_path "next without ! refuses to discard edits" \
    "['\" hexpair: page 1/10  bytes 1-512 of 5000  $WORK/paged23.bin', 1]" \
    "$(sed -n 1p "$WORK/t23.out")"
check_path "next! discards edits and advances" \
    "['\" hexpair: page 2/10  bytes 513-1024 of 5000  $WORK/paged23.bin', 0]" \
    "$(sed -n 2p "$WORK/t23.out")"

# --- Test 24: :HexPairPages reports the expected text -----------------------
cat > "$WORK/t24.vim" <<EOF
source $PLUGIN
let g:hexpair_page_size = 512
HexPairOpen $WORK/paged21.bin 3
redir => msg
silent HexPairPages
redir END
call writefile([substitute(msg, '^\_s*\|\_s*\$', '', 'g')], '$WORK/t24.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/t24.vim"
check_path "HexPairPages reports page/offsets/total" \
    "hexpair: page 3 of 10, offsets 1025-1536 of total 5000 bytes ($WORK/paged21.bin); cursor on byte 0x401 (1025)" \
    "$(cat "$WORK/t24.out")"

# --- Test 25: splice version-gate message function, both branches ----------
cat > "$WORK/t25.vim" <<EOF
source $PLUGIN
let ok = HexPairPagedGateMessage(1)
let fail = HexPairPagedGateMessage(0)
let saveas = HexPairPagedGateMessage(0, 'writing the whole file somewhere else')
call writefile([string(ok), fail, saveas], '$WORK/t25.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/t25.vim"
check "gate message empty when supported"     "''" "$(sed -n 1p "$WORK/t25.out")"
check "gate message set when unsupported" \
    "hexpair: rewriting the file to change its length needs Vim patch 8.2.4906 or later with +num64 (readblob(), 64-bit Numbers for large file offsets); this Vim does not qualify - nothing was written. An edit that keeps the page's length, or that inserts bytes with no more than half the file after them, does not need it." \
    "$(sed -n 2p "$WORK/t25.out")"
check "gate message names the operation the caller passed" \
    "hexpair: writing the whole file somewhere else needs Vim patch 8.2.4906 or later with +num64 (readblob(), 64-bit Numbers for large file offsets); this Vim does not qualify - nothing was written. An edit that keeps the page's length, or that inserts bytes with no more than half the file after them, does not need it." \
    "$(sed -n 3p "$WORK/t25.out")"

# --- Test 26: g:hexpair_page_size validation --------------------------------
cat > "$WORK/t26.vim" <<EOF
source $PLUGIN
let ok       = HexPairPagedSizeError(1024, 16)
let notmult  = HexPairPagedSizeError(1000, 16)
let negative = HexPairPagedSizeError(-16, 16)
call writefile([string(ok), notmult, negative], '$WORK/t26.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/t26.vim"
check "page size ok"           "''" "$(sed -n 1p "$WORK/t26.out")"
check "page size not a multiple of bytes_per_line" \
    "hexpair: g:hexpair_page_size (1000) must be a positive multiple of g:hexpair_bytes_per_line (16)" \
    "$(sed -n 2p "$WORK/t26.out")"
check "page size not positive" \
    "hexpair: g:hexpair_page_size (-16) must be a positive multiple of g:hexpair_bytes_per_line (16)" \
    "$(sed -n 3p "$WORK/t26.out")"

# --- Test 27: hex-digit width boundary clamping (fabricated total, no real -
# multi-GiB fixture needed - the bounds/page-count functions are pure) -----
cat > "$WORK/t27.vim" <<EOF
source $PLUGIN
" total = 4 GiB + 1 GB; size = 900 MB, so page 4 straddles the
" 4 GiB offset-width boundary - which is allowed: the layout is read off
" each line, so a page needs no alignment to anything.
let total = 4294967296 + 1000000000
let size  = 900000000
let idx = 4294967296 / size
let straddling = HexPairPagedBounds(idx, size, total)
let n = HexPairPagedTotalPages(size, total)
let last = HexPairPagedBounds(n - 1, size, total)
let oob = HexPairPagedBounds(999999, 512, 5000)
let neg = HexPairPagedBounds(-1, 512, 5000)
call writefile([string(straddling), string(n), string(last), string(oob), string(neg)], '$WORK/t27.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/t27.vim"
check "a page may straddle a width boundary, at full size" \
    "[3600000000, 900000000]" "$(sed -n 1p "$WORK/t27.out")"
check "page count is just the file divided by the page size" "6" \
    "$(sed -n 2p "$WORK/t27.out")"
check "the last page is the short one" "[4500000000, 794967296]" \
    "$(sed -n 3p "$WORK/t27.out")"
check "out-of-range page index"        "[-1, -1]" "$(sed -n 4p "$WORK/t27.out")"
check "negative page index"            "[-1, -1]" "$(sed -n 5p "$WORK/t27.out")"

# --- Test 28: banner-aware stripping and validation -------------------------
cat > "$WORK/t28.vim" <<EOF
source $PLUGIN
let banner = '" hexpair: page 3/21  bytes 2097152-3145727 of 45678901  big.bin'
let stripped_banner = HexPairPagedStripLine(banner)
let stripped_data    = HexPairPagedStripLine('00000000: 41 42 43 44                                      ABCD')
call setline(1, [banner, '00000000: 41 42 43 44                                      ABCD', '" hexpair: end of page 3/21'])
let clean = HexPairPagedValidate()
call setline(2, '00000000: 4x 42 43 44                                      ABCD')
let dirty = HexPairPagedValidate()
call writefile([string(stripped_banner), stripped_data, string(clean), string(dirty)], '$WORK/t28.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/t28.vim"
check "banner line strips to zero bytes despite its letters/slashes" "''" "$(sed -n 1p "$WORK/t28.out")"
check "data line strips to its hex payload"                          " 41 42 43 44" "$(sed -n 2p "$WORK/t28.out")"
check "validation ignores banner text (no false positive)"           "{}" "$(sed -n 3p "$WORK/t28.out")"
check "validation still catches a real invalid character"            "{'lnum': 2, 'col': 12, 'msg': 'invalid character ''x'' in the hex area (line 2, column 12)'}" "$(sed -n 4p "$WORK/t28.out")"

# --- Test 29: HexPairOpenFile() opens a name with a space and a literal ----
# '$NAME' substring exactly, bypassing the Ex command-line escaping that
# :HexPairOpen's own -nargs=+ parsing cannot fully round-trip (fnameescape()
# escapes '$', but <f-args>'s unescaping only knows about its own argument
# separators, e.g. a space, and leaves that backslash behind) - this is
# the function form documented for scripts/wrappers building the filename
# programmatically instead of typing it on the Ex command line.
SPECIAL_FILE="$WORK/space dir/dollar \$HOSTNAME name.bin"
cat > "$WORK/t29.vim" <<EOF
source $PLUGIN
let g:hexpair_page_size = 512
call HexPairOpenFile(\$HEXPAIR_TEST_FILE)
let state = string([get(b:, 'hexpair_page_active', 0), HexPairPagedSamePath(b:hexpair_page_file, \$HEXPAIR_TEST_FILE, has('fname_case'), exists('+shellslash'))])
call writefile([state, getline(2)], '$WORK/t29.out')
qa!
EOF
HEXPAIR_TEST_FILE="$SPECIAL_FILE" "$HEXPAIR_VIM" -es -u NONE -S "$WORK/t29.vim"
check "HexPairOpenFile opens a name with a space and a literal \$VAR" \
    "[1, 1]" "$(sed -n 1p "$WORK/t29.out")"
check "HexPairOpenFile shows the correct content" \
    "00000000: 41 42 43 44 45 46 47 48                          ABCDEFGH" \
    "$(sed -n 2p "$WORK/t29.out")"

# --- Test 30: HexPairPagedParsePageInput() - the goto-prompt parsing -------
cat > "$WORK/t30.vim" <<EOF
source $PLUGIN
let empty_input = HexPairPagedParsePageInput('')
let valid_input = HexPairPagedParsePageInput('7')
let bad_input   = HexPairPagedParsePageInput('abc')
call writefile([string(empty_input), string(valid_input), string(bad_input)], '$WORK/t30.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/t30.vim"
check "empty prompt input is cancellation, not an error" "{}" "$(sed -n 1p "$WORK/t30.out")"
check "numeric prompt input yields the page number"      "{'page': 7}" "$(sed -n 2p "$WORK/t30.out")"
check "non-numeric prompt input is a clear error"         "{'msg': 'hexpair: not a page number: abc (a page, +N or -N to step, \$ for the last)'}" "$(sed -n 3p "$WORK/t30.out")"

# --- Test 31: :HexPairPageGoto! discards unsaved changes -------------------
# The mechanism <Plug>(HexPairPageGotoForce) relies on (s:GotoPage()'s
# force flag flowing through to the same guard s:PageNext()/s:PagePrev()
# already exercise via HexPairPageNext! in test 23).
cat > "$WORK/t31.vim" <<EOF
source $PLUGIN
let g:hexpair_page_size = 512
HexPairOpen $WORK/paged31.bin 1
call setline(2, substitute(getline(2), '00 01', 'ff ee', ''))
HexPairPageGoto 5
let refused = [getline(1), &l:modified]
HexPairPageGoto! 5
let forced = [getline(1), &l:modified]
call writefile([string(refused), string(forced)], '$WORK/t31.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/t31.vim"
check_path "goto without ! refuses to discard edits" \
    "['\" hexpair: page 1/10  bytes 1-512 of 5000  $WORK/paged31.bin', 1]" \
    "$(sed -n 1p "$WORK/t31.out")"
check_path "goto! discards edits and jumps" \
    "['\" hexpair: page 5/10  bytes 2049-2560 of 5000  $WORK/paged31.bin', 0]" \
    "$(sed -n 2p "$WORK/t31.out")"

# --- Test 32: :HexPairOpen with a bad page number creates nothing ----------
# Regression test: s:Open() used to enew + rename the buffer to
# "<file> [hexpair page]" BEFORE validating the requested page, leaving
# an empty, inactive, but real-looking acwrite buffer behind on a bad
# page number - harmless only by accident today (Stage 1's :w always
# throws "not implemented"), a landmine once a real write path lands.
# The current buffer must now be completely untouched by either an
# out-of-range or a non-numeric page number.
cat > "$WORK/t32.vim" <<EOF
source $PLUGIN
let g:hexpair_page_size = 512
let before = [bufname('%'), &l:buftype]
HexPairOpen $WORK/paged32.bin 999
let toolarge_unchanged = ([bufname('%'), &l:buftype] ==# before) && !get(b:, 'hexpair_page_active', 0)
HexPairOpen $WORK/paged32.bin abc
let nonnumeric_unchanged = ([bufname('%'), &l:buftype] ==# before) && !get(b:, 'hexpair_page_active', 0)
call writefile([string(toolarge_unchanged), string(nonnumeric_unchanged)], '$WORK/t32.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/t32.vim"
check "out-of-range page number leaves the buffer untouched" "1" "$(sed -n 1p "$WORK/t32.out")"
check "non-numeric page number leaves the buffer untouched"  "1" "$(sed -n 2p "$WORK/t32.out")"

# --- An empty file must survive the round trip -----------------------------
# A file with no bytes has no pages, but must still be viewable - and must
# still be empty afterwards. A file holding a lone 0a looks the same in a
# buffer and must NOT be mistaken for it.
cat > "$WORK/te1.vim" <<EOF
$(printf "$HEX")
HexPairToggle
let view = string([line('\$'), b:hexpair_page_totalpages, get(b:, 'hexpair_page_active', 0)])
write
call writefile([getline(1), view], '$WORK/te1.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/empty.bin" -S "$WORK/te1.vim" < /dev/null
check_path "an empty file says so" "\" hexpair: $WORK/empty.bin is empty" \
    "$(sed -n 1p "$WORK/te1.out")"
check "an empty file has no pages but is still open" "[2, 0, 1]" \
    "$(sed -n 2p "$WORK/te1.out")"
check "an empty file stays empty"       "0"       "$(file_size "$WORK/empty.bin")"

cat > "$WORK/te2.vim" <<EOF
$(printf "$HEX")
HexPairToggle
let dump = getline(2)
write
call writefile([dump], '$WORK/te2.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/nl.bin" -S "$WORK/te2.vim" < /dev/null
check "a lone newline is still dumped" \
    "00000000: 0a                                               ." \
    "$(cat "$WORK/te2.out")"
check "a lone newline survives the round trip" "1" "$(file_size "$WORK/nl.bin")"

# --- Deleting the whole page writes an empty file --------------------------
cat > "$WORK/te3.vim" <<EOF
$(printf "$HEX")
HexPairToggle
%delete _
write
call writefile([string([&l:modified, b:hexpair_page_totalpages]), getline(1)], '$WORK/te3.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/wipe.bin" -S "$WORK/te3.vim" < /dev/null
check "an emptied page writes an empty file" "0" "$(file_size "$WORK/wipe.bin")"
check "and leaves a view saying the file is empty" "[0, 0]" \
    "$(sed -n 1p "$WORK/te3.out")"
check_path "with the banner to match" "\" hexpair: $WORK/wipe.bin is empty" \
    "$(sed -n 2p "$WORK/te3.out")"

# --- Undo does not reach across a page boundary ----------------------------
# Undoing into the previous page would put bytes from a different part of
# the file into a buffer that claims to be this page - and once writing is
# implemented, the next :w would patch them in at this page's offset.
cat > "$WORK/tu1.vim" <<EOF
source $PLUGIN
let g:hexpair_page_size = 512
HexPairOpen $WORK/undo1.bin 1
setlocal undolevels=1000
call setline(2, substitute(getline(2), '00 01', 'aa bb', ''))
HexPairPageNext!
let fresh = [getline(1), getline(2)]
silent! undo
call writefile([string([getline(1) ==# fresh[0], getline(2) ==# fresh[1], b:hexpair_page_index, &l:modified])], '$WORK/tu1.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tu1.vim" < /dev/null
check "undo stops at the page boundary" "[1, 1, 1, 0]" "$(cat "$WORK/tu1.out")"

# --- Undo still works INSIDE a page ----------------------------------------
cat > "$WORK/tu2.vim" <<EOF
source $PLUGIN
let g:hexpair_page_size = 512
HexPairOpen $WORK/undo1.bin 2
let before = getline(2)
call setline(2, substitute(getline(2), '00 01', 'aa bb', ''))
let edited = getline(2) !=# before
silent! undo
call writefile([string([edited, getline(2) ==# before])], '$WORK/tu2.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tu2.vim" < /dev/null
check "undo still works inside a page" "[1, 1]" "$(cat "$WORK/tu2.out")"

# --- A page that did not come out the expected size is refused -------------
# xxd runs through the shell, which can fail without Vim noticing; a short
# or empty buffer presented as the page would be patched into the file by
# the next write.
cat > "$WORK/ts1.vim" <<EOF
source $PLUGIN
let g:hexpair_page_size = 512
HexPairOpen $WORK/undo1.bin 1
let good = string([line('\$'), b:hexpair_page_len])
call writefile([good], '$WORK/ts1.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/ts1.vim" < /dev/null
check "a full page is two banner lines plus its dump lines" "[34, 512]" \
    "$(cat "$WORK/ts1.out")"

# --- The paged column layout lines up with the dump it describes -----------
# hexstart used to be the offset digits + 2, which lands on the SPACE
# after the ':' rather than on the first hex digit - so the pair
# highlight covered a space and one digit, and the cursor came to rest one
# column short of the byte it was meant to be on.
cat > "$WORK/tl1.vim" <<EOF
source $PLUGIN
let g:hexpair_page_size = 512
HexPairOpen $WORK/layout1.bin 2
let l = getline(2)
let hexstart = b:hexpair_page_hexstart
let hexend = hexstart + 3 * b:hexpair_n - 2
let asciistart = hexend + 3
let found_hex = match(l, '[0-9a-f]', stridx(l, ':')) + 1
let found_ascii = match(l, '  \zs', stridx(l, ':')) + 1
call writefile([string([hexstart, found_hex]), string([hexend, strpart(l, hexend - 1, 1)]), string([asciistart, found_ascii])], '$WORK/tl1.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tl1.vim" < /dev/null
check "hexstart is the first hex digit"     "[11, 11]"   "$(sed -n 1p "$WORK/tl1.out")"
check "hexend is the last hex digit"        "[57, 'f']"  "$(sed -n 2p "$WORK/tl1.out")"
check "asciistart is the first ASCII char"  "[60, 60]"   "$(sed -n 3p "$WORK/tl1.out")"

# ===========================================================================
# Paged mode: writing a page
# ===========================================================================
PAGEDW="source $PLUGIN\nlet g:hexpair_page_size = 512\nlet g:hexpair_page_confirm = 0"

# --- A same-length write patches ONLY the page it belongs to ---------------
# This is the guarantee the in-place path exists for: the file must not be
# truncated, nothing may be appended, and every byte outside the page must
# be bit-identical afterwards, whatever the file's size.
W1_HEAD=$(hash_range "$WORK/w1.bin" 0 512)
W1_TAIL=$(hash_range "$WORK/w1.bin" 1024 -1)
cat > "$WORK/tw1.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/w1.bin 2
call cursor(2, b:hexpair_page_hexstart)
call setline(2, substitute(getline(2), '00 01', 'de ad', ''))
write
call writefile([string([&l:modified, line('.'), col('.')]), getline(2)], '$WORK/tw1.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tw1.vim" < /dev/null
check "in-place write clears 'modified' and keeps the cursor byte" "[0, 2, 11]" \
    "$(sed -n 1p "$WORK/tw1.out")"
check "in-place write shows in the re-read page" \
    "00000200: de ad 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f  ................" \
    "$(sed -n 2p "$WORK/tw1.out")"
check "in-place write keeps the file length"     "5000"     "$(file_size "$WORK/w1.bin")"
check "in-place write leaves the head untouched" "$W1_HEAD" "$(hash_range "$WORK/w1.bin" 0 512)"
check "in-place write leaves the tail untouched" "$W1_TAIL" "$(hash_range "$WORK/w1.bin" 1024 -1)"
check "in-place write changed exactly the edited bytes" \
    "00000200: de ad 02 03                                      ...." \
    "$("$HEXPAIR_XXD" -s 512 -l 4 -g 1 "$WORK/w1.bin")"

# --- A write on the short LAST page is patched the same way ----------------
cat > "$WORK/tw2.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/w2.bin 10
call setline(2, substitute(getline(2), '00 01', 'ff 01', ''))
write
call writefile([string([&l:modified, b:hexpair_page_len])], '$WORK/tw2.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tw2.vim" < /dev/null
check "the short last page writes too" "[0, 392]" "$(cat "$WORK/tw2.out")"
check "the short last page keeps the file length" "5000" "$(file_size "$WORK/w2.bin")"
check "the short last page patched its first byte" \
    "00001200: ff                                               ." \
    "$("$HEXPAIR_XXD" -s 4608 -l 1 -g 1 "$WORK/w2.bin")"

# --- An invalid dump refuses the write, on disk and in the buffer ----------
W3_ALL=$(hash_range "$WORK/w3.bin" 0 -1)
cat > "$WORK/tw3.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/w3.bin 2
call setline(2, substitute(getline(2), '00 01', '00 0x', ''))
let caught = ''
try
  write
catch /hexpair:/
  let caught = 'refused'
endtry
call writefile([caught, string([&l:modified, line('.'), col('.')])], '$WORK/tw3.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tw3.vim" < /dev/null
check "an invalid dump refuses the paged write" "refused"     "$(sed -n 1p "$WORK/tw3.out")"
check "the cursor is parked on the offender"    "[1, 2, 15]"  "$(sed -n 2p "$WORK/tw3.out")"
check "an invalid dump leaves the file alone"   "$W3_ALL"     "$(hash_range "$WORK/w3.bin" 0 -1)"

# --- A file that changed on disk is refused --------------------------------
W4_ALL=$(hash_range "$WORK/w4.bin" 0 -1)
cat > "$WORK/tw4.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/w4.bin 2
call setline(2, substitute(getline(2), '00 01', 'de ad', ''))
let b:hexpair_page_total = b:hexpair_page_total - 1
let caught = ''
try
  write
catch /hexpair:/
  let caught = v:exception =~# 'changed on disk' ? 'refused' : v:exception
endtry
call writefile([caught, string([&l:modified])], '$WORK/tw4.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tw4.vim" < /dev/null
check "a file changed on disk refuses the write" "refused" "$(sed -n 1p "$WORK/tw4.out")"
check "the refused write left the buffer dirty"  "[1]"     "$(sed -n 2p "$WORK/tw4.out")"
check "the refused write left the file alone"    "$W4_ALL" "$(hash_range "$WORK/w4.bin" 0 -1)"

# --- ':w {file}' saves the WHOLE content, with this page's edits in it -----
# Not the page on its own: the buffer shows one page, but what the user
# means by "save it over there" is the thing they are looking into. The
# original is left exactly as it was.
W5_BEFORE=$(hash_range "$WORK/w5.bin" 0 -1)
cat > "$WORK/tw5.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/w5.bin 2
call setline(2, substitute(getline(2), '00 01', 'de ad', ''))
write $WORK/elsewhere.bin
let state = string([&l:modified, HexPairPagedSamePath(b:hexpair_page_file, '$WORK/w5.bin', has('fname_case'), exists('+shellslash'))])
write
call writefile([state, string([&l:modified])], '$WORK/tw5.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tw5.vim" < /dev/null
check "':w other' leaves the buffer and its own file alone" "[1, 1]" \
    "$(sed -n 1p "$WORK/tw5.out")"
check "the copy is the whole file, not just the page" "5000" \
    "$(file_size "$WORK/elsewhere.bin")"
check "with the page's edit in it" \
    "00000200: de ad 02 03" "$("$HEXPAIR_XXD" -s 512 -l 4 -g 1 "$WORK/elsewhere.bin" | cut -c1-21)"
check "and everything outside the page copied verbatim" \
    "$(hash_range "$WORK/w5.bin" 1024 -1)" "$(hash_range "$WORK/elsewhere.bin" 1024 -1)"
check "':w' afterwards still writes the page to its own file" "[0]" \
    "$(sed -n 2p "$WORK/tw5.out")"
check "which is where the edit ended up too" \
    "00000200: de ad 02 03" "$("$HEXPAIR_XXD" -s 512 -l 4 -g 1 "$WORK/w5.bin" | cut -c1-21)"

# --- Piped input can only be saved with ':w {file}' - and then adopts it ---
# `cat x | vim -` has no file behind it. A plain :w says so; :w {file}
# writes everything, and the view goes on editing that file.
cat > "$WORK/tw6.vim" <<EOF
$(printf "$PAGEDW")
enew
call setline(1, ['piped line one', 'piped line two'])
HexPairToggle
redir => msg
silent! write
redir END
let plain = msg =~# 'no file to write it back to' || msg =~# 'E32'
call setline(2, substitute(getline(2), '^\(.\{10\}\)..', '\1ff', ''))
write $WORK/frompipe.bin
let after = string([&l:modified, HexPairPagedSamePath(b:hexpair_page_file, '$WORK/frompipe.bin', has('fname_case'), exists('+shellslash')), get(b:, 'hexpair_page_spill', 'gone') ==# ''])
call setline(2, substitute(getline(2), '^\(.\{10\}\)..', '\1ee', ''))
write
call writefile([string(plain), after, string([&l:modified])], '$WORK/tw6.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tw6.vim" < /dev/null
check "a plain ':w' on piped input says there is no file"  "1" "$(sed -n 1p "$WORK/tw6.out")"
check "':w file' saves it and the view adopts the file" "[0, 1, 1]" \
    "$(sed -n 2p "$WORK/tw6.out")"
check "the saved file has all of the piped content, edited" \
    "00000000: ee 69 70 65 64 20 6c 69 6e 65 20 6f 6e 65 0a 70  .iped line one.p" \
    "$("$HEXPAIR_XXD" -s 0 -l 16 -g 1 "$WORK/frompipe.bin")"
check "and a later plain ':w' now patches that file" "[0]" "$(sed -n 3p "$WORK/tw6.out")"
check "which it did" "00000000: ee" "$("$HEXPAIR_XXD" -s 0 -l 1 -g 1 "$WORK/frompipe.bin" | cut -c1-12)"

# --- A growing write splices the file ---------------------------------------
SP1_HEAD=$(hash_range "$WORK/sp1.bin" 0 512)
SP1_TAIL=$(hash_range "$WORK/sp1.bin" 512 -1)
cat > "$WORK/ts3a.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/sp1.bin 2
call cursor(2, b:hexpair_page_hexstart)
call append(1, 'aa bb cc')
write
call writefile([string([&l:modified, b:hexpair_page_total, line('.'), col('.')]), getline(2)], '$WORK/ts3a.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/ts3a.vim" < /dev/null
check "grow: the file is three bytes longer, cursor still on its byte" \
    "[0, 5003, 2, 20]" "$(sed -n 1p "$WORK/ts3a.out")"
check "grow: the inserted bytes open the page" \
    "00000200: aa bb cc 00 01 02 03 04 05 06 07 08 09 0a 0b 0c  ................" \
    "$(sed -n 2p "$WORK/ts3a.out")"
check "grow: the file really grew"   "5003"      "$(file_size "$WORK/sp1.bin")"
check "grow: the head is unchanged"  "$SP1_HEAD" "$(hash_range "$WORK/sp1.bin" 0 512)"
check "grow: the tail is unchanged, just moved" "$SP1_TAIL" \
    "$(hash_range "$WORK/sp1.bin" 515 -1)"

# --- A shrinking write splices the file -------------------------------------
SP2_HEAD=$(hash_range "$WORK/sp2.bin" 0 512)
SP2_TAIL=$(hash_range "$WORK/sp2.bin" 528 -1)
cat > "$WORK/ts3b.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/sp2.bin 2
2delete _
write
call writefile([string([&l:modified, b:hexpair_page_total, b:hexpair_page_len])], '$WORK/ts3b.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/ts3b.vim" < /dev/null
check "shrink: the file is sixteen bytes shorter" "[0, 4984, 512]" \
    "$(cat "$WORK/ts3b.out")"
check "shrink: the file really shrank" "4984"      "$(file_size "$WORK/sp2.bin")"
check "shrink: the head is unchanged"  "$SP2_HEAD" "$(hash_range "$WORK/sp2.bin" 0 512)"
check "shrink: the tail is unchanged, just moved" "$SP2_TAIL" \
    "$(hash_range "$WORK/sp2.bin" 512 -1)"

# --- The temp file is gone after a successful splice ------------------------
# Nothing of ours may be left in tempname()'s directory once the write has
# succeeded. Count the difference, not the contents: that directory is
# private and empty per Vim session on Unix, but on Windows tempname()
# names files straight in the shared %TEMP%, which is full of other
# people's.
cat > "$WORK/ts3c.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/sp3.bin 2
let dir = fnamemodify(tempname(), ':h')
let before = len(glob(dir . '/*', 0, 1))
call append(1, 'aa bb cc')
write
call writefile([string([len(glob(dir . '/*', 0, 1)) - before, &l:modified])], '$WORK/ts3c.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/ts3c.vim" < /dev/null
check "a successful splice leaves no temp files behind" "[0, 0]" \
    "$(cat "$WORK/ts3c.out")"

# --- A splice that cannot replace the file keeps the recovery copy ----------
# Making the target read-only makes the copy back fail after the temp
# already holds the complete new content - the one case where the temp is
# deliberately NOT deleted.
#
# Whether that works at all depends on the environment rather than on this
# suite: root ignores the permission bits, and so do some filesystems and
# some Windows setups. Rather than guess from the platform, take a
# throwaway file away from ourselves and see whether we can still write to
# it; the test only means anything where the answer is no.
SP4_ALL=$(hash_range "$WORK/sp4.bin" 0 -1)
echo x > "$WORK/roprobe"
chmod 444 "$WORK/roprobe"
probe_writable=0
(echo x >> "$WORK/roprobe") 2>/dev/null && probe_writable=1
chmod 644 "$WORK/roprobe"
if [ "$probe_writable" = 1 ]; then
    echo "ok   - (skipped: read-only is not enforced here) a page of a file this user cannot write is read-only"
    echo "ok   - (skipped: read-only is not enforced here) a failed splice keeps a recovery copy"
    echo "ok   - (skipped: read-only is not enforced here) a failed splice leaves the file alone"
else
    chmod 444 "$WORK/sp4.bin"
    cat > "$WORK/ts3d.vim" <<EOF
$(printf "$PAGEDW")
let dir = fnamemodify(tempname(), ':h')
HexPairOpen $WORK/sp4.bin 2
let ro = &l:readonly
call append(1, 'aa bb cc')
let refused = ''
try
  write
catch
  let refused = 'refused'
endtry
let temps = len(glob(dir . '/*', 0, 1))
let failed = ''
try
  write!
catch
  let failed = 'failed'
endtry
let kept = filter(glob(dir . '/*', 0, 1), 'getfsize(v:val) == 5003')
call writefile([string([ro, refused, temps]), string([failed, len(kept), &l:modified])], '$WORK/ts3d.out')
qa!
EOF
    "$HEXPAIR_VIM" -es -u NONE -S "$WORK/ts3d.vim" < /dev/null
    check "a page of a file this user cannot write is read-only" \
        "[1, 'refused', 0]" "$(sed -n 1p "$WORK/ts3d.out")"
    check "a failed splice keeps a recovery copy" "['failed', 1, 1]" \
        "$(sed -n 2p "$WORK/ts3d.out")"
    check "a failed splice leaves the file alone" "$SP4_ALL" \
        "$(hash_range "$WORK/sp4.bin" 0 -1)"
    chmod 644 "$WORK/sp4.bin"
fi

# --- Emptying the only page leaves a view with nothing to show --------------
cat > "$WORK/ts3e.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/sp5.bin 1
2delete _
write
call writefile([getline(1), string([&l:modified, line('\$'), b:hexpair_page_totalpages]), s:nothing], '$WORK/ts3e.out')
qa!
EOF
sed -i 's/, s:nothing//' "$WORK/ts3e.vim"
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/ts3e.vim" < /dev/null
check_path "emptying the file leaves a banner saying so" \
    "\" hexpair: $WORK/sp5.bin is empty" "$(sed -n 1p "$WORK/ts3e.out")"
check "emptying the file leaves no pages" "[0, 2, 0]" "$(sed -n 2p "$WORK/ts3e.out")"
check "the emptied file really is empty"  "0" "$(file_size "$WORK/sp5.bin")"

# --- The resize prompt says what it is about to do --------------------------
# confirm() cannot run under this harness, so the message it asks is
# tested on its own, like the version-gate and page-size messages.
cat > "$WORK/ts3f.vim" <<EOF
source $PLUGIN
call writefile(split(HexPairPagedResizeMessage(-16, 5000, 5000), "\n") + split(HexPairPagedResizeMessage(3, 5000, 900), "\n"), '$WORK/ts3f.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/ts3f.vim" < /dev/null
check "the resize prompt names the delta" \
    "hexpair: this page changed length by -16 bytes." "$(sed -n 1p "$WORK/ts3f.out")"
check "shortening says the file is rewritten" \
    "Shortening a file means writing it afresh, so all 5000 of its bytes are rewritten (5000 -> 4984 bytes)." \
    "$(sed -n 2p "$WORK/ts3f.out")"
check "growing says only what moves is written" \
    "Everything after this page has to move, so 900 of the file's 5000 bytes are rewritten in place - the rest is not touched, and no second copy of it is made (5000 -> 5003 bytes)." \
    "$(sed -n 5p "$WORK/ts3f.out")"

# --- The help file must produce tags ---------------------------------------
# :helptags aborts on the FIRST duplicate tag and writes none at all, so
# one repeated tag costs the plugin its whole :help - after exactly the
# `vim -c 'helptags ALL'` the README tells users to run.
cat > "$WORK/th1.vim" <<EOF
let result = 'ok'
try
  execute 'helptags' fnameescape('$WORK/doctags')
catch
  let result = v:exception
endtry
call writefile([result, string(len(readfile('$WORK/doctags/tags')))], '$WORK/th1.out')
qa!
EOF
mkdir -p "$WORK/doctags"
cp "$ROOT/doc/hexpair.txt" "$WORK/doctags/"
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/th1.vim" < /dev/null
check "helptags accepts the help file" "ok" "$(sed -n 1p "$WORK/th1.out")"
check "helptags found the plugin's tags" "1" \
    "$(test "$(sed -n 2p "$WORK/th1.out")" -gt 30 && echo 1 || echo 0)"

# --- A real page STRADDLING 4 GiB, where the offset column widens mid-page --
# Pages are plain fixed-size slices, so nothing stops one from spanning the
# point where xxd goes from eight offset digits to nine. 1536 is a multiple
# of the 16-byte line width but not a divisor of 4 GiB, so page 2796203 of
# this sparse fixture carries both widths - line 65 eight digits, line 66
# nine - and every column must follow the line it is on, not the page.
HUGE_HEAD=$(hash_range "$WORK/huge.bin" 0 4096)
cat > "$WORK/t4g.vim" <<EOF
source $PLUGIN
let g:hexpair_page_size = 1536
let g:hexpair_page_confirm = 0
HexPairOpen $WORK/huge.bin 2796203
let widths = string([HexPairPagedLineHexStart(65), HexPairPagedLineHexStart(66)])
call cursor(66, 12)
let mapped = HexPairPagedByteOffset()
HexPairGoAscii
let jumped = string([line('.'), col('.')])
call cursor(66, 12)
call setline(66, substitute(getline(66), '00 01', 'fe ed', ''))
write
call writefile([getline(65), getline(66), widths, string(mapped), jumped, string([&l:modified, b:hexpair_page_total])], '$WORK/t4g.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/t4g.vim" < /dev/null
check "the line before the 4 GiB mark keeps eight offset digits" \
    "fffffff0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00  ................" \
    "$(sed -n 1p "$WORK/t4g.out")"
check "the line after it has nine, and was patched in place" \
    "100000000: fe ed 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f  ................" \
    "$(sed -n 2p "$WORK/t4g.out")"
check "the hex column follows each line's own offset width" "[11, 12]" \
    "$(sed -n 3p "$WORK/t4g.out")"
check "the cursor maps to the absolute offset"  "4294967296" "$(sed -n 4p "$WORK/t4g.out")"
check "the column jump follows the wider line" "[66, 61]" "$(sed -n 5p "$WORK/t4g.out")"
check "patching across the boundary left the length alone" "[0, 4294971392]" \
    "$(sed -n 6p "$WORK/t4g.out")"
check "patching across the boundary left the head alone" "$HUGE_HEAD" \
    "$(hash_range "$WORK/huge.bin" 0 4096)"

# --- The column jumps work in a paged buffer -------------------------------
# They used to be keyed on the whole-file mode's active flag, which a paged
# buffer never sets, so :HexPairGoAscii and friends did nothing there.
cat > "$WORK/tg1.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/jump1.bin 2
call cursor(2, 14)
HexPairGoAscii
let ascii = string([line('.'), col('.'), strpart(getline('.'), col('.') - 1, 1)])
HexPairSwap
let back = string([line('.'), col('.'), strpart(getline('.'), col('.') - 1, 2)])
call cursor(2, 63)
HexPairGoHex
let hex = string([line('.'), col('.'), strpart(getline('.'), col('.') - 1, 2)])
normal! 1G
HexPairGoAscii
let banner = string([line('.'), col('.')])
call writefile([ascii, back, hex, banner], '$WORK/tg1.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tg1.vim" < /dev/null
check "GoAscii lands on the byte's ASCII character" "[2, 61, '.']" \
    "$(sed -n 1p "$WORK/tg1.out")"
check "Swap comes back to the same byte"            "[2, 14, '01']" \
    "$(sed -n 2p "$WORK/tg1.out")"
check "GoHex lands on the byte's hex digits"        "[2, 20, '03']" \
    "$(sed -n 3p "$WORK/tg1.out")"
check "a jump from the banner line does nothing"    "[1, 1]" \
    "$(sed -n 4p "$WORK/tg1.out")"

# --- 'paste' is managed in a paged buffer too ------------------------------
cat > "$WORK/tg2.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/paste1.bin 1
let inpage = &paste
new
let outside = &paste
wincmd p
let back = &paste
call writefile([string([inpage, outside, back])], '$WORK/tg2.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tg2.vim" < /dev/null
check "'paste' is on in a paged buffer and restored outside it" "[1, 0, 1]" \
    "$(cat "$WORK/tg2.out")"

# --- Opening a page never abandons a modified buffer -----------------------
# :HexPairOpen leaves the current buffer alone; Vim's own refusal to
# abandon unsaved work must survive, whatever the entry point does.
cat > "$WORK/tx1.vim" <<EOF
$(printf "$PAGEDW")
enew
call setline(1, 'precious unsaved work')
let refused = ''
try
  HexPairOpen $WORK/abandon1.bin 1
catch
  let refused = v:exception =~# 'E37' ? 'refused' : v:exception
endtry
call writefile([refused, string([getline(1), get(b:, 'hexpair_page_active', 0)])], '$WORK/tx1.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tx1.vim" < /dev/null
check "opening a page refuses to abandon a modified buffer" "refused" \
    "$(sed -n 1p "$WORK/tx1.out")"
check "the modified buffer is left untouched" "['precious unsaved work', 0]" \
    "$(sed -n 2p "$WORK/tx1.out")"

# --- A buffer-local 'undolevels' cannot keep the history alive -------------
# 'undolevels' is global-local: clearing only the global value would leave
# the history intact for exactly the users who set a buffer-local one.
cat > "$WORK/tx2.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/ulocal1.bin 1
setlocal undolevels=500
HexPairPageNext
let fresh = getline(2)
silent! undo
let kept = getline(2) ==# fresh
call setline(2, substitute(getline(2), '00 01', 'aa bb', ''))
silent! undo
let restored = getline(2) ==# fresh
call writefile([string([kept, restored, &l:undolevels])], '$WORK/tx2.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tx2.vim" < /dev/null
check "a buffer-local 'undolevels' is restored, history still cleared" \
    "[1, 1, 500]" "$(cat "$WORK/tx2.out")"

# ===========================================================================
# Where a toggled buffer's pages come from
# ===========================================================================

# --- An unnamed buffer is paged from a spill of its own content ------------
# `cat x | vim -` has no file to read pages from, and by the time hex mode
# can be asked for, the content is fully in memory anyway.
cat > "$WORK/tp1.vim" <<EOF
$(printf "$HEX")
enew
call setline(1, ['first line', 'second line', 'third line'])
HexPairToggle
let state = string([get(b:, 'hexpair_page_active', 0), b:hexpair_page_totalpages, b:hexpair_page_total])
call writefile([getline(1), getline(2), state], '$WORK/tp1.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tp1.vim" < /dev/null
check "an unnamed buffer names itself in the banner" \
    "\" hexpair: page 1/1  bytes 1-34 of 34  [unnamed buffer]" \
    "$(sed -n 1p "$WORK/tp1.out")"
check "and its bytes are dumped" \
    "00000000: 66 69 72 73 74 20 6c 69 6e 65 0a 73 65 63 6f 6e  first line.secon" \
    "$(sed -n 2p "$WORK/tp1.out")"
check "one page, 34 bytes" "[1, 1, 34]" "$(sed -n 3p "$WORK/tp1.out")"

# --- A modified file-backed buffer is refused ------------------------------
# The buffer and the file disagree. Paging from disk would hide the edits;
# paging from memory would let a page-range write drop every edit outside
# the visible page. Both lose data quietly, so neither is done.
cat > "$WORK/tp2.vim" <<EOF
$(printf "$HEX")
call setline(1, 'tampered')
redir => msg
HexPairToggle
redir END
call writefile([string([msg =~# 'unwritten changes', get(b:, 'hexpair_page_active', 0), &l:buftype, getline(1)])], '$WORK/tp2.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/src1.bin" -S "$WORK/tp2.vim" < /dev/null
check "a modified file-backed buffer is refused, and left alone" \
    "[1, 0, '', 'tampered']" "$(cat "$WORK/tp2.out")"
check "and the file is untouched" \
    "00000000: 00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f  ................" \
    "$("$HEXPAIR_XXD" -s 0 -l 16 -g 1 "$WORK/src1.bin")"

# --- :HexPairGoOffset jumps to a byte, wherever it is ----------------------
# Pages are fixed-size slices, so the page holding an offset is a division.
cat > "$WORK/tp3.vim" <<EOF
$(printf "$HEX")
HexPairToggle
HexPairGoOffset 2000
let dec = string([b:hexpair_page_index, HexPairPagedByteOffset()])
HexPairGoOffset 0x400
let hex = string([b:hexpair_page_index, HexPairPagedByteOffset()])
redir => m1
silent HexPairGoOffset 99999
redir END
redir => m2
silent HexPairGoOffset zz
redir END
redir => m3
silent HexPairGoOffset 0
redir END
HexPairToggle
HexPairGoOffset 100
let intext = string([b:hexpair_view, b:hexpair_page_index, line('.'), col('.')])
call writefile([dec, hex, string([m1 =~# 'outside the file', m2 =~# 'not a byte position', m3 =~# 'start at 1']), intext], '$WORK/tp3.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/off1.bin" -S "$WORK/tp3.vim" < /dev/null
check "byte 2000 is offset 1999 - positions are 1-based, like the banner" \
    "[3, 1999]" "$(sed -n 1p "$WORK/tp3.out")"
check "and so is a 0x one"                     "[1, 1023]" "$(sed -n 2p "$WORK/tp3.out")"
check "out of range, non-numeric and zero are all refused" "[1, 1, 1]" \
    "$(sed -n 3p "$WORK/tp3.out")"
check "the jump keeps you in the view you were in" "['text', 0, 3, 89]" \
    "$(sed -n 4p "$WORK/tp3.out")"

check "HexPairPagedOffsetError() accepts what is in range" "''" \
    "$("$HEXPAIR_VIM" -es -u NONE -c "source $PLUGIN" -c "call writefile([string(HexPairPagedOffsetError(0, 1))], '$WORK/tp4.out')" -c 'qa!' < /dev/null; cat "$WORK/tp4.out")"

# --- Editing and writing several pages of one file, one after another ------
# Each :w patches the page on screen; the pages you never opened keep their
# bytes. This is the ordinary way to work on a multi-page file, so it is
# asserted end to end: three pages edited, including the short last one, and
# every other byte of the file compared against what it was.
cp "$WORK/multi.bin" "$WORK/multi.before"
cat > "$WORK/tm1.vim" <<EOF
$(printf "$HEX")
HexPairOpen $WORK/multi.bin 1
call setline(2, substitute(getline(2), '^\(.\{10\}\)..', '\1aa', ''))
write
let p1 = &l:modified
HexPairPageGoto 5
call setline(2, substitute(getline(2), '^\(.\{10\}\)..', '\1bb', ''))
write
let p5 = &l:modified
HexPairPageGoto 10
call setline(2, substitute(getline(2), '^\(.\{10\}\)..', '\1cc', ''))
write
let p10 = [&l:modified, b:hexpair_page_len, b:hexpair_page_total]
call writefile([string([p1, p5]), string(p10)], '$WORK/tm1.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tm1.vim" < /dev/null
check "each page write clears 'modified'" "[0, 0]" "$(sed -n 1p "$WORK/tm1.out")"
check "the short last page writes too, file size unchanged" "[0, 392, 5000]" \
    "$(sed -n 2p "$WORK/tm1.out")"
check "page 1's byte was patched"  "00000000: aa" "$("$HEXPAIR_XXD" -s 0 -l 1 -g 1 "$WORK/multi.bin" | cut -c1-12)"
check "page 5's byte was patched"  "00000800: bb" "$("$HEXPAIR_XXD" -s 2048 -l 1 -g 1 "$WORK/multi.bin" | cut -c1-12)"
check "page 10's byte was patched" "00001200: cc" "$("$HEXPAIR_XXD" -s 4608 -l 1 -g 1 "$WORK/multi.bin" | cut -c1-12)"
check "the file kept its length" "5000" "$(file_size "$WORK/multi.bin")"
check "everything between the edits is untouched" \
    "$(hash_range "$WORK/multi.before" 1 2047)" "$(hash_range "$WORK/multi.bin" 1 2047)"
check "and after them too" \
    "$(hash_range "$WORK/multi.before" 4609 -1)" "$(hash_range "$WORK/multi.bin" 4609 -1)"

# --- Entering hex mode from a buffer with unsaved changes is refused -------
# Not a limitation on writing: it is the one transition that cannot be made
# without losing something. The buffer holds whole-file edits, the hex view
# holds one page, and a page-range write would drop every edit outside it.
# Once in hex mode, editing and writing any page works (above).
cat > "$WORK/tm2.vim" <<EOF
$(printf "$HEX")
call setline(1, 'edited in the plain view')
redir => msg
HexPairToggle
redir END
let refused = [msg =~# 'unwritten changes', msg =~# ':HexPairOpen', get(b:, 'hexpair_page_active', 0)]
write
HexPairToggle
let after = [get(b:, 'hexpair_page_active', 0), b:hexpair_page_totalpages]
call writefile([string(refused), string(after)], '$WORK/tm2.out')
qa!
EOF
"$HEXPAIR_VIM" -es -b -u NONE "$WORK/multi2.bin" -S "$WORK/tm2.vim" < /dev/null
check "a dirty buffer is refused, and told both ways out" "[1, 1, 0]" \
    "$(sed -n 1p "$WORK/tm2.out")"
check "writing it first makes the toggle work"            "[1, 10]" \
    "$(sed -n 2p "$WORK/tm2.out")"

# --- Every command has a way to be mapped, and the offset parser works -----
# The <Plug> targets are the plugin's whole key surface (it defines no
# mappings), so a command that has none cannot be bound to a key at all.
cat > "$WORK/tk1.vim" <<EOF
source $PLUGIN
let want = ['(HexPairToggle)', '(HexPairGoHex)', '(HexPairGoAscii)', '(HexPairSwap)', '(HexPairRefresh)', '(HexPairPageNext)', '(HexPairPagePrev)', '(HexPairPageGoto)', '(HexPairPageGotoForce)', '(HexPairGoOffset)', '(HexPairGoOffsetForce)', '(HexPairPages)']
let listed = execute('nmap')
let missing = filter(copy(want), 'stridx(listed, "<Plug>" . v:val) < 0')
let parsed = [HexPairPagedParseOffsetInput(''), HexPairPagedParseOffsetInput('1234'), HexPairPagedParseOffsetInput('0x10'), HexPairPagedParseOffsetInput('zz'), HexPairPagedParseOffsetInput('ff'), HexPairPagedParseOffsetInput('+16'), HexPairPagedParseOffsetInput('-0x10')]
call writefile([string(missing), string(parsed[0]), string(parsed[1]), string(parsed[2]), parsed[3].msg, parsed[4].msg, string([parsed[5], parsed[6]])], '$WORK/tk1.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tk1.vim" < /dev/null
check "every command has a <Plug> target" "[]" "$(sed -n 1p "$WORK/tk1.out")"
check "an empty offset prompt cancels"    "{}" "$(sed -n 2p "$WORK/tk1.out")"
check "byte 1234 parses to offset 1233"   "{'offset': 1233}" "$(sed -n 3p "$WORK/tk1.out")"
check "byte 0x10 parses to offset 15"     "{'offset': 15}"   "$(sed -n 4p "$WORK/tk1.out")"
check "a non-position is reported" \
    "hexpair: not a byte position: 'zz' (decimal, or 0x for hex; byte 1 is the first, +N and -N step from here)" \
    "$(sed -n 5p "$WORK/tk1.out")"
# A bare "ff" reads as hex to a person and as the decimal 0 to str2nr(),
# so it is refused as a position rather than reported as "positions start
# at 1", which is a complaint about the wrong thing.
check "hex without the 0x is not a position either" \
    "hexpair: not a byte position: 'ff' (decimal, or 0x for hex; byte 1 is the first, +N and -N step from here)" \
    "$(sed -n 6p "$WORK/tk1.out")"
# A step is the one form where 0 means something ("stay here") and where
# the 1-based question does not arise at all.
check "a step parses as a step, in either base" \
    "[{'delta': 16}, {'delta': -16}]" "$(sed -n 7p "$WORK/tk1.out")"

# --- Piped input that Vim may already have transcoded is flagged -----------
# A named file can be re-read with ++bin; piped input cannot, so if the
# buffer was not read in binary mode its bytes may no longer be the input's
# and nothing can put that back. Say so rather than present them as exact.
cat > "$WORK/tw7.vim" <<EOF
$(printf "$HEX")
enew
setlocal nobinary
call setline(1, ['some text'])
redir => msg
HexPairToggle
redir END
let warned = [msg =~# 'not read in binary mode', msg =~# 'vim -b -', get(b:, 'hexpair_page_active', 0)]
enew!
setlocal binary
call setline(1, ['some text'])
redir => msg2
HexPairToggle
redir END
call writefile([string(warned), string([msg2 =~# 'not read in binary mode', get(b:, 'hexpair_page_active', 0)])], '$WORK/tw7.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tw7.vim" < /dev/null
check "a non-binary piped buffer is flagged, and still opens" "[1, 1, 1]" \
    "$(sed -n 1p "$WORK/tw7.out")"
check "a binary one is not flagged"                          "[0, 1]" \
    "$(sed -n 2p "$WORK/tw7.out")"

# --- Two spellings of one path are one path --------------------------------
# A plain :w and a ':w {this view's own file}' must both patch the page.
# Getting that wrong sends a plain write down the save-as path, which
# copies the file over itself - and copying a file over itself truncates
# the source before a byte of it has been read. On Windows the two
# spellings differ in their separators and in the case of the drive letter
# without naming anything different, which is exactly how that happened.
cat > "$WORK/twp.vim" <<EOF
source $PLUGIN
let unix = [HexPairPagedSamePath('/a/b', '/a/b', 1, 0), HexPairPagedSamePath('/a/B', '/a/b', 1, 0), HexPairPagedSamePath('/a\b', '/a/b', 1, 0)]
let win = [HexPairPagedSamePath('C:\dir\f.bin', 'c:/dir/f.bin', 0, 1), HexPairPagedSamePath('C:\dir\f.bin', 'C:\dir\g.bin', 0, 1)]
let empty = [HexPairPagedSamePath('', '/a/b', 1, 0), HexPairPagedSamePath('/a/b', '', 1, 0)]
call writefile([string(unix), string(win), string(empty)], '$WORK/twp.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/twp.vim" < /dev/null
check "on Unix, case and backslashes are part of the name" "[1, 0, 0]" \
    "$(sed -n 1p "$WORK/twp.out")"
check "on Windows, separators and case are not"            "[1, 0]" \
    "$(sed -n 2p "$WORK/twp.out")"
check "an empty path names nothing"                        "[0, 0]" \
    "$(sed -n 3p "$WORK/twp.out")"

# The same thing end to end: naming the file longhand must patch the page,
# not copy the file over itself. A multi-page file, so a truncate-then-read
# would destroy it rather than happen to work out.
SAME_BEFORE=$(hash_range "$WORK/same1.bin" 1024 -1)
cat > "$WORK/twp2.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/same1.bin 2
call setline(2, substitute(getline(2), '00 01', 'de ad', ''))
execute 'write!' fnameescape('$WORK/./same1.bin')
call writefile([string([&l:modified, b:hexpair_page_total])], '$WORK/twp2.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/twp2.vim" < /dev/null
check "writing to the same file spelled longhand patches the page" "[0, 5000]" \
    "$(cat "$WORK/twp2.out")"
check "the file is intact, not truncated" "5000" "$(file_size "$WORK/same1.bin")"
check "the edit landed"    "00000200: de ad" "$("$HEXPAIR_XXD" -s 512 -l 2 -g 1 "$WORK/same1.bin" | cut -c1-15)"
check "the rest is intact" "$SAME_BEFORE" "$(hash_range "$WORK/same1.bin" 1024 -1)"

# --- A Visual selection is mirrored in the other column --------------------
# Vim highlights what is selected; hexpair adds the same BYTES on the other
# side of the dump. Visual mode cannot be driven under `vim -es`, so what
# is tested is the function that works out where the counterpart is - the
# same split the version-gate and prompt-parsing functions use.
cat > "$WORK/tv1.vim" <<EOF
$(printf "$HEX")
HexPairOpen $WORK/vis1.bin 1
" the 2nd to the 5th byte of line 2, selected in the HEX column
let inhex = HexPairPagedSelectionPositions([0,2,14,0], [0,2,23,0], 'v', 2, 2)
" three bytes selected in the ASCII column, mirrored back as hex pairs
let inascii = HexPairPagedSelectionPositions([0,2,61,0], [0,2,63,0], 'v', 2, 2)
" across two lines: from byte 14 of line 2 to byte 1 of line 3
let across = HexPairPagedSelectionPositions([0,2,50,0], [0,3,14,0], 'v', 2, 3)
" linewise takes whole lines
let linewise = HexPairPagedSelectionPositions([0,2,1,0], [0,2,1,0], 'V', 2, 2)
" the banner contributes nothing
let banner = HexPairPagedSelectionPositions([0,1,1,0], [0,2,14,0], 'v', 1, 2)
call writefile([string(inhex), string(inascii), string(across), string(linewise), string(banner)], '$WORK/tv1.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tv1.vim" < /dev/null
check "a hex selection mirrors into the ASCII column" "[[2, 61, 4]]" \
    "$(sed -n 1p "$WORK/tv1.out")"
check "an ASCII selection mirrors into the hex column" "[[2, 14, 8]]" \
    "$(sed -n 2p "$WORK/tv1.out")"
check "a selection across lines mirrors line by line" \
    "[[2, 73, 3], [3, 60, 2]]" "$(sed -n 3p "$WORK/tv1.out")"
check "linewise takes the whole line's bytes" "[[2, 60, 16]]" \
    "$(sed -n 4p "$WORK/tv1.out")"
check "a banner line contributes nothing"     "[[2, 60, 2]]" \
    "$(sed -n 5p "$WORK/tv1.out")"

# --- Inserting bytes moves only what is after them --------------------------
# The head of the file is not read, let alone written: the tail is shifted
# right in place with xxd and the page patched in. Asserted by hashing the
# head, the moved tail, and the file's new length.
IP1_HEAD=$(hash_range "$WORK/ip1.bin" 0 2048)
IP1_TAIL=$(hash_range "$WORK/ip1.bin" 2560 -1)
cat > "$WORK/tip1.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/ip1.bin 5
let dir = fnamemodify(tempname(), ':h')
let before = len(glob(dir . '/*', 0, 1))
call append(1, 'aa bb cc')
write
call writefile([string([&l:modified, b:hexpair_page_total, len(glob(dir . '/*', 0, 1)) - before]), getline(2)], '$WORK/tip1.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tip1.vim" < /dev/null
check "an insert grows the file, in place, and leaves no temp behind" \
    "[0, 5003, 0]" "$(sed -n 1p "$WORK/tip1.out")"
check "the inserted bytes open the page" \
    "00000800: aa bb cc 00 01 02 03 04 05 06 07 08 09 0a 0b 0c  ................" \
    "$(sed -n 2p "$WORK/tip1.out")"
check "the file really grew"                "5003"      "$(file_size "$WORK/ip1.bin")"
check "everything before the page is byte-identical" "$IP1_HEAD" \
    "$(hash_range "$WORK/ip1.bin" 0 2048)"
check "everything after it moved intact"    "$IP1_TAIL" \
    "$(hash_range "$WORK/ip1.bin" 2563 -1)"

# --- Appending to the last page touches nothing else ------------------------
# The tail is empty there, so there is nothing to move at all: xxd writes
# the longer page straight past the old end of the file.
IP2_HEAD=$(hash_range "$WORK/ip2.bin" 0 4608)
cat > "$WORK/tip2.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/ip2.bin 10
call append(line('\$') - 1, 'de ad be ef')
write
call writefile([string([&l:modified, b:hexpair_page_total, b:hexpair_page_len])], '$WORK/tip2.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tip2.vim" < /dev/null
check "appending to the last page" "[0, 5004, 396]" "$(cat "$WORK/tip2.out")"
check "the rest of the file is untouched" "$IP2_HEAD" \
    "$(hash_range "$WORK/ip2.bin" 0 4608)"
check "the appended bytes are at the end" \
    "00001388: de ad be ef" "$("$HEXPAIR_XXD" -s 5000 -l 4 -g 1 "$WORK/ip2.bin" | cut -c1-21)"

# --- A shrink still rewrites, and says so -----------------------------------
# Nothing in Vim or xxd can shorten a file except by writing it afresh.
IP3_HEAD=$(hash_range "$WORK/ip3.bin" 0 2048)
cat > "$WORK/tip3.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/ip3.bin 5
2delete _
write
call writefile([string([&l:modified, b:hexpair_page_total])], '$WORK/tip3.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tip3.vim" < /dev/null
check "a delete shrinks the file"        "[0, 4984]" "$(cat "$WORK/tip3.out")"
check "its head survives the rewrite"    "$IP3_HEAD" "$(hash_range "$WORK/ip3.bin" 0 2048)"

# ===========================================================================
# Paged mode: writing from the WINDOWED TEXT VIEW
# ===========================================================================
# The same write paths as above, but reached from the other view, which
# sources the page's bytes completely differently: the hex view strips a
# dump, the text view takes the buffer's lines as they are. That round trip
# goes through readfile()/writefile() in binary mode, because a NUL byte is
# stored as a NL *inside* a Vim line and getline() alone cannot express the
# difference. The fixture holds every byte value, NUL and 0x0a included, so
# it exercises exactly that.
#
# Page 2 at 512 bytes/page is file bytes 512-1023, values 0-255 twice. The
# two 0x0a bytes in it (at 522 and 778) split the view into three lines:
# body line 1 is bytes 512-521, line 2 is 523-777, line 3 is 779-1023.

# --- No edit at all must still round-trip every byte -----------------------
TV1_ALL=$(hash_range "$WORK/tv1.bin" 0 -1)
cat > "$WORK/ttv1.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/tv1.bin 2
HexPairToggle
let view = b:hexpair_view
let body = line('\$') - 2
setlocal modified
write
call writefile([string([view, body, &l:modified])], '$WORK/ttv1.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/ttv1.vim" < /dev/null
check "the text view holds the page's bytes as three lines" "['text', 3, 0]" \
    "$(cat "$WORK/ttv1.out")"
check "writing it back unedited changes nothing" "$TV1_ALL" \
    "$(hash_range "$WORK/tv1.bin" 0 -1)"
check "and does not change the length" "5000" "$(file_size "$WORK/tv1.bin")"

# --- A same-length edit patches the page in place, as in the hex view ------
TV2_HEAD=$(hash_range "$WORK/tv2.bin" 0 512)
TV2_TAIL=$(hash_range "$WORK/tv2.bin" 1024 -1)
TV2_REST=$(hash_range "$WORK/tv2.bin" 513 511)
cat > "$WORK/ttv2.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/tv2.bin 2
HexPairToggle
call setline(2, 'A' . strpart(getline(2), 1))
write
call writefile([string([&l:modified])], '$WORK/ttv2.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/ttv2.vim" < /dev/null
check "a text-view write clears 'modified'" "[0]" "$(cat "$WORK/ttv2.out")"
check "a text-view write keeps the file length" "5000" "$(file_size "$WORK/tv2.bin")"
check "it left the head untouched" "$TV2_HEAD" "$(hash_range "$WORK/tv2.bin" 0 512)"
check "it left the tail untouched" "$TV2_TAIL" "$(hash_range "$WORK/tv2.bin" 1024 -1)"
check "the rest of the page survived the round trip" "$TV2_REST" \
    "$(hash_range "$WORK/tv2.bin" 513 511)"
check "it changed exactly the edited byte" \
    "00000200: 41 01 02 03                                      A..." \
    "$("$HEXPAIR_XXD" -s 512 -l 4 -g 1 "$WORK/tv2.bin")"

# --- A growing edit moves the tail, from this view too ---------------------
TV3_HEAD=$(hash_range "$WORK/tv3.bin" 0 512)
TV3_TAIL=$(hash_range "$WORK/tv3.bin" 1024 -1)
TV3_REST=$(hash_range "$WORK/tv3.bin" 522 502)
cat > "$WORK/ttv3.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/tv3.bin 2
HexPairToggle
call setline(2, getline(2) . 'Z')
write
call writefile([string([&l:modified])], '$WORK/ttv3.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/ttv3.vim" < /dev/null
check "a growing text-view write clears 'modified'" "[0]" "$(cat "$WORK/ttv3.out")"
check "the file grew by the one byte inserted" "5001" "$(file_size "$WORK/tv3.bin")"
check "everything before the page is byte-identical" "$TV3_HEAD" \
    "$(hash_range "$WORK/tv3.bin" 0 512)"
check "everything after it is byte-identical, just moved" "$TV3_TAIL" \
    "$(hash_range "$WORK/tv3.bin" 1025 -1)"
check "the rest of the page moved up intact" "$TV3_REST" \
    "$(hash_range "$WORK/tv3.bin" 523 502)"
check "the inserted byte is where the edit put it" \
    "0000020a: 5a 0a 0b                                         Z.." \
    "$("$HEXPAIR_XXD" -s 522 -l 3 -g 1 "$WORK/tv3.bin")"

# --- An edited banner refuses the write: which lines are content is then
# --- guesswork, and in a page of raw bytes a leading '"' proves nothing ----
TV4_ALL=$(hash_range "$WORK/tv4.bin" 0 -1)
cat > "$WORK/ttv4.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/tv4.bin 2
HexPairToggle
call setline(1, getline(1) . ' tampered')
try
  write
  let outcome = 'written'
catch
  let outcome = 'refused'
endtry
call writefile([string([outcome, &l:modified])], '$WORK/ttv4.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/ttv4.vim" < /dev/null
check "an edited banner refuses the text-view write" "['refused', 1]" \
    "$(cat "$WORK/ttv4.out")"
check "and leaves the file exactly as it was" "$TV4_ALL" \
    "$(hash_range "$WORK/tv4.bin" 0 -1)"

# --- :HexPairPages says which byte the cursor is on ------------------------
# In the form :HexPairGoOffset and vimhex's @BYTE both take, so a position
# can be written down and gone back to. 1-based, like the banner's range.
cat > "$WORK/tcb.vim" <<EOF
$(printf "$PAGEDW")
HexPairOpen $WORK/pos1.bin 3
call cursor(4, 20)
let inhex = s:PagesTextProbe()
normal! 1G
let banner = s:PagesTextProbe()
HexPairToggle
call cursor(3, 5)
let intext = s:PagesTextProbe()
call writefile([inhex, banner, intext], '$WORK/tcb.out')
qa!
EOF
sed -i 's/s:PagesTextProbe()/HexPairPagedReport()/g' "$WORK/tcb.vim"
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tcb.vim" < /dev/null
check_path "the cursor byte is reported in hex and decimal" \
    "hexpair: page 3 of 10, offsets 1025-1536 of total 5000 bytes ($WORK/pos1.bin); cursor on byte 0x424 (1060)" \
    "$(sed -n 1p "$WORK/tcb.out")"
check_path "a banner line has no byte to report" \
    "hexpair: page 3 of 10, offsets 1025-1536 of total 5000 bytes ($WORK/pos1.bin)" \
    "$(sed -n 2p "$WORK/tcb.out")"
check_path "the text view reports it too" \
    "hexpair: page 3 of 10, offsets 1025-1536 of total 5000 bytes ($WORK/pos1.bin); cursor on byte 0x410 (1040)" \
    "$(sed -n 3p "$WORK/tcb.out")"

# ===========================================================================
# The whole-page scan
# ===========================================================================
# Validation, stripping and the cursor's byte all come from ONE pass that
# regexes the whole page at once instead of walking it line by line. The
# per-line rule (HexPairPagedStripLine()) stays the reference, so the two
# have to agree - and they can only disagree on a page of real size, where
# a regex over the whole of it stops behaving like the same regex over one
# line (a negated collection matches the end-of-line whatever is listed in
# it, which turned up as a page validating at 2000 lines and failing at
# 4000). Hence a fixture measured in thousands of lines, not in ten.

# --- The two rules agree, on a full-size page ------------------------------
cat > "$WORK/tsc1.vim" <<EOF
source $PLUGIN
HexPairOpen $WORK/scan1.bin
let perline = map(getline(1, '\$'), 'HexPairPagedStripLine(v:val)')
let whole = HexPairPagedScanLines()
call writefile([string([line('\$'), whole ==# perline, HexPairPagedValidate()])], '$WORK/tsc1.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tsc1.vim" < /dev/null
check "the whole-page scan says what the per-line rule says" \
    "[6252, 1, {}]" "$(cat "$WORK/tsc1.out")"

# --- A clean page of that size is not rejected, and survives a write -------
# An unedited page written back must reproduce the file bit for bit: the
# scan, the strip and the patch are the whole round trip.
SCAN2_ALL=$(hash_range "$WORK/scan2.bin" 0 -1)
cat > "$WORK/tsc2.vim" <<EOF
source $PLUGIN
HexPairOpen $WORK/scan2.bin
call cursor(5000, 11)
let at = HexPairPagedByteOffset()
write
call writefile([string([at, line('\$'), &l:modified])], '$WORK/tsc2.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tsc2.vim" < /dev/null
check "the cursor's byte on a deep line of a full page" \
    "[79968, 6252, 0]" "$(cat "$WORK/tsc2.out")"
check "writing a full page back unedited changes nothing" \
    "$SCAN2_ALL" "$(hash_range "$WORK/scan2.bin" 0 -1)"
check "and does not change its length" "100000" "$(file_size "$WORK/scan2.bin")"

# --- Lines the scan must not be thrown by ---------------------------------
# An empty line, a bare hex line with no offset column, and an indented
# one: each is a line the whole-page pass has to treat exactly as the
# per-line rule does - including leaving the NEXT line's offset column
# alone, which an anchor that consumes the line break does not.
cat > "$WORK/tsc3.vim" <<EOF
$(printf "$HEX")
HexPairOpen $WORK/scan3.bin 1
call append(2, ['', '41 42', '   43 44', '00000000: 45 46  EF'])
let payload = HexPairPagedScanLines()[2:6]
call cursor(4, 1)
let at = [HexPairPagedByteOffset()]
call cursor(7, 11)
call add(at, HexPairPagedByteOffset())
call writefile([string(payload), string(at), string(HexPairPagedValidate())], '$WORK/tsc3.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tsc3.vim" < /dev/null
check "an empty, a bare and an indented line strip as the rule says" \
    "['', '41 42', '43 44', ' 45 46', ' 10 11 12 13 14 15 16 17 18 19 1a 1b 1c 1d 1e 1f']" \
    "$(sed -n 1p "$WORK/tsc3.out")"
check "and the bytes on them count towards the cursor's offset" \
    "[16, 22]" "$(sed -n 2p "$WORK/tsc3.out")"
check "with nothing on them read as invalid" "{}" "$(sed -n 3p "$WORK/tsc3.out")"

# --- The position-mapping trace -------------------------------------------
# g:hexpair_debug is what a field report about a cursor landing on the
# wrong byte is diagnosed with, so it has to still exist and still say
# both directions of the mapping - and say nothing at all when it is off.
cat > "$WORK/tdbg.vim" <<EOF
$(printf "$HEX")
let g:hexpair_debug = 1
redir => on
silent HexPairOpen $WORK/dbg1.bin 2
silent HexPairGoOffset 600
silent call HexPairPagedByteOffset()
redir END
let g:hexpair_debug = 0
redir => off
silent HexPairGoOffset 700
silent call HexPairPagedByteOffset()
redir END
let lines = filter(split(on, "\n"), 'v:val =~# "^hexpair: "')
call writefile([string([len(lines) >= 3, lines[1], lines[2]]), string(split(off, "\n"))], '$WORK/tdbg.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tdbg.vim" < /dev/null
check "the trace says both directions of the mapping" \
    "[1, 'hexpair: byte 599 -> hex view line 7, column 32', 'hexpair: hex view line 7, column 32 -> byte 599 (page base 512, unedited page)']" \
    "$(sed -n 1p "$WORK/tdbg.out")"
check "and nothing at all when it is off" "[]" "$(sed -n 2p "$WORK/tdbg.out")"

# --- Both ways of counting the cursor's byte agree ------------------------
# An unedited page is canonical, so where the cursor's byte is follows from
# the layout and the page is not walked at all. The moment it is edited it
# has to be counted from what is actually on the lines. Same buffer, both
# paths - the difference is 'modified' alone, so they must answer the same.
cat > "$WORK/tcbo.vim" <<EOF
$(printf "$HEX")
HexPairOpen $WORK/cbo1.bin 3
let fast = []
let slow = []
for pos in [[2, 11], [2, 12], [2, 14], [5, 30], [5, 58], [5, 61], [5, 63], [33, 11]]
  call cursor(pos[0], pos[1])
  setlocal nomodified
  call add(fast, HexPairPagedByteOffset())
  setlocal modified
  call add(slow, HexPairPagedByteOffset())
endfor
setlocal nomodified
call writefile([string(fast), string(slow)], '$WORK/tcbo.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tcbo.vim" < /dev/null
check "the canonical byte and the counted byte are the same byte" \
    "$(sed -n 1p "$WORK/tcbo.out")" "$(sed -n 2p "$WORK/tcbo.out")"
# The gap between the columns (5, 58) is the odd one out: the cursor is
# past the line's last hex digit, and both paths clamp it to that last
# byte (1087) rather than counting it as the first of the next line.
check "and it is the byte the layout says" \
    "[1024, 1024, 1025, 1078, 1087, 1073, 1075, 1520]" "$(sed -n 1p "$WORK/tcbo.out")"

# ===========================================================================
# The column ruler (g:hexpair_ruler)
# ===========================================================================
# One more line between the banner and the dump, numbering the columns.
# It carries no bytes (it starts with a '"', like the banners), but it does
# shift every dump line down by one - and turning a line number into a byte
# offset is arithmetic that has to know about it.
RULER_ALL=$(hash_range "$WORK/ruler1.bin" 0 -1)
cat > "$WORK/trul.vim" <<EOF
$(printf "$HEX")
let g:hexpair_ruler = 1
HexPairOpen $WORK/ruler1.bin 2
let ruler = getline(2)
let dump = getline(3)
" every column of the ruler must sit exactly over the byte it numbers:
" byte 7 and byte 15 in the hex column, and the ASCII column's own run
let hexstart = HexPairPagedLineHexStart(3)
let aligned = [stridx(ruler, '07') + 1 == hexstart + 7 * 3, stridx(ruler, '0f') + 1 == hexstart + 15 * 3, strpart(ruler, hexstart + 16 * 3, 16), stridx(dump, ' 07') + 2 == hexstart + 7 * 3]
let opened = [line('.'), col('.'), HexPairPagedByteOffset()]
HexPairGoOffset 600
let jumped = [line('.'), col('.'), HexPairPagedByteOffset() + 1]
HexPairToggle
let intext = [line('\$'), getline(1) ==# b:hexpair_banner_top]
HexPairToggle
let back = [getline(2)[0:8], HexPairPagedByteOffset() + 1, line('\$')]
write
call writefile([string(aligned), string(opened), string(jumped), string(intext), string(back), string(HexPairPagedValidate())], '$WORK/trul.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/trul.vim" < /dev/null
check "the ruler numbers the columns it sits over" "[1, 1, '0123456789abcdef', 1]" \
    "$(sed -n 1p "$WORK/trul.out")"
check "a page with a ruler opens on its first byte" "[3, 11, 512]" \
    "$(sed -n 2p "$WORK/trul.out")"
check "and byte 600 is still where the layout says" "[8, 32, 600]" \
    "$(sed -n 3p "$WORK/trul.out")"
check "the text view has no ruler, just the banners" "[5, 1]" \
    "$(sed -n 4p "$WORK/trul.out")"
check "and the way back rebuilds it" "['\"        ', 600, 35]" \
    "$(sed -n 5p "$WORK/trul.out")"
check "the ruler is not read as hex payload" "{}" "$(sed -n 6p "$WORK/trul.out")"
check "and contributes no bytes to the write" "$RULER_ALL" \
    "$(hash_range "$WORK/ruler1.bin" 0 -1)"

# ===========================================================================
# HexPairStatus() for 'statusline'
# ===========================================================================
# Empty outside hexpair buffers, so it can sit in the statusline
# unconditionally; and it must agree with :HexPairPages about the byte
# while the page is unedited, since one is what you see and the other is
# what you ask.
cat > "$WORK/tst.vim" <<EOF
$(printf "$HEX")
let plain = HexPairStatus()
HexPairOpen $WORK/status1.bin 3
call cursor(4, 20)
let hex = HexPairStatus()
let agrees = HexPairPagedReport() =~# 'cursor on byte 0x424 '
normal! 1G
let banner = HexPairStatus()
call cursor(4, 20)
setlocal modified
let edited = HexPairStatus()
setlocal nomodified
HexPairToggle
call cursor(3, 5)
let text = HexPairStatus()
call writefile([string([plain, hex, agrees, banner, edited, text])], '$WORK/tst.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tst.vim" < /dev/null
check "the statusline says view, page and byte, and nothing elsewhere" \
    "['', 'hex 3/10 @0x424', 1, 'hex 3/10', 'hex 3/10+ @0x424', 'txt 3/10 @0x410']" \
    "$(cat "$WORK/tst.out")"

# ===========================================================================
# What a Visual selection covers
# ===========================================================================
# Visual mode cannot be driven under `vim -es`, so the geometry is called
# with the two ends and the mode passed in - the same split
# HexPairPagedSelectionPositions() already uses for the mirror highlight.
cat > "$WORK/tsel.vim" <<EOF
$(printf "$HEX")
HexPairOpen $WORK/sel1.bin 3
let out = []
call add(out, string(HexPairPagedSelectionBytes([0, 3, 11, 0], [0, 4, 14, 0], 'v')))
call add(out, HexPairPagedSelectionText(HexPairPagedSelectionBytes([0, 3, 11, 0], [0, 4, 14, 0], 'v'), b:hexpair_page_total))
call add(out, HexPairPagedSelectionText(HexPairPagedSelectionBytes([0, 3, 1, 0], [0, 3, 1, 0], 'V'), b:hexpair_page_total))
call add(out, HexPairPagedSelectionText(HexPairPagedSelectionBytes([0, 3, 11, 0], [0, 5, 20, 0], "\<C-V>"), b:hexpair_page_total))
call add(out, HexPairPagedSelectionText(HexPairPagedSelectionBytes([0, 1, 1, 0], [0, 1, 5, 0], 'v'), b:hexpair_page_total))
" a selection made backwards covers the same bytes as one made forwards
call add(out, string(HexPairPagedSelectionBytes([0, 4, 14, 0], [0, 3, 11, 0], 'v') ==# HexPairPagedSelectionBytes([0, 3, 11, 0], [0, 4, 14, 0], 'v')))
HexPairToggle
call add(out, HexPairPagedSelectionText(HexPairPagedSelectionBytes([0, 2, 1, 0], [0, 2, 16, 0], 'v'), b:hexpair_page_total))
call add(out, HexPairPagedSelectionText(HexPairPagedSelectionBytes([0, 2, 1, 0], [0, 2, 1, 0], 'V'), b:hexpair_page_total))
call writefile(out, '$WORK/tsel.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tsel.vim" < /dev/null
check "a charwise selection is one run of bytes" \
    "{'first': 1040, 'perline': 0, 'last': 1057, 'lines': 2, 'count': 18}" \
    "$(sed -n 1p "$WORK/tsel.out")"
check "and says so 1-based, in hex and decimal" \
    "hexpair: 18 bytes selected, 1041-1058 (0x411-0x422) of 5000" \
    "$(sed -n 2p "$WORK/tsel.out")"
check "a linewise selection is the line's bytes" \
    "hexpair: 16 bytes selected, 1041-1056 (0x411-0x420) of 5000" \
    "$(sed -n 3p "$WORK/tsel.out")"
# Blockwise bytes are not one run, so the count is what it leads with.
check "a blockwise selection counts its columns on every line" \
    "hexpair: 12 bytes selected in 3 lines (4 per line), 1041-1076 (0x411-0x434) of 5000" \
    "$(sed -n 4p "$WORK/tsel.out")"
check "banner lines cover no bytes" "hexpair: the selection covers no bytes" \
    "$(sed -n 5p "$WORK/tsel.out")"
check "and which end it was made from makes no difference" "1" \
    "$(sed -n 6p "$WORK/tsel.out")"
check "in the text view a column is a byte" \
    "hexpair: 16 bytes selected, 1025-1040 (0x401-0x410) of 5000" \
    "$(sed -n 7p "$WORK/tsel.out")"
# A line break is a byte of the file like any other, so a linewise
# selection of a 10-byte line covers 11.
check "and a linewise selection there takes the line break with it" \
    "hexpair: 11 bytes selected, 1025-1035 (0x401-0x40b) of 5000" \
    "$(sed -n 8p "$WORK/tsel.out")"

# --- A page can be named as a step, or as the last one ---------------------
# The same parser serves :HexPairPageGoto and the <Plug> prompt, so "$"
# and "+2" work wherever a page number does - including through the vimhex
# wrapper, which hands its PAGE argument straight to the command.
cat > "$WORK/tpg.vim" <<EOF
$(printf "$HEX")
HexPairOpen $WORK/pgoto1.bin 3
let parsed = [HexPairPagedParsePageInput('\$'), HexPairPagedParsePageInput('+2'), HexPairPagedParsePageInput('-2'), HexPairPagedParsePageInput('7')]
let resolved = map(copy(parsed), 'HexPairPagedResolvePage(v:val, 3, 10)')
HexPairPageGoto +2
let stepped = b:hexpair_page_index + 1
HexPairPageGoto -1
let back = b:hexpair_page_index + 1
HexPairPageGoto \$
let last = b:hexpair_page_index + 1
redir => msg
silent! HexPairPageGoto +9
redir END
call writefile([string(parsed), string(resolved), string([stepped, back, last, b:hexpair_page_index + 1]), substitute(msg, '^[\r\n]*', '', '')], '$WORK/tpg.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tpg.vim" < /dev/null
check "a step and a \$ parse as themselves" \
    "[{'last': 1}, {'delta': 2}, {'delta': -2}, {'page': 7}]" \
    "$(sed -n 1p "$WORK/tpg.out")"
check "and resolve against the page in view" "[10, 5, 1, 7]" \
    "$(sed -n 2p "$WORK/tpg.out")"
check "+2, -1 and \$ turn the pages they name" "[5, 4, 10, 10]" \
    "$(sed -n 3p "$WORK/tpg.out")"

# --- :HexPairOpen takes the same three forms ------------------------------
# A step counts from the first page, which is where opening starts.
cat > "$WORK/tpg2.vim" <<EOF
$(printf "$HEX")
HexPairOpen $WORK/pgoto1.bin \$
let last = b:hexpair_page_index + 1
bwipeout!
HexPairOpen $WORK/pgoto1.bin +2
let stepped = b:hexpair_page_index + 1
bwipeout!
HexPairOpen $WORK/pgoto1.bin
let default = b:hexpair_page_index + 1
call writefile([string([last, stepped, default])], '$WORK/tpg2.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tpg2.vim" < /dev/null
check "opening at \$, at a step, and by default" "[10, 3, 1]" \
    "$(cat "$WORK/tpg2.out")"
check "a step past the end is refused like any other missing page" \
    "hexpair: page 19 does not exist (file has 10 pages)" \
    "$(sed -n 4p "$WORK/tpg.out")"

# ===========================================================================
# A page that changed on disk within the same second
# ===========================================================================
# Size and mtime are all a portable Vim can see, and mtime is whole
# seconds: a writer that changes bytes in place, in the same second the
# page was read, is invisible to both. The page's own bytes are therefore
# hashed when it is read and again before it is patched. The helper below
# is that writer - it edits the file and puts the timestamps back, so
# nothing but the content differs.
cat > "$WORK/tamper.py" <<'PYEOF'
import os, sys
name = sys.argv[1]
st = os.stat(name)
with open(name, 'r+b') as f:
    f.seek(int(sys.argv[2]))
    f.write(b'\xff\xff\xff\xff')
os.utime(name, (st.st_atime, st.st_mtime))
PYEOF
cat > "$WORK/tdig.vim" <<EOF
$(printf "$HEX")
HexPairOpen $WORK/digest1.bin 2
let same = [getfsize('$WORK/digest1.bin'), getftime('$WORK/digest1.bin')]
call system('$PY $WORK/tamper.py $WORK/digest1.bin 600')
let unchanged = [getfsize('$WORK/digest1.bin') == same[0], getftime('$WORK/digest1.bin') == same[1]]
call setline(3, substitute(getline(3), '^\(.\{10\}\)..', '\1ee', ''))
let refused = ''
try
  write
catch /^hexpair:/
  let refused = 'refused'
endtry
call writefile([string(unchanged), refused, string(&l:modified)], '$WORK/tdig.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tdig.vim" < /dev/null
check "the tampering left the size and the timestamp alone" "[1, 1]" \
    "$(sed -n 1p "$WORK/tdig.out")"
check "but the page's own bytes give it away" "refused" \
    "$(sed -n 2p "$WORK/tdig.out")"
check "and the edit is still there to be saved elsewhere" "1" \
    "$(sed -n 3p "$WORK/tdig.out")"
check "the other writer's bytes are still on disk" "ffffffff" \
    "$("$HEXPAIR_XXD" -s 600 -l 4 -p "$WORK/digest1.bin")"

# ===========================================================================
# The data inspector
# ===========================================================================
# Every conversion in it is a pure function of the bytes, so they are
# checked against values whose bit patterns are known exactly - a double
# packed by python, a float, the specials - and then the command itself is
# driven over a real page, from both views.
cat > "$WORK/tins.vim" <<EOF
$(printf "$HEX")
let out = []
call add(out, HexPairPagedBinaryText(173) . ' ' . HexPairPagedBinaryText(0) . ' ' . HexPairPagedBinaryText(255))
call add(out, HexPairPagedU64Text(-1) . ' ' . HexPairPagedU64Text(0) . ' ' . HexPairPagedU64Text(-1068498944))
call add(out, HexPairPagedDecSub('1000', '1') . ' ' . HexPairPagedDecSub('100', '100'))
call add(out, HexPairPagedIeeeText([0x40,0x93,0x4a,0x45,0x6d,0x5c,0xfa,0xad]) . ' ' . HexPairPagedIeeeText([0xc0,0x50,0x00,0x00]))
call add(out, HexPairPagedIeeeText([0x7f,0x80,0,0]) . ' ' . HexPairPagedIeeeText([0xff,0x80,0,0]) . ' ' . HexPairPagedIeeeText([0x7f,0xc0,0,0]) . ' ' . HexPairPagedIeeeText([0,0,0,0]) . ' ' . HexPairPagedIeeeText([0,0,0,1]))
HexPairOpen $WORK/insp1.bin 1
HexPairGoOffset 66
redir => m1
silent HexPairInspect
redir END
let hexview = filter(split(m1, "\n"), 'v:val !~# "^\$"')
call extend(out, hexview)
HexPairGoOffset 512
redir => m2
silent HexPairInspect
redir END
call add(out, filter(split(m2, "\n"), 'v:val =~# "16-bit"')[0])
HexPairGoOffset 1
HexPairToggle
redir => m3
silent HexPairInspect
redir END
let textview = filter(split(m3, "\n"), 'v:val !~# "^\$"')
HexPairToggle
HexPairGoOffset 1
redir => m4
silent HexPairInspect
redir END
call add(out, string(textview ==# filter(split(m4, "\n"), 'v:val !~# "^\$"')))
normal! 1G
redir => m5
silent HexPairInspect
redir END
call add(out, filter(split(m5, "\n"), 'v:val !~# "^\$"')[0])
call writefile(out, '$WORK/tins.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tins.vim" < /dev/null
check "a byte in binary" "10101101 00000000 11111111" "$(sed -n 1p "$WORK/tins.out")"
# Vim's Number is signed, so the unsigned form of a 64-bit pattern whose
# top bit is set has to be done in decimal.
check "an unsigned 64-bit pattern" "18446744073709551615 0 18446744072641052672" \
    "$(sed -n 2p "$WORK/tins.out")"
check "decimal subtraction, including down to zero" "999 0" "$(sed -n 3p "$WORK/tins.out")"
check "IEEE 754 from the bytes python packed" "1234.5678 -3.25" "$(sed -n 4p "$WORK/tins.out")"
check "and the ends of the range" "inf -inf nan 0.0 1.401298e-45" \
    "$(sed -n 5p "$WORK/tins.out")"
check "the inspector reads the bytes at the cursor" \
    "hexpair: byte 66 (0x42) of 512: 41 42 43 44 45 46 47 48" \
    "$(sed -n 6p "$WORK/tins.out")"
check "one byte, as a character and as bits" \
    "  8-bit    65                          char 'A'  bin 01000001  oct 0101" \
    "$(sed -n 7p "$WORK/tins.out")"
check "the widths, both ways round" \
    "  16-bit   16961                       16706" "$(sed -n 9p "$WORK/tins.out")"
check "including the 64-bit one" \
    "  64-bit   5208208757389214273         4702394921427289928" \
    "$(sed -n 11p "$WORK/tins.out")"
check "and the floats" \
    "  float32  781.035217                  12.141422" "$(sed -n 12p "$WORK/tins.out")"
check "a width that does not fit in what is left of the page says so" \
    "  16-bit   (only 1 byte left on this page)" "$(sed -n 14p "$WORK/tins.out")"
check "both views read the same bytes" "1" "$(sed -n 15p "$WORK/tins.out")"
check "and a banner line has nothing to read" "hexpair: no byte here to read" \
    "$(sed -n 16p "$WORK/tins.out")"

# ===========================================================================
# Two views of one file
# ===========================================================================
# :HexPairSplit opens a second window on the same file at another page.
# Two things used to stand in the way: the buffer name, which was the
# file's alone and collided (E95), and the freshness check, which refused
# a write whenever the file's timestamp had moved - which is exactly what
# the other view writing does. This bumps the timestamp deliberately, so
# the test does not depend on how fast the two writes happen to be.
cat > "$WORK/bump.py" <<'PYEOF'
import os, sys
st = os.stat(sys.argv[1])
os.utime(sys.argv[1], (st.st_atime, st.st_mtime + 5))
PYEOF
cat > "$WORK/tsv.vim" <<EOF
$(printf "$HEX")
HexPairOpen $WORK/split1.bin 3
let first = bufname('%')
HexPairSplit +2
let second = [bufname('%') !=# first, b:hexpair_page_index + 1, winnr('\$')]
HexPairVSplit \$
let third = [b:hexpair_page_index + 1, winnr('\$'), winwidth(0) < &columns]
let before = winnr('\$')
silent! HexPairSplit +99
let nowindow = winnr('\$') == before
only
call writefile([string([second, third, nowindow])], '$WORK/tsv.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tsv.vim" < /dev/null
check "a split is a second view, on the page it names" \
    "[[1, 5, 2], [10, 3, 1], 1]" "$(cat "$WORK/tsv.out")"

# --- Both views can write, because they hold different pages --------------
SV2_HEAD=$(hash_range "$WORK/split2.bin" 0 1024)
cat > "$WORK/tsv2.vim" <<EOF
$(printf "$HEX")
HexPairOpen $WORK/split2.bin 3
let a = bufnr('%')
HexPairSplit 7
call cursor(3, 11)
normal! rf
write
let b = 'wrote page 7'
call system('$PY $WORK/bump.py $WORK/split2.bin')
execute bufwinnr(a) . 'wincmd w'
call cursor(3, 11)
normal! re
let outcome = ''
try
  write
  let outcome = 'wrote page 3'
catch /^hexpair:/
  let outcome = 'refused'
endtry
call writefile([string([b, outcome, &l:modified])], '$WORK/tsv2.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tsv2.vim" < /dev/null
check "one view writing does not lock the other out" \
    "['wrote page 7', 'wrote page 3', 0]" "$(cat "$WORK/tsv2.out")"
check "and both edits are in the file" "e0 f0" \
    "$("$HEXPAIR_XXD" -s 1040 -l 1 -p "$WORK/split2.bin") $("$HEXPAIR_XXD" -s 3088 -l 1 -p "$WORK/split2.bin")"

# --- ... but a view whose own page was overwritten is still refused -------
cat > "$WORK/tsv3.vim" <<EOF
$(printf "$HEX")
HexPairOpen $WORK/split3.bin 3
let a = bufnr('%')
HexPairSplit 3
call cursor(4, 11)
normal! rf
write
call system('$PY $WORK/bump.py $WORK/split3.bin')
execute bufwinnr(a) . 'wincmd w'
call cursor(3, 11)
normal! re
let outcome = ''
try
  write
  let outcome = 'wrote'
catch /^hexpair:/
  let outcome = 'refused'
endtry
call writefile([outcome, string(&l:modified)], '$WORK/tsv3.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tsv3.vim" < /dev/null
check "two views of the SAME page do not overwrite each other" "refused" \
    "$(sed -n 1p "$WORK/tsv3.out")"
check "the refused edit is still in the buffer" "1" "$(sed -n 2p "$WORK/tsv3.out")"
# The split view edited the byte at 1056 and wrote it; the refused view
# wanted 1040, which must still hold what it always did.
check "the other view's byte is the one on disk" "f0" \
    "$("$HEXPAIR_XXD" -s 1056 -l 1 -p "$WORK/split3.bin")"
check "and the refused edit reached nothing" "10" \
    "$("$HEXPAIR_XXD" -s 1040 -l 1 -p "$WORK/split3.bin")"

# --- ... and a plain :split can be one too, if asked ----------------------
# g:hexpair_split_views makes a window that ends up showing a page a second
# time into a view of its own. Off by default, because a page is thousands
# of lines and looking at two parts of ONE page in two windows is what
# :split is for everywhere else.
cat > "$WORK/tsv5.vim" <<EOF
$(printf "$HEX")
HexPairOpen $WORK/split4.bin 3
split
let plain = [winbufnr(1) == winbufnr(2), winnr('\$')]
only
let g:hexpair_split_views = 1
split
let asked = [winbufnr(1) != winbufnr(2), b:hexpair_page_index + 1, HexPairPagedByteOffset()]
HexPairPageNext
let here = b:hexpair_page_index + 1
wincmd w
let there = b:hexpair_page_index + 1
" switching between windows must not keep making views
let buffers = len(filter(range(1, bufnr('\$')), 'bufexists(v:val)'))
wincmd w
wincmd w
let stable = len(filter(range(1, bufnr('\$')), 'bufexists(v:val)')) == buffers
" a split of the text view stays a text view
HexPairToggle
split
let astext = [b:hexpair_view, winbufnr(1) != winbufnr(2)]
call writefile([string(plain), string(asked), string([here, there, stable]), string(astext)], '$WORK/tsv5.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tsv5.vim" < /dev/null
check "by default :split is two windows on one page, as everywhere else" \
    "[1, 2]" "$(sed -n 1p "$WORK/tsv5.out")"
check "asked to, it makes a view of its own on the same byte" \
    "[1, 3, 1024]" "$(sed -n 2p "$WORK/tsv5.out")"
check "which then turns its pages alone" "[4, 3, 1]" \
    "$(sed -n 3p "$WORK/tsv5.out")"
check "and a split of the text view is a text view" "['text', 1]" \
    "$(sed -n 4p "$WORK/tsv5.out")"

# --- Piped input has nothing to make a second view from -------------------
cat > "$WORK/tsv6.vim" <<EOF
$(printf "$HEX")
let g:hexpair_split_views = 1
call setline(1, ['abc', 'def'])
HexPairToggle
split
call writefile([string([winbufnr(1) == winbufnr(2), winnr('\$'), b:hexpair_page_active])], '$WORK/tsv6.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tsv6.vim" < /dev/null
check "so its :split stays a plain one, without complaint" "[1, 2, 1]" \
    "$(cat "$WORK/tsv6.out")"

# --- A view paged from piped input has nothing to split -------------------
# Its temp file belongs to that buffer and goes when the buffer does.
cat > "$WORK/tsv4.vim" <<EOF
$(printf "$HEX")
call setline(1, ['abc', 'def'])
HexPairToggle
redir => msg
silent! HexPairSplit
redir END
call writefile([substitute(substitute(msg, '^[\r\n]*', '', ''), '\n', ' ', 'g'), string(winnr('\$'))], '$WORK/tsv4.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tsv4.vim" < /dev/null
check "splitting piped input says why not" \
    "hexpair: this view is paged from a private copy of piped input, which belongs to it alone; save it with :w {file} first, and split that" \
    "$(sed -n 1p "$WORK/tsv4.out")"
check "and opens no window" "1" "$(sed -n 2p "$WORK/tsv4.out")"

# --- Stepping by bytes, and :HexPairOpen! ---------------------------------
# A step moves from the byte the cursor is on, so it crosses page
# boundaries the same way a position does. The bang is Vim's own "abandon
# what is in this window", which :HexPairOpen had never had.
cat > "$WORK/tstep.vim" <<EOF
$(printf "$HEX")
HexPairOpen $WORK/step1.bin 3
call cursor(4, 11)
let start = HexPairPagedByteOffset()
HexPairGoOffset +16
let forward = HexPairPagedByteOffset()
HexPairGoOffset -0x20
let back = HexPairPagedByteOffset()
HexPairGoOffset +600
let crossed = [HexPairPagedByteOffset(), b:hexpair_page_index + 1]
redir => msg
silent! HexPairGoOffset -99999
redir END
let outside = substitute(msg, '^[\r\n]*', '', '')
enew
call setline(1, 'precious unsaved work')
let refused = ''
try
  HexPairOpen $WORK/step1.bin 1
catch
  let refused = v:exception =~# 'E37' ? 'refused' : v:exception
endtry
HexPairOpen! $WORK/step1.bin 1
call writefile([string([start, forward, back, crossed]), outside, string([refused, b:hexpair_page_index + 1, get(b:, 'hexpair_page_active', 0)])], '$WORK/tstep.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tstep.vim" < /dev/null
check "a step moves from where the cursor is, and turns the page" \
    "[1056, 1072, 1040, [1640, 4]]" "$(sed -n 1p "$WORK/tstep.out")"
check "and a step out of the file is refused like a position" \
    "hexpair: byte -98358 is outside the file (5000 bytes)" \
    "$(sed -n 2p "$WORK/tstep.out")"
# The bang is about the buffer being LEFT, not about the page: a paged
# buffer is 'bufhidden' hide and is never abandoned, but an ordinary
# modified buffer in the window is, and Vim refuses that without a !.
check "the bang opens over a modified buffer, the bare command does not" \
    "['refused', 1, 1]" "$(sed -n 3p "$WORK/tstep.out")"

# ===========================================================================
# Marks
# ===========================================================================
# Positions in the FILE, not in a buffer: a paged buffer holds a different
# part of the file from one page to the next, so Vim's own marks cannot
# mean what they say here. These are kept per file, so two views of one
# file share them.
cat > "$WORK/tmk.vim" <<EOF
$(printf "$HEX")
let out = []
call add(out, string([HexPairPagedMarkNameError('header'), HexPairPagedMarkNameError(''), HexPairPagedMarkNameError('a b')]))
call add(out, string(HexPairPagedMarkLines({}, 512, 5000)))
call add(out, string(HexPairPagedMarkLines({'b': 1056, 'a': 3123, 'gone': 9999}, 512, 5000)))
HexPairOpen $WORK/mark1.bin 3
call cursor(4, 11)
HexPairMark header
HexPairPageGoto 7
call cursor(5, 20)
HexPairMark payload
HexPairPageGoto 1
HexPairGoMark header
call add(out, HexPairStatus())
call add(out, string(HexPairPagedMarkComplete('h', '', 0)))
" a second view of the same file sees the same marks
HexPairSplit 1
HexPairGoMark payload
call add(out, HexPairStatus())
HexPairMarkDelete payload
redir => msg
silent! HexPairGoMark payload
redir END
call add(out, substitute(substitute(msg, '^[\r\n]*', '', ''), '\n', ' ', 'g'))
call writefile(out, '$WORK/tmk.out')
qa!
EOF
"$HEXPAIR_VIM" -es -u NONE -S "$WORK/tmk.vim" < /dev/null
check "a mark name is a word" \
    "['', 'hexpair: a mark needs a name', 'hexpair: ''a b'' is not a mark name (letters, digits and underscores)']" \
    "$(sed -n 1p "$WORK/tmk.out")"
check "no marks says so" "['hexpair: no marks in this file']" \
    "$(sed -n 2p "$WORK/tmk.out")"
# Listed by offset, not by name, and a mark left behind by a file that
# shrank says where it now points.
check "the listing is by position, and names the page" \
    "['hexpair: marks in this file:', '  b                byte 1057 (0x421) of 5000, page 3', '  a                byte 3124 (0xc34) of 5000, page 7', '  gone             byte 10000 (0x2710) - past the end of 5000, page 20']" \
    "$(sed -n 3p "$WORK/tmk.out")"
check "a mark is a byte to jump back to" "hex 3/10 @0x421" \
    "$(sed -n 4p "$WORK/tmk.out")"
check "and completes by name" "['header']" "$(sed -n 5p "$WORK/tmk.out")"
check "a second view of the file has the same marks" "hex 7/10 @0xc34" \
    "$(sed -n 6p "$WORK/tmk.out")"
check "a dropped mark is dropped for both, and says what is left" \
    "hexpair: no mark named 'payload' here (have: header)" \
    "$(sed -n 7p "$WORK/tmk.out")"

# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED." >&2
fi
exit $FAIL
