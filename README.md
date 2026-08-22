# `hexpair` Vim Plugin: a Slightly Advanced Support for HEX Display and Editing in Vim

[![Build](https://github.com/michal-ruzicka/hexpair/actions/workflows/build.yml/badge.svg)](https://github.com/michal-ruzicka/hexpair/actions/workflows/build.yml)
[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-GitHub%20Sponsors-ea4aaa?style=flat&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/michal-ruzicka)
[![Ko-fi](https://img.shields.io/badge/Tip-Ko--fi-FF5E5B?style=flat&logo=kofi&logoColor=white)](https://ko-fi.com/michal_ruzicka)
[![Revolut](https://img.shields.io/badge/Pay-Revolut-191C1F?style=flat&logo=revolut&logoColor=white)](https://revolut.me/ruzicka_michal)

**A Vim plugin that turns the classic `:%!xxd` hex-dump workflow into a
small, reliable hex editor** — with live highlighting of the byte pair
under the cursor in *both* the HEX and the ASCII column, byte-exact
cursor mapping between the views, `:w` that writes only the page you are
looking at, and forgiving editing where the offset and ASCII columns are
purely decorative.

**The hex*pair* name:** hex and text, always paired. *Within a line* —
the byte under the cursor and its character light up together, whichever
column you are in, one byte or a whole Visual selection. *Between the
views* — the page as a hex dump and the same page as raw text, toggled
with the cursor left on the same byte.

It is not the best hex editor in the world, and does not try to be. It
is the one that is always a single command away wherever you already
have Vim — no install, no package manager, nothing to get approved.
Everything runs on `xxd`, which ships with Vim itself, and portable
VimScript: no `sed`, `tr`, `dd` or anything else, so it behaves the same
on Linux, on native Windows (where `xxd.exe` is found inside the Vim
installation even when it is not on `PATH`) and inside WSL.

And it is good enough for real work on real files: because it shows one
page at a time and writes one page at a time, a file that does not fit
in memory — a disk image, a core dump, a database — is no different from
a small one. Editing an 8 GiB file costs the same 13 MB of memory as
editing an 8 KiB one. (A block device such as `/dev/sda` is the one
thing it cannot page: the size the system reports for one is 0, and
hexpair pages what a file says it holds. Copy a slice of it into a file,
or pipe one in — `dd if=/dev/sda bs=1M count=64 | vimhex -`.)

**Project page:** <https://github.com/michal-ruzicka/hexpair> — source
code, releases and issue tracker.

**Releases:** <https://github.com/michal-ruzicka/hexpair/releases>

**Support:** If you find this plugin useful, consider supporting its development.

- <https://github.com/sponsors/michal-ruzicka> — GitHub Sponsors (GitHub account needed).

  [![GitHub Sponsors](https://img.shields.io/github/sponsors/michal-ruzicka)](https://github.com/sponsors/michal-ruzicka)

- <https://ko-fi.com/michal_ruzicka> — Buy me a Coffee with no specific account needed, card payment is possible.

  [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/michal_ruzicka)

- <https://revolut.me/ruzicka_michal> — Donate me via Revolut, debit/credit card or Apple Pay.

---

## Features

- **Pair highlighting.** In the hex view, the byte under the cursor is
  highlighted in both columns: stand on a hex byte and the matching
  ASCII character lights up, and vice versa. The cursor side gets a
  subtle underline (`HexPairActive`), the counterpart a prominent
  highlight (`HexPairMirror`) — so you always see at a glance which
  column you are in. A **Visual selection** is mirrored the same way:
  select a run of hex digits and the text it is lights up, select a run
  of text and the bytes it is light up.
- **Byte-exact cursor mapping.** Every transition — into hex mode,
  between the hex and text views, across a write, across a page turn —
  keeps the cursor on the *same byte*, and entering hex mode opens on
  the page that byte is on. The mapping stays
  exact for files with a BOM, CRLF or even mixed CRLF/LF line endings,
  and single-byte file encodings (`latin*`, `cp125x`, ...).
- **Safe writing, scoped to the page.** `:w` converts back to binary
  and writes just the page you are looking at — the file on disk always
  contains the real bytes, never the textual dump, and regions of the
  file you never looked at cannot be clobbered. Overwriting values
  patches in place at a cost independent of the file's size.
- **Forgiving editing.** Only the HEX column matters: the offset and
  ASCII columns are stripped before the reverse conversion, so you can
  freely insert, delete or reorder lines — inserted lines need no
  offset and no ASCII part, just hex pairs. After `:w`, or on demand
  with `:HexPairRefresh`, the dump is regenerated and offsets become
  correct again automatically — `:HexPairRefresh` does this without
  writing to disk, and without affecting the `'modified'` flag.
- **Column navigation.** Commands to jump between the HEX and ASCII
  representation of the byte under the cursor, or to swap to the
  opposite column.
- **Search that knows the file, not the page.** `:HexPairFind de ad be ef`
  looks through the whole file a block at a time and lands on the byte it
  found, turning the page on the way; `?` stands for any nibble, and
  `:HexPairFindText` takes a string. `:HexPairReplace` and
  `:HexPairReplaceAllInPage` put new bytes over what was found.
- **Changed bytes are visible.** Everything edited and not yet written is
  marked in both columns (`HexPairModified`), so an edit in a dump does
  not look exactly like everything around it.
- **Compare with another file.** `:HexPairDiff other.bin` marks every byte
  of the page that differs from the same offset of `other.bin`, and
  `:HexPairDiffNext` walks the whole file for the next disagreement. The
  bundled `vimhexdiff a b` opens both files side by side that way.
- **Marks that survive page turns.** `:HexPairMark header` remembers a
  byte of the *file*, not a line of a buffer.
- **A data inspector.** `:HexPairInspect` reads the bytes at the cursor
  as the numbers they could be — 8, 16, 32 and 64 bits wide, unsigned
  and signed, little- and big-endian, plus `float32` and `float64` —
  which is the one question a hex dump cannot answer on its own.
- **A selection knows its size.** `:HexPairSelection` says how many
  bytes a Visual selection covers and which ones, in the same 1-based
  numbering `:HexPairGoOffset` takes.
- **Statusline support.** `HexPairStatus()` puts `hex 3/21 @0x4a2001` in
  your statusline and returns nothing in buffers hexpair never touched,
  so one statusline works everywhere.
- **An optional column ruler.** `g:hexpair_ruler` numbers the byte
  columns above the dump.
- **Binary correctness.** Opening a file without `-b` is handled by an
  automatic `:edit ++bin` reload, so the dump always shows the exact
  on-disk bytes (and a plain `:w` cannot silently re-encode a binary
  file).
- **Errors are refused, not guessed.** A non-hex character in the hex
  area, or an odd total number of hex digits, aborts `:w` and hex-mode
  the switch to the text view with an error and the cursor parked on
  the offender — the
  file and the dump keep their previous content. Reloading with `:e`
  while in hex mode regenerates the dump from the fresh file content
  and stays in hex mode instead of breaking the view.
- **Always paged, so file size stops mattering.** The hex view is always
  one page (default 128 KiB) with absolute file offsets — a small file
  simply has exactly one. `:HexPairOpen` opens a file of any size
  instantly, reading only the page it shows and never loading the rest. `:w` writes the page back: overwriting values patches it
  **in place**, so the rest of the file is never read or written
  whatever its size; inserting bytes moves only what follows them, also
  in place; and only deleting them rewrites the file. Either change of
  length says what it will cost and asks first. See
  [below](#paged-large-file-mode).

## Installation

Vim 8+ native packages (recommended):

```sh
mkdir -p ~/.vim/pack/plugins/start
tar xf hexpair.vX.Y.Z.tar -C ~/.vim/pack/plugins/start/
vim -c 'helptags ALL' -c 'q'
```

Or clone the repository directly:

```sh
git clone https://github.com/michal-ruzicka/hexpair.git \
    ~/.vim/pack/plugins/start/hexpair
vim -c 'helptags ALL' -c 'q'
```

The plugin defines **no key mappings by default**. Add your own to
`~/.vimrc`:

```vim
" Views
nmap <Leader>h <Plug>(HexPairToggle)        " hex page view <-> windowed text view
nmap <Leader>< <Plug>(HexPairGoHex)         " cursor to the HEX column, same byte
nmap <Leader>> <Plug>(HexPairGoAscii)       " cursor to the ASCII column, same byte
nmap <Leader>- <Plug>(HexPairSwap)          " cursor to the opposite column
nmap <Leader>r <Plug>(HexPairRefresh)       " regenerate offsets/ASCII, no write

" Moving around the file
nmap <Leader>j <Plug>(HexPairPageNext)      " next page
nmap <Leader>k <Plug>(HexPairPagePrev)      " previous page
nmap <Leader>g <Plug>(HexPairPageGoto)      " prompt for a page (N, +N, -N, $)
nmap <Leader>b <Plug>(HexPairGoOffset)      " prompt for a byte, 1-based (0x... ok)
nmap <Leader>? <Plug>(HexPairPages)         " where am I: page, range, cursor byte

" Reading the bytes
nmap <Leader>i <Plug>(HexPairInspect)       " the bytes at the cursor as numbers
nmap <Leader>s <Plug>(HexPairSelection)     " how many bytes the last selection was
xmap <Leader>s <Plug>(HexPairSelection)     " ... and the one being made now
nmap <Leader>m <Plug>(HexPairMarks)         " list the marks in this file

" Searching, and comparing with another file
nmap <Leader>n <Plug>(HexPairFindNext)      " next match of the last pattern
nmap <Leader>N <Plug>(HexPairFindPrev)      " previous match
nmap <Leader>] <Plug>(HexPairDiffNext)      " next byte that differs
nmap <Leader>[ <Plug>(HexPairDiffPrev)      " previous one

" Uppercase variants: the same, but discard unwritten changes without
" asking (like the ! commands) - handy for skimming through a file.
nnoremap <silent> <Leader>J :HexPairPageNext!<CR>
nnoremap <silent> <Leader>K :HexPairPagePrev!<CR>
nmap <Leader>G <Plug>(HexPairPageGotoForce)
nmap <Leader>B <Plug>(HexPairGoOffsetForce)
```

Note the `xmap` in the third block: it is the same `<Plug>` target in
**Visual** mode, where it reports the selection you are making rather
than the last one. Every other target is Normal-mode only. The commands
that take an argument — `:HexPairFind`, `:HexPairReplace`,
`:HexPairDiff`, `:HexPairMark`, `:HexPairSplit`, `:HexPairOpen` — have no
`<Plug>` target, so there is nothing to map for them.

`:HexPairOpen {file}` takes an argument, so it has no `<Plug>` target;
it is meant for the command line or a shell wrapper (see below).

`<Leader>` expands to the `mapleader` variable at the time a mapping is
defined — backslash by default; put e.g. `let mapleader = ','` *before*
the mappings to use a different prefix. The `<Plug>(HexPair…)` targets
are named virtual keys exposed by the plugin — map onto them with
`nmap`, not `nnoremap` (the latter forbids the remapping through which
a `<Plug>` target expands). Details: `:help hexpair-mappings`.

### Verifying Releases

Each release tarball is accompanied by a detached GPG signature file
(`hexpair.vX.Y.Z.tar.asc`). Before installing, verify that the
archive has not been tampered with:

```
gpg --keyserver keys.openpgp.org --recv-keys 489C5EC80FD62BE89E59B4F719C13E8CE0F5DB61
gpg --verify hexpair.vX.Y.Z.tar.asc hexpair.vX.Y.Z.tar
```

## Usage

Open a file, preferably in binary mode:

```sh
vim -b file.bin
```

and toggle the hex view with your mapping or `:HexPairToggle`. For a file
too large to want Vim to read at all, skip the buffer entirely:

```sh
vim -c 'HexPairOpen /var/lib/disk.img'
```

A shell wrapper for the same ships with the plugin. Source it from your
`~/.bashrc`:

```sh
source ~/.vim/pack/plugins/start/hexpair/hexpair.bashrc
```

and it gives you `vimhex`:

```sh
vimhex bigfile.bin              # the first page
vimhex bigfile.bin 3            # page 3
vimhex bigfile.bin '$'          # the last page, without counting them
vimhex bigfile.bin @0x4a2000    # the page holding that byte
cat bigfile.bin | vimhex -      # piped input
```

`:HexPairPages` reports the byte under the cursor in exactly the form
`@BYTE` takes, so you can note where you were and come straight back to
it later. Set `VIMHEX_VIM` to pick a particular Vim. Details are in the
file's own comments and in `:help hexpair-vimhex`.

A buffer hexpair has touched is in one of two views, and `:HexPairToggle`
moves between them:

| View | What you see |
|---|---|
| **Hex page** | the page as an xxd dump — offset, hex and ASCII columns — between two banner lines |
| **Windowed text** | the same page's raw bytes as text, between the same banner lines |

There is deliberately **no way back** to the plain buffer: once a buffer
holds one page instead of the whole file, showing it as the file again
would be a lie, and a plain `:w` would truncate the file down to that
page. Close and reopen the file for the ordinary view.

| Command | Description |
|---|---|
| `:HexPairToggle` | Move between the hex page view and the windowed text view |
| `:HexPairGoHex` / `:HexPairGoAscii` / `:HexPairSwap` | Move the cursor between the HEX and ASCII columns, staying on the same byte |
| `:HexPairRefresh` | Regenerate the offset and ASCII columns from the current hex payload, without writing |
| `:HexPairOpen {file} [page]` | Open `{file}` paged, without loading it; `[page]` takes `$` and `+N`/`-N` too |
| `:HexPairPageNext[!]` / `:HexPairPagePrev[!]` / `:HexPairPageGoto[!] {page}` | Turn pages (`!` discards unwritten changes); `{page}` is a number, `+N`/`-N` to step, or `$` for the last one |
| `:HexPairGoOffset[!] {byte}` | Jump to a byte, decimal or `0x`-prefixed, turning the page if needed; 1-based, like the banner. `+N` / `-N` step from where the cursor is |
| `:HexPairPages` | Report page X of Y, the offsets covered, the file size and the byte under the cursor |
| `:HexPairInspect` | Read the bytes at the cursor as numbers: 8/16/32/64-bit, unsigned and signed, both endiannesses, and both IEEE 754 floats |
| `:HexPairSelection` | Say how many bytes the Visual selection covers, and which |
| `:HexPairFind[!] {bytes}` | Find those bytes in the file (`?` = any nibble); `!` forgets the pattern |
| `:HexPairFindText {string}` | The same, for the bytes of a string |
| `:HexPairFindNext` / `:HexPairFindPrev` | Repeat the search either way (obeys `'wrapscan'`) |
| `:HexPairReplace {bytes}` | Put those bytes over the match under the cursor |
| `:HexPairReplaceAllInPage {pattern} / {bytes}` | ... over every match on the page in view |
| `:HexPairDiff[!] [file]` | Compare with `{file}`, marking the bytes that differ; `!` stops |
| `:HexPairDiffNext` / `:HexPairDiffPrev` | Walk to the next/previous byte where the two files differ |
| `:HexPairMark {name}` / `:HexPairGoMark[!] {name}` / `:HexPairMarks` / `:HexPairMarkDelete {name}` | Remember a byte of the file, jump back to it, list them, drop one |
| `:HexPairSplit [page]` / `:HexPairVSplit [page]` | A second view of the same file in a new window, showing `[page]` (default: this view's) |

### Reading the bytes

`:HexPairInspect` (mapped to `<Leader>i` above) reads the eight bytes at
the cursor as everything they could be:

```
hexpair: byte 66 (0x42) of 512: 41 42 43 44 45 46 47 48
  8-bit    65                          char 'A'  bin 01000001  oct 0101
           little-endian               big-endian
  16-bit   16961                       16706
  32-bit   1145258561                  1094861636
  64-bit   5208208757389214273         4702394921427289928
  float32  781.035217                  12.141422
  float64  1.58398e40                  2393736.541207
  utf-8    U+0041 'A' (1 byte)
  utf-16   U+4241 '䉁' (2 bytes)       U+4142 '䅂' (2 bytes)
  utf-32   U+44434241 - past U+10FFFF  U+41424344 - past U+10FFFF
```

The signed reading follows the unsigned one where the two differ
(`43981 / -21555`). The three text rows say what the bytes would be as
characters — UTF-8 has no byte order to get wrong, the other two are read
each way round like the numbers above them — and every way an encoding
can be wrong is its own answer rather than a code point: an overlong
UTF-8 sequence, a lone surrogate or a value past U+10FFFF is not a
character, and saying so is the point. The bytes are this page's, as the buffer holds them
— edits included — so at the end of a page the wider rows say how many
are left instead of reaching into a page that is not on screen.

`:HexPairSelection` (`<Leader>s`, in Visual mode too) says what a
selection covers:

```
hexpair: 18 bytes selected, 1041-1058 (0x411-0x422) of 5000
hexpair: 12 bytes selected in 3 lines (4 per line), 1041-1076 (0x411-0x434) of 5000
```

The second form is a blockwise selection, whose bytes are not one run —
so it leads with the count. Both work in either view, and the numbers
are 1-based, the same as the banner's, so they can be typed straight
into `:HexPairGoOffset`.

Editing rules (see `:help hexpair` for details): keep bytes in the hex
area separated by at most one space — a run of two spaces marks the
start of the (ignored) ASCII column — and always write full byte pairs.
The banner lines are decoration and contribute no bytes; in the windowed
text view they are matched by their exact text, so editing one refuses
the write rather than guessing which lines are content.

`:w` writes just the page you are looking at. If you only overwrote
values, it is patched **in place** — the file keeps its length, every
byte outside the page keeps its content, and the cost does not depend on
the file's size. If you inserted bytes, only what follows them has to
move, and it moves in place too — what precedes them is not even read.
Only deleting bytes rewrites the file, because nothing in Vim or `xxd`
can make a file shorter any other way. Either change of length says how
the size will change and how much has to be written, and asks first.

Where the pages come from depends on what the buffer was:

- **unmodified and backed by a file** — the usual case: pages are read
  from the file;
- **no file at all** (`cat data | vim -`) — the content is written once
  to a private temporary file and paged from there. A plain `:w` has
  nothing to write back to; `:w {file}` saves all of it and the view
  then edits that file. Pipe binary data in with `vim -b -`, or Vim may
  transcode it on the way in — hexpair warns when it does;
- **modified and backed by a file** — refused, because the buffer and
  the file disagree and every way of resolving that loses something
  quietly. Write it first, or use `:HexPairOpen` to see what is on disk.

### Searching, replacing, comparing

`/` searches the page on screen — which is a window on the file, so it
cannot find what is on any other page, and a sequence of bytes in a dump
has spaces, line breaks and an ASCII column through the middle of it.
`:HexPairFind` searches the **file**:

```vim
:HexPairFind de ad be ef      " or deadbeef, or de ?? be ef
:HexPairFindText PK\x03\x04    " the bytes of a string
:HexPairFindNext              " and again, obeying 'wrapscan'
```

Every match on the page is marked (`HexPairFind`), and the search lands
the cursor on the byte it found, turning the page if it is elsewhere.

```vim
:HexPairReplace 11 22 33 44                 " over the match under the cursor
:HexPairReplaceAllInPage de ad be ef / 00 00      " over every match on this page
```

Both edit the page exactly as typing over the dump would: the new bytes
are marked as changed, and nothing reaches the file until `:w` does — so
a replacement of a different length asks the same question any other
insertion or deletion asks.

The second command has the scope in its name because the scope is the
surprising part: everything here writes one page at a time, and a
file-wide replace would be a different mechanism with a different failure
to recover from, not a bigger version of this one. Step the pages to
cover a file.

Comparing with another file works the same way round:

```vim
:HexPairDiff ../golden/firmware.bin   " mark what differs on this page
:HexPairDiffNext                      " the next differing byte, wherever it is
:HexPairDiff!                         " stop comparing
```

and the shell wrapper opens two files that way in one go:

```sh
vimhexdiff old.img new.img
```

— both files side by side, each marking what differs from the other,
cursors on the first difference and the windows scroll-bound.

### Marks

Vim's own marks are positions in a *buffer*, and a paged buffer holds a
different part of the file from one page to the next. These are positions
in the **file**:

```vim
:HexPairMark header      " remember the byte under the cursor
:HexPairGoMark header    " go back to it, wherever it is
:HexPairMarks            " list them, by position, with the page each is on
:HexPairMarkDelete header
```

They are kept per file, so two views of one file share them, and they
last as long as the Vim session does.

### Two views of one file

`:HexPairSplit` opens a second window onto the same file at another page,
and `:HexPairVSplit` does it vertically:

```vim
:HexPairSplit +1        " the next page beside this one
:HexPairVSplit $        " the end of the file next to where you are
:HexPairSplit 7         " page 7
:HexPairSplit           " the same page again, to navigate away from
```

`[page]` is counted from the view you are in, exactly as
`:HexPairPageGoto` counts it. The two views share nothing but the file:
each is its own buffer with its own page, cursor and unwritten changes,
and a `:w` in either patches only the page that view holds — so one
region can be read while another is edited, or bytes copied from one to
the other. The second buffer is named `disk.img [hexpair page #2]`, which
is what tells them apart in `:ls`.

Writing one view does not lock the other out: a write asks whether *its
own page* changed on disk, not whether the file did. Two views of the
**same** page are allowed too — and then the second write is refused,
because that page really did change underneath it.

A plain `:split` on a hex page is left alone: it does what `:split` means
everywhere else in Vim — two windows onto **one** buffer, so both show
the same page and turning it in one turns it in the other. That is worth
keeping, because a page is thousands of lines and looking at two parts of
one page is a real use of a split. If you would rather every split be an
independent view, say so:

```vim
let g:hexpair_split_views = 1
```

and then `:split`, `:vsplit`, `:tab split` — any way a page ends up in a
second window — give you a view of its own, on the same page and the same
byte, to navigate away from. `:HexPairSplit` does it explicitly either
way.

A view paged from piped input cannot be split: the temporary file it
pages belongs to that buffer alone. Save it with `:w {file}` first. (With
`g:hexpair_split_views` on, a `:split` of such a view simply stays an
ordinary split rather than complaining.)

### Configuration

Every option, with its default, ready to paste into `~/.vimrc` — the
values shown are the defaults, so uncomment a line only to change one.

```vim
" ---- hexpair -------------------------------------------------------------

" Bytes per dump line.
" let g:hexpair_bytes_per_line = 16

" Bytes per page. Must stay a positive multiple of
" g:hexpair_bytes_per_line. A page is an ordinary Vim buffer, so a bigger
" one costs what that many lines cost - see "What it costs" below.
" let g:hexpair_page_size = 128 * 1024

" Whether a write that changes the page's length says what it will cost
" and asks first. Set it to 0 to answer yes automatically, e.g. in a script.
" let g:hexpair_page_confirm = 1

" Keep the global 'paste' option on while the cursor is in a hex buffer,
" and restore it when the cursor leaves. 0 leaves 'paste' alone.
" let g:hexpair_paste = 1

" A ruler line under the banner, numbering the byte columns of the dump.
" Set it to 1 to get one.
" let g:hexpair_ruler = 0

" Whether a plain :split (or :vsplit, or :tab split) of a hex page becomes
" an independent view of the same file - its own page, its own cursor -
" instead of a second window onto the same buffer. Set it to 1 to get
" views; :HexPairSplit does the same explicitly whatever this says.
" let g:hexpair_split_views = 0

" Position-mapping trace for diagnosing a cursor that landed on the wrong
" byte. Set it to 1 and read the trace with :messages.
" let g:hexpair_debug = 0

" Whether the bytes that differ from the ones on disk - what you have
" edited and not yet written - are highlighted. Set it to 0 to stop.
" let g:hexpair_show_modified = 1

" Highlight overrides: the byte under the cursor, its counterpart in the
" other column, the banner (and ruler) lines, the bytes changed since the
" page was read, the bytes that differ from the file being compared
" against, and the matches of the last search.
" highlight HexPairActive cterm=bold,underline gui=bold,underline
" highlight HexPairMirror ctermbg=52 guibg=#5f0000
" highlight link HexPairPageBanner Comment
" highlight link HexPairModified DiffText
" highlight link HexPairDiff DiffAdd
" highlight link HexPairFind Search

" The page and the byte under the cursor, in the statusline. Empty in
" every buffer hexpair has not touched, so one statusline serves both.
" set statusline=%f\ %h%w%m%r\ %{HexPairStatus()}%=%l,%c%V\ %P
```

With the ruler on, a page looks like this — the ruler is decoration, it
carries no bytes and is never written:

```
" hexpair: page 2/10  bytes 513-1024 of 5000  disk.img
"         00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f  0123456789abcdef
00000200: 00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f  ................
```

`HexPairStatus()` gives `hex 3/21 @0x4a2001` in the hex view and
`txt 3/21 @0x4a2001` in the text view; a page with unwritten edits is
marked `hex 3/21+ @…`, and the byte is then where the layout puts it —
use `:HexPairPages` for the counted answer once you have inserted or
deleted digits.

The plugin also bundles a filetype plugin (`ftplugin/xxd.vim`) with
editing defaults for the dump: `tabstop=10`, `expandtab`,
`shiftwidth=3` (one hex byte) and no automatic formatting, all reverted
when hex mode is toggled off. To suppress it, put
`let b:did_ftplugin = 1` into your own `~/.vim/ftplugin/xxd.vim`; to
tweak individual settings, use `~/.vim/after/ftplugin/xxd.vim` (see
`:help hexpair-ftplugin`).

Full documentation: `:help hexpair` after installation, or
[doc/hexpair.txt](doc/hexpair.txt).

## Pages

The hex view is always one page. A file smaller than a page has exactly
one; a 400 GB one has as many as it needs, and only the page on screen
is ever read.

| Command | Description |
|---|---|
| `:HexPairOpen {file} [page]` | Open `{file}` paged at `[page]` (1-based, default 1; `$` and `+N`/`-N` work here too) without loading it |
| `:HexPairPageNext[!]` / `:HexPairPagePrev[!]` | Turn the page; refuses to discard unwritten changes without `!` |
| `:HexPairPageGoto[!] {page}` | Jump to page `{page}`: a number, `+N` / `-N` to step, or `$` for the last one |
| `:HexPairGoOffset[!] {byte}` | Jump to a byte, decimal or `0x`-prefixed; 1-based, like the banner |
| `:HexPairPages` | Report the current page, total pages, the byte range shown, and the byte under the cursor |
| `:HexPairSplit [page]` / `:HexPairVSplit [page]` | A second view of the same file in another window, at `[page]` — see [above](#two-views-of-one-file) |

`<Plug>(HexPairPageGoto)` (mapping example above) prompts for a page
with `input()` instead of requiring a typed `:HexPairPageGoto {page}` —
press the key, type a number (or `+2`, `-1`, `$`), Enter.
`<Plug>(HexPairPageGotoForce)` is the same prompt but discards unsaved
changes without asking, like the `{N}` variant with `!`.

Each page is bracketed by a leading and trailing banner line (`" hexpair:
page 3/21  bytes ...`), given a comment-like appearance via the
`HexPairPageBanner` highlight group. The banner contributes no bytes: in
the dump it is recognized by its leading double quote, and in the
windowed text view — where a page of raw bytes may itself start with one
— by matching the banner text exactly, so editing it refuses the write
rather than guessing which lines are content.

A page is an ordinary Vim buffer, so its size is what everything costs:
with 16 bytes per line, the default 128 KiB page is 8192 lines. Reading
one takes hundredths of a second, writing one about a seventh. Since
`:HexPairGoOffset` reaches any byte directly, raising the page size buys
nothing but latency — see `:help hexpair-paged-size`.

`:w {file}` means "save the whole thing over there", not "save this
page": it writes the entire content being paged, with the current page's
edits in it, and leaves the original alone. For piped input that is the
only way to save, and the view adopts the file afterwards.

A file that changed on disk since the page was read is refused rather
than patched blindly — and not only by its size and timestamp, which
whole-second resolution lets an in-place writer slip past: the page's
own bytes are hashed when it is read and again before it is patched.
`g:hexpair_page_confirm = 0` answers the resize question automatically,
for scripts.

Only a write that **shortens** a file, and `:w {file}`, need a newer Vim
than the rest of the plugin: `+num64` and patch 8.2.4906+, for
`readblob()`, checked when such a write is attempted and refusing just
that write. Viewing, navigating, same-length writes and inserts run on
Vim 8.0 with nothing but `xxd`. Details: `:help hexpair-paged`.

## What it costs

Memory does not follow the size of the file. A page is read, written and
patched a block at a time, so the numbers below are the same for a file
of 8 KiB and one of 8 TiB — measured on this machine with the default
128 KiB page:

| Operation | Memory | Temporary disk space |
|---|---|---|
| Viewing a page, turning pages | 12 MB | none |
| Writing a page whose length did not change | 13 MB | about one page |
| **Inserting** bytes | 13 MB | one block of hex, ~16 MB |
| **Deleting** bytes | 29 MB | **a full copy of the file** |

Time is what does scale, and only with what has to move: a same-length
write touches the page alone, an insert moves the bytes after it, and a
delete rewrites the file — because nothing in Vim or `xxd` can make a
file shorter any other way. On this machine, at the default page size,
opening or turning a page takes about 0.03 s and a same-length write
about 0.15 s; both include reading the page's bytes back to check that
nothing else has written to them meanwhile.

The one exception to all of this is `:HexPairToggle` on a file you have
already opened normally: by the time you press it, Vim has read the whole
file into the buffer. That is exactly what `:HexPairOpen` (and `vimhex`)
exist to avoid — they read only the page they show.

## Requirements

- Vim 8.0 with patch 8.0.0794 (`count()` over a string), which every
  Vim 8.0 point release since 2017 has. Native packages need Vim 8
  anyway; a manual installation needs the patch level. Shortening a
  file, `:w {file}`, and inserting bytes with more than half the file
  after them additionally need patch 8.2.4906 and `+num64`, checked at
  the moment such a write is attempted - see
  [above](#pages). The baseline is tested: the suite runs against a
  Vim 8.0.0000 build, where everything but those three works.
- The `xxd` utility, which ships with Vim. It is looked up on `PATH`
  first and then in the Vim runtime directory (`$VIMRUNTIME`), so on
  Windows the bundled `xxd.exe` is found even when it is not on `PATH`.

## Contributing

Bug reports and patches are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md) for the repository layout, the test
harness, the reproducible release packaging and the signing policy.
Project notes for AI-assisted development live in
[CLAUDE.md](CLAUDE.md), including the architecture of the **paged
large-file mode**.

## License

Distributed under the same terms as Vim itself (the Vim License) — see
[LICENSE.md](LICENSE.md). Release notes are in
[CHANGELOG.md](CHANGELOG.md).
