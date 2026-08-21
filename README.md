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
in memory — or on the machine at all, a disk image, a device — is no
different from a small one. Editing an 8 GiB file costs the same 13 MB
of memory as editing an 8 KiB one.

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
nmap <Leader>g <Plug>(HexPairPageGoto)      " prompt for a page number
nmap <Leader>b <Plug>(HexPairGoOffset)      " prompt for a byte, 1-based (0x... ok)
nmap <Leader>? <Plug>(HexPairPages)         " where am I: page, range, cursor byte

" Uppercase variants: the same, but discard unwritten changes without
" asking (like the ! commands) - handy for skimming through a file.
nnoremap <silent> <Leader>J :HexPairPageNext!<CR>
nnoremap <silent> <Leader>K :HexPairPagePrev!<CR>
nmap <Leader>G <Plug>(HexPairPageGotoForce)
nmap <Leader>B <Plug>(HexPairGoOffsetForce)
```

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
| `:HexPairOpen[!] {file} [page]` | Open `{file}` paged, without loading it |
| `:HexPairPageNext[!]` / `:HexPairPagePrev[!]` / `:HexPairPageGoto[!] {n}` | Turn pages (`!` discards unwritten changes) |
| `:HexPairGoOffset[!] {byte}` | Jump to a byte, decimal or `0x`-prefixed, turning the page if needed; 1-based, like the banner |
| `:HexPairPages` | Report page X of Y, the offsets covered, the file size and the byte under the cursor |

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

### Configuration

```vim
" bytes per dump line (default 16)
let g:hexpair_bytes_per_line = 32

" bytes per page (default 128 KiB); must stay a positive multiple of
" g:hexpair_bytes_per_line. A page is an ordinary Vim buffer, so a bigger
" one costs what that many lines cost - see "What it costs" below
let g:hexpair_page_size = 1024 * 1024

" whether a write that changes the page's length says what it will cost
" and asks first (default 1); 0 answers yes automatically, e.g. in a script
let g:hexpair_page_confirm = 0

" keep the global 'paste' option on while the cursor is in a hex buffer,
" restored when the cursor leaves it (default 1; 0 leaves 'paste' alone)
let g:hexpair_paste = 0

" highlight overrides
highlight HexPairActive cterm=bold,underline gui=bold,underline
highlight HexPairMirror ctermbg=52 guibg=#5f0000

" position-mapping trace for debugging (inspect with :messages)
let g:hexpair_debug = 1
```

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
| `:HexPairOpen[!] {file} [page]` | Open `{file}` paged at `[page]` (1-based, default 1) without loading it |
| `:HexPairPageNext[!]` / `:HexPairPagePrev[!]` | Turn the page; refuses to discard unwritten changes without `!` |
| `:HexPairPageGoto[!] {N}` | Jump to page `{N}` |
| `:HexPairGoOffset[!] {byte}` | Jump to a byte, decimal or `0x`-prefixed; 1-based, like the banner |
| `:HexPairPages` | Report the current page, total pages, the byte range shown, and the byte under the cursor |

`<Plug>(HexPairPageGoto)` (mapping example above) prompts for a page
number with `input()` instead of requiring a typed `:HexPairPageGoto
{N}` — press the key, type a number, Enter.
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
one takes hundredths of a second, writing one about a third. Since
`:HexPairGoOffset` reaches any byte directly, raising the page size buys
nothing but latency — see `:help hexpair-paged-size`.

`:w {file}` means "save the whole thing over there", not "save this
page": it writes the entire content being paged, with the current page's
edits in it, and leaves the original alone. For piped input that is the
only way to save, and the view adopts the file afterwards.

A file that changed on disk since the page was read is refused rather
than patched blindly. `g:hexpair_page_confirm = 0` answers the resize
question automatically, for scripts.

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
file shorter any other way.

The one exception to all of this is `:HexPairToggle` on a file you have
already opened normally: by the time you press it, Vim has read the whole
file into the buffer. That is exactly what `:HexPairOpen` (and `vimhex`)
exist to avoid — they read only the page they show.

## Requirements

- Vim 8+ (native packages; the plugin itself uses lambda expressions,
  so Vim 8.0+ is required even for manual installation).
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
