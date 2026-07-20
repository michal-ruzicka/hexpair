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
ROOT=$(cd .. && pwd)
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
# validation / reload fixture (must stay unmodified by the tests)
open(os.path.join(w, 'val.bin'), 'wb').write(b'ABCDEFGH')
# modified-flag fixtures: separate copies so a write in one test cannot
# affect another test's expectations
for name in ('mod12.bin', 'mod13.bin', 'mod14.bin', 'mod15.bin'):
    open(os.path.join(w, name), 'wb').write(b'ABCDEFGH')
# :HexPairRefresh fixtures
for name in ('ref1.bin', 'ref2.bin', 'ref3.bin', 'ref4.bin', 'ref5.bin'):
    open(os.path.join(w, name), 'wb').write(b'ABCDEFGH')
# paged-mode fixture: 5000 bytes, byte i has value i % 256 - at 512
# bytes/page that is 10 pages, the last one short (392 bytes)
for name in ('paged21.bin', 'paged22.bin', 'paged23.bin', 'paged31.bin', 'paged32.bin'):
    with open(os.path.join(w, name), 'wb') as f:
        f.write(bytes(i % 256 for i in range(5000)))
# fixture with a name that is awkward for Ex command-line argument
# parsing: a space and a literal '$NAME' substring
special_dir = os.path.join(w, 'space dir')
os.mkdir(special_dir)
with open(os.path.join(special_dir, 'dollar $HOSTNAME name.bin'), 'wb') as f:
    f.write(b'ABCDEFGH')
EOF
PAGEDPLUGIN=../plugin/hexpair_paged.vim

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

# --- Test 5: ftplugin defaults + managed 'paste' across the toggle ---------
# The original filetype of a binary buffer is empty, so this also covers
# the explicit b:undo_ftplugin execution in s:FromHex() (no FileType
# event fires when an empty filetype is restored).
cat > "$WORK/t5.vim" <<EOF
" Hermetic runtimepath: only the repo and \$VIMRUNTIME, so a developer's
" personal ~/.vim/ftplugin/xxd.vim cannot leak into the assertions.
let &runtimepath = '$ROOT,' . \$VIMRUNTIME
filetype plugin on
source $PLUGIN
HexPairToggle
let on = [&l:tabstop, &l:shiftwidth, &l:expandtab, &paste]
HexPairToggle
let off = [&l:tabstop, &l:shiftwidth, &l:expandtab, &paste, exists('b:did_ftplugin')]
HexPairToggle
let re = [&l:tabstop, &l:expandtab, &paste]
call writefile([string(on), string(off), string(re)], '$WORK/t5.out')
qa!
EOF
vim -es -b -u NONE "$WORK/ins.bin" -S "$WORK/t5.vim"
check "ftplugin + paste active in hex mode"     "[10, 3, 1, 1]"   "$(sed -n 1p "$WORK/t5.out")"
check "ftplugin + paste reverted on toggle-off" "[8, 8, 0, 0, 0]" "$(sed -n 2p "$WORK/t5.out")"
check "ftplugin re-applied on re-toggle"        "[10, 1, 1]"      "$(sed -n 3p "$WORK/t5.out")"

# --- Test 6: a user ftplugin with b:did_ftplugin suppresses the bundled one -
mkdir -p "$WORK/user-rtp/ftplugin"
cat > "$WORK/user-rtp/ftplugin/xxd.vim" <<'EOF'
let b:did_ftplugin = 1
setlocal tabstop=4
EOF
cat > "$WORK/t6.vim" <<EOF
let &runtimepath = '$WORK/user-rtp,$ROOT,' . \$VIMRUNTIME
filetype plugin on
source $PLUGIN
HexPairToggle
call writefile([string([&l:tabstop, &l:shiftwidth])], '$WORK/t6.out')
qa!
EOF
vim -es -b -u NONE "$WORK/ins.bin" -S "$WORK/t6.vim"
check "user ftplugin overrules bundled defaults" "[4, 8]" "$(cat "$WORK/t6.out")"

# --- Test 7: g:hexpair_paste opt-out; restore on leaving the hex buffer ----
cat > "$WORK/t7.vim" <<EOF
let &runtimepath = '$ROOT,' . \$VIMRUNTIME
filetype plugin on
source $PLUGIN
let g:hexpair_paste = 0
HexPairToggle
let optout = &paste
HexPairToggle
let g:hexpair_paste = 1
HexPairToggle
let inhex = &paste
new
let outside = &paste
wincmd p
let back = &paste
call writefile([string([optout, inhex, outside, back])], '$WORK/t7.out')
qa!
EOF
vim -es -b -u NONE "$WORK/ins.bin" -S "$WORK/t7.vim"
check "paste opt-out and restore on buffer switch" "[0, 1, 0, 1]" "$(cat "$WORK/t7.out")"

# --- Test 8: a non-hex character aborts :w; file and dump stay intact ------
cat > "$WORK/t8.vim" <<EOF
source $PLUGIN
HexPairToggle
call setline(1, substitute(getline(1), '41', '4x', ''))
let caught = ''
try
  write
catch /^hexpair:/
  let caught = 'caught'
endtry
let state = string([get(b:, 'hexpair_active', 0), line('.'), col('.')])
call writefile([caught, state, getline(1)], '$WORK/t8.out')
qa!
EOF
vim -es -b -u NONE "$WORK/val.bin" -S "$WORK/t8.vim"
check "invalid char aborts the write"  "caught"     "$(sed -n 1p "$WORK/t8.out")"
check "cursor parked on the offender"  "[1, 1, 12]" "$(sed -n 2p "$WORK/t8.out")"
check "dump kept after aborted write" \
    "00000000: 4x 42 43 44 45 46 47 48                          ABCDEFGH" \
    "$(sed -n 3p "$WORK/t8.out")"
check "file kept after aborted write" \
    "00000000: 41 42 43 44 45 46 47 48                          ABCDEFGH" \
    "$(xxd -g 1 "$WORK/val.bin")"

# --- Test 9: a non-hex character refuses hex-mode toggle-off ---------------
cat > "$WORK/t9.vim" <<EOF
source $PLUGIN
HexPairToggle
call append(1, '01 0g 03')
HexPairToggle
call writefile([string([get(b:, 'hexpair_active', 0), line('.'), col('.')])], '$WORK/t9.out')
qa!
EOF
vim -es -b -u NONE "$WORK/val.bin" -S "$WORK/t9.vim"
check "invalid char refuses toggle-off" "[1, 2, 5]" "$(cat "$WORK/t9.out")"

# --- Test 10: an odd total number of hex digits aborts :w ------------------
cat > "$WORK/t10.vim" <<EOF
source $PLUGIN
HexPairToggle
call append(1, '01 2')
let caught = ''
try
  write
catch /^hexpair:/
  let caught = v:exception =~# 'odd' ? 'odd' : 'other'
endtry
call writefile([caught], '$WORK/t10.out')
qa!
EOF
vim -es -b -u NONE "$WORK/val.bin" -S "$WORK/t10.vim"
check "odd digit count aborts the write" "odd" "$(cat "$WORK/t10.out")"

# --- Test 11: :e while in hex mode regenerates the dump --------------------
cat > "$WORK/t11.vim" <<EOF
source $PLUGIN
HexPairToggle
call cursor(1, 20)
HexPairGoHex
silent edit
let state = string([get(b:, 'hexpair_active', 0), line('.'), col('.'), &l:modified])
call writefile([getline(1), state], '$WORK/t11.out')
qa!
EOF
vim -es -b -u NONE "$WORK/val.bin" -S "$WORK/t11.vim"
check "reload regenerates the dump" \
    "00000000: 41 42 43 44 45 46 47 48                          ABCDEFGH" \
    "$(sed -n 1p "$WORK/t11.out")"
check "reload keeps hex mode and cursor byte" "[1, 1, 20, 0]" \
    "$(sed -n 2p "$WORK/t11.out")"

# --- Test 12: an edit made in hex mode marks the buffer modified -----------
# This is the regression test for the data-loss bug: toggling back used to
# unconditionally mirror the PRE-hex-mode modified state, silently clearing
# 'modified' even though the dump had just been edited.
cat > "$WORK/t12.vim" <<EOF
source $PLUGIN
HexPairToggle
call setline(1, substitute(getline(1), '41', '5a', ''))
HexPairToggle
call writefile([string([&modified, getline(1)])], '$WORK/t12.out')
qa!
EOF
vim -es -b -u NONE "$WORK/mod12.bin" -S "$WORK/t12.vim"
check "edit in hex mode marks buffer modified" "[1, 'ZBCDEFGH']" "$(cat "$WORK/t12.out")"

# --- Test 13: an edit-free round trip stays unmodified ----------------------
cat > "$WORK/t13.vim" <<EOF
source $PLUGIN
HexPairToggle
HexPairToggle
call writefile([string([&modified, getline(1)])], '$WORK/t13.out')
qa!
EOF
vim -es -b -u NONE "$WORK/mod13.bin" -S "$WORK/t13.vim"
check "edit-free round trip stays unmodified" "[0, 'ABCDEFGH']" "$(cat "$WORK/t13.out")"

# --- Test 14: a pre-existing modification survives an edit-free round trip -
cat > "$WORK/t14.vim" <<EOF
source $PLUGIN
call setline(1, substitute(getline(1), '^A', 'Z', ''))
HexPairToggle
HexPairToggle
call writefile([string([&modified, getline(1)])], '$WORK/t14.out')
qa!
EOF
vim -es -b -u NONE "$WORK/mod14.bin" -S "$WORK/t14.vim"
check "pre-existing modification survives edit-free hex round trip" "[1, 'ZBCDEFGH']" "$(cat "$WORK/t14.out")"

# --- Test 15: a write in hex mode resets the modified baseline -------------
cat > "$WORK/t15.vim" <<EOF
source $PLUGIN
HexPairToggle
call setline(1, substitute(getline(1), '41', '5a', ''))
write
HexPairToggle
call writefile([string([&modified, getline(1)])], '$WORK/t15.out')
qa!
EOF
vim -es -b -u NONE "$WORK/mod15.bin" -S "$WORK/t15.vim"
check "write in hex mode resets the modified baseline" "[0, 'ZBCDEFGH']" "$(cat "$WORK/t15.out")"
check "write in hex mode persists the edit to disk" \
    "00000000: 5a 42 43 44 45 46 47 48                          ZBCDEFGH" \
    "$(xxd -g 1 "$WORK/mod15.bin")"

# --- Test 16: :HexPairRefresh self-heals offsets/ASCII without writing -----
cat > "$WORK/t16.vim" <<EOF
source $PLUGIN
HexPairToggle
call append(1, '01 02 03 04 05')
call cursor(2, 7)
HexPairRefresh
let state = string([line('.'), col('.'), strpart(getline('.'), col('.') - 1, 2), line('\$')])
call writefile([state, getline(1)], '$WORK/t16.out')
qa!
EOF
vim -es -b -u NONE "$WORK/ref1.bin" -S "$WORK/t16.vim"
check "refresh: cursor stays on same byte, dump merges to one line" \
    "[1, 41, '03', 1]" "$(sed -n 1p "$WORK/t16.out")"
check "refresh: offsets and ASCII column regenerated" \
    "00000000: 41 42 43 44 45 46 47 48 01 02 03 04 05           ABCDEFGH....." \
    "$(sed -n 2p "$WORK/t16.out")"
check "refresh never writes to disk" \
    "00000000: 41 42 43 44 45 46 47 48                          ABCDEFGH" \
    "$(xxd -g 1 "$WORK/ref1.bin")"

# --- Test 17: refresh after a real edit keeps 'modified' through toggle-off
cat > "$WORK/t17.vim" <<EOF
source $PLUGIN
HexPairToggle
call setline(1, substitute(getline(1), '41', '5a', ''))
HexPairRefresh
let afterrefresh = &modified
HexPairToggle
call writefile([string([afterrefresh, &modified, getline(1)])], '$WORK/t17.out')
qa!
EOF
vim -es -b -u NONE "$WORK/ref2.bin" -S "$WORK/t17.vim"
check "edit survives refresh and toggle-off as modified" "[1, 1, 'ZBCDEFGH']" \
    "$(cat "$WORK/t17.out")"

# --- Test 18: a no-op refresh stays unmodified through toggle-off ----------
cat > "$WORK/t18.vim" <<EOF
source $PLUGIN
HexPairToggle
HexPairRefresh
let afterrefresh = &modified
HexPairToggle
call writefile([string([afterrefresh, &modified, getline(1)])], '$WORK/t18.out')
qa!
EOF
vim -es -b -u NONE "$WORK/ref3.bin" -S "$WORK/t18.vim"
check "no-op refresh stays unmodified through toggle-off" "[0, 0, 'ABCDEFGH']" \
    "$(cat "$WORK/t18.out")"

# --- Test 19: an invalid dump refuses refresh -------------------------------
cat > "$WORK/t19.vim" <<EOF
source $PLUGIN
HexPairToggle
call setline(1, substitute(getline(1), '41', '4x', ''))
let before = getline(1)
HexPairRefresh
let state = string([get(b:, 'hexpair_active', 0), line('.'), col('.'), getline(1) ==# before])
call writefile([state], '$WORK/t19.out')
qa!
EOF
vim -es -b -u NONE "$WORK/ref4.bin" -S "$WORK/t19.vim"
check "invalid char refuses refresh" "[1, 1, 12, 1]" "$(cat "$WORK/t19.out")"

# --- Test 20: refresh outside hex mode is a no-op --------------------------
cat > "$WORK/t20.vim" <<EOF
source $PLUGIN
HexPairRefresh
call writefile([string([get(b:, 'hexpair_active', 0)])], '$WORK/t20.out')
qa!
EOF
vim -es -b -u NONE "$WORK/ref5.bin" -S "$WORK/t20.vim"
check "refresh outside hex mode is a no-op" "[0]" "$(cat "$WORK/t20.out")"

# --- Test 21: :HexPairOpen shows page 1 with banner and absolute offsets ---
cat > "$WORK/t21.vim" <<EOF
source $PLUGIN
source $PAGEDPLUGIN
let g:hexpair_page_size = 512
HexPairOpen $WORK/paged21.bin 1
let state = string([line('\$'), line('.'), col('.')])
call writefile([getline(1), getline(2), getline('\$'), state], '$WORK/t21.out')
qa!
EOF
vim -es -u NONE -S "$WORK/t21.vim"
check "page 1 top banner" \
    "\" hexpair: page 1/10  bytes 1-512 of 5000  $WORK/paged21.bin" \
    "$(sed -n 1p "$WORK/t21.out")"
check "page 1 first data line" \
    "00000000: 00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f  ................" \
    "$(sed -n 2p "$WORK/t21.out")"
check "page 1 bottom banner" "\" hexpair: end of page 1/10" "$(sed -n 3p "$WORK/t21.out")"
check "page 1 line count and cursor on first byte" "[34, 2, 10]" "$(sed -n 4p "$WORK/t21.out")"

# --- Test 22: :HexPairPageNext / :HexPairPageGoto move between pages -------
cat > "$WORK/t22.vim" <<EOF
source $PLUGIN
source $PAGEDPLUGIN
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
vim -es -u NONE -S "$WORK/t22.vim"
check "next page shows page 2" \
    "\" hexpair: page 2/10  bytes 513-1024 of 5000  $WORK/paged22.bin" \
    "$(sed -n 1p "$WORK/t22.out")"
check "goto last (short) page banner and size" \
    "['\" hexpair: page 10/10  bytes 4609-5000 of 5000  $WORK/paged22.bin', '\" hexpair: end of page 10/10', 27]" \
    "$(sed -n 2p "$WORK/t22.out")"
check "next past the last page does not throw"  "no-error" "$(sed -n 3p "$WORK/t22.out")"
check "next past the last page leaves the page unchanged" "1" "$(sed -n 4p "$WORK/t22.out")"

# --- Test 23: navigation guard refuses to discard unsaved edits ------------
cat > "$WORK/t23.vim" <<EOF
source $PLUGIN
source $PAGEDPLUGIN
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
vim -es -u NONE -S "$WORK/t23.vim"
check "next without ! refuses to discard edits" \
    "['\" hexpair: page 1/10  bytes 1-512 of 5000  $WORK/paged23.bin', 1]" \
    "$(sed -n 1p "$WORK/t23.out")"
check "next! discards edits and advances" \
    "['\" hexpair: page 2/10  bytes 513-1024 of 5000  $WORK/paged23.bin', 0]" \
    "$(sed -n 2p "$WORK/t23.out")"

# --- Test 24: :HexPairPages reports the expected text -----------------------
cat > "$WORK/t24.vim" <<EOF
source $PLUGIN
source $PAGEDPLUGIN
let g:hexpair_page_size = 512
HexPairOpen $WORK/paged21.bin 3
redir => msg
silent HexPairPages
redir END
call writefile([trim(msg)], '$WORK/t24.out')
qa!
EOF
vim -es -u NONE -S "$WORK/t24.vim"
check "HexPairPages reports page/offsets/total" \
    "hexpair: page 3 of 10, offsets 1025-1536 of total 5000 bytes ($WORK/paged21.bin)" \
    "$(cat "$WORK/t24.out")"

# --- Test 25: version-gate message function, both branches -----------------
cat > "$WORK/t25.vim" <<EOF
source $PLUGIN
source $PAGEDPLUGIN
let ok = HexPairPagedGateMessage(1)
let fail = HexPairPagedGateMessage(0)
call writefile([string(ok), fail], '$WORK/t25.out')
qa!
EOF
vim -es -u NONE -S "$WORK/t25.vim"
check "gate message empty when supported"     "''" "$(sed -n 1p "$WORK/t25.out")"
check "gate message set when unsupported" \
    "hexpair: paged mode requires Vim patch 8.2.4906 or later with +num64 (readblob(), 64-bit Numbers for large file offsets); this Vim does not qualify, paged commands are unavailable" \
    "$(sed -n 2p "$WORK/t25.out")"

# --- Test 26: g:hexpair_page_size validation --------------------------------
cat > "$WORK/t26.vim" <<EOF
source $PLUGIN
source $PAGEDPLUGIN
let ok       = HexPairPagedSizeError(1024, 16)
let notmult  = HexPairPagedSizeError(1000, 16)
let negative = HexPairPagedSizeError(-16, 16)
call writefile([string(ok), notmult, negative], '$WORK/t26.out')
qa!
EOF
vim -es -u NONE -S "$WORK/t26.vim"
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
source $PAGEDPLUGIN
" total = 4 GiB + 1000 bytes; size = 900 MB, so a naive page would
" straddle the 4 GiB offset-width boundary
let total = 4294967296 + 1000
let size  = 900000000
let idx = 4294967296 / size
let straddling = HexPairPagedBounds(idx, size, total)
let boundaries = HexPairPagedWidthBoundaries(total)
let n = HexPairPagedTotalPages(size, total)
let oob = HexPairPagedBounds(999999, 512, 5000)
call writefile([string(straddling), string(boundaries), string(n), string(oob)], '$WORK/t27.out')
qa!
EOF
vim -es -u NONE -S "$WORK/t27.vim"
check "page straddling a width boundary is clamped to end at it" \
    "[3600000000, 694967296]" "$(sed -n 1p "$WORK/t27.out")"
check "width boundary list contains exactly the 4 GiB transition" \
    "[4294967296]" "$(sed -n 2p "$WORK/t27.out")"
check "total pages accounts for the boundary split" "6" "$(sed -n 3p "$WORK/t27.out")"
check "out-of-range page index" "[-1, -1]" "$(sed -n 4p "$WORK/t27.out")"

# --- Test 28: banner-aware stripping and validation -------------------------
cat > "$WORK/t28.vim" <<EOF
source $PLUGIN
source $PAGEDPLUGIN
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
vim -es -u NONE -S "$WORK/t28.vim"
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
source $PAGEDPLUGIN
let g:hexpair_page_size = 512
call HexPairOpenFile(\$HEXPAIR_TEST_FILE)
let state = string([get(b:, 'hexpair_page_active', 0), b:hexpair_page_file ==# \$HEXPAIR_TEST_FILE])
call writefile([state, getline(2)], '$WORK/t29.out')
qa!
EOF
HEXPAIR_TEST_FILE="$SPECIAL_FILE" vim -es -u NONE -S "$WORK/t29.vim"
check "HexPairOpenFile opens a name with a space and a literal \$VAR" \
    "[1, 1]" "$(sed -n 1p "$WORK/t29.out")"
check "HexPairOpenFile shows the correct content" \
    "00000000: 41 42 43 44 45 46 47 48                          ABCDEFGH" \
    "$(sed -n 2p "$WORK/t29.out")"

# --- Test 30: HexPairPagedParsePageInput() - the goto-prompt parsing -------
cat > "$WORK/t30.vim" <<EOF
source $PLUGIN
source $PAGEDPLUGIN
let empty_input = HexPairPagedParsePageInput('')
let valid_input = HexPairPagedParsePageInput('7')
let bad_input   = HexPairPagedParsePageInput('abc')
call writefile([string(empty_input), string(valid_input), string(bad_input)], '$WORK/t30.out')
qa!
EOF
vim -es -u NONE -S "$WORK/t30.vim"
check "empty prompt input is cancellation, not an error" "{}" "$(sed -n 1p "$WORK/t30.out")"
check "numeric prompt input yields the page number"      "{'page': 7}" "$(sed -n 2p "$WORK/t30.out")"
check "non-numeric prompt input is a clear error"         "{'msg': 'hexpair: not a page number: abc'}" "$(sed -n 3p "$WORK/t30.out")"

# --- Test 31: :HexPairPageGoto! discards unsaved changes -------------------
# The mechanism <Plug>(HexPairPageGotoForce) relies on (s:GotoPage()'s
# force flag flowing through to the same guard s:PageNext()/s:PagePrev()
# already exercise via HexPairPageNext! in test 23).
cat > "$WORK/t31.vim" <<EOF
source $PLUGIN
source $PAGEDPLUGIN
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
vim -es -u NONE -S "$WORK/t31.vim"
check "goto without ! refuses to discard edits" \
    "['\" hexpair: page 1/10  bytes 1-512 of 5000  $WORK/paged31.bin', 1]" \
    "$(sed -n 1p "$WORK/t31.out")"
check "goto! discards edits and jumps" \
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
source $PAGEDPLUGIN
let g:hexpair_page_size = 512
let before = [bufname('%'), &l:buftype]
HexPairOpen $WORK/paged32.bin 999
let toolarge_unchanged = ([bufname('%'), &l:buftype] ==# before) && !get(b:, 'hexpair_page_active', 0)
HexPairOpen $WORK/paged32.bin abc
let nonnumeric_unchanged = ([bufname('%'), &l:buftype] ==# before) && !get(b:, 'hexpair_page_active', 0)
call writefile([string(toolarge_unchanged), string(nonnumeric_unchanged)], '$WORK/t32.out')
qa!
EOF
vim -es -u NONE -S "$WORK/t32.vim"
check "out-of-range page number leaves the buffer untouched" "1" "$(sed -n 1p "$WORK/t32.out")"
check "non-numeric page number leaves the buffer untouched"  "1" "$(sed -n 2p "$WORK/t32.out")"

# ---------------------------------------------------------------------------
if [ "$FAIL" -eq 0 ]; then
    echo "All tests passed."
else
    echo "Some tests FAILED." >&2
fi
exit $FAIL
