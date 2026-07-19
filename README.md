# `hexpair` Vim Plugin: a Slightly Advanced Support for HEX Display and Editing in Vim

[![Build](https://github.com/michal-ruzicka/hexpair/actions/workflows/build.yml/badge.svg)](https://github.com/michal-ruzicka/hexpair/actions/workflows/build.yml)
[![GitHub Sponsors](https://img.shields.io/badge/Sponsor-GitHub%20Sponsors-ea4aaa?style=flat&logo=githubsponsors&logoColor=white)](https://github.com/sponsors/michal-ruzicka)
[![Ko-fi](https://img.shields.io/badge/Tip-Ko--fi-FF5E5B?style=flat&logo=kofi&logoColor=white)](https://ko-fi.com/michal_ruzicka)
[![Revolut](https://img.shields.io/badge/Pay-Revolut-191C1F?style=flat&logo=revolut&logoColor=white)](https://revolut.me/ruzicka_michal)

**A Vim plugin that turns the classic `:%!xxd` hex-dump workflow into a
small, reliable hex editor** — with live highlighting of the byte pair
under the cursor in *both* the HEX and the ASCII column, byte-exact
cursor mapping when toggling between the normal and the hex view, safe
`:w` while in hex mode, and forgiving editing where the offset and ASCII
columns are purely decorative.

Everything is built on `xxd` (which ships with Vim) and portable
VimScript — no `sed`, `tr`, `dd` or other external tools, so the plugin
works the same on Linux, on Windows (native Vim/gVim, where `xxd.exe` is
found in the Vim installation directory even when it is not on `PATH`),
and inside WSL.

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
  column you are in.
- **Byte-exact cursor mapping.** Toggling between the normal view and
  the hex view keeps the cursor on the *same byte* — for a multibyte
  character, on its first byte in the file encoding. The mapping stays
  exact for files with a BOM, CRLF or even mixed CRLF/LF line endings,
  and single-byte file encodings (`latin*`, `cp125x`, ...).
- **Safe writing.** `:w` in hex mode transparently converts back to
  binary before the write and regenerates the dump afterwards — the
  file on disk always contains the real bytes, never the textual dump,
  and the cursor stays on the byte it was on even when insertions
  shifted all offsets.
- **Forgiving editing.** Only the HEX column matters: the offset and
  ASCII columns are stripped before the reverse conversion, so you can
  freely insert, delete or reorder lines — inserted lines need no
  offset and no ASCII part, just hex pairs. After `:w` the dump is
  regenerated and offsets become correct again automatically.
- **Column navigation.** Commands to jump between the HEX and ASCII
  representation of the byte under the cursor, or to swap to the
  opposite column.
- **Binary correctness.** Opening a file without `-b` is handled by an
  automatic `:edit ++bin` reload, so the dump always shows the exact
  on-disk bytes (and a plain `:w` cannot silently re-encode a binary
  file).

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
nmap §h <Plug>(HexPairToggle)     " toggle hex view
nmap §< <Plug>(HexPairGoHex)      " jump to the HEX column (same byte)
nmap §> <Plug>(HexPairGoAscii)    " jump to the ASCII column (same byte)
nmap §- <Plug>(HexPairSwap)       " jump to the opposite column
```

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

and toggle the hex view with your mapping or `:HexPairToggle`. To open
a file directly in the hex view from the shell:

```sh
vim -b -c 'HexPairToggle' file.bin
```

| Command | Description |
|---|---|
| `:HexPairToggle` | Toggle between the normal content and the hex dump view |
| `:HexPairGoHex` | Move the cursor to the HEX column, staying on the same byte |
| `:HexPairGoAscii` | Move the cursor to the ASCII column, staying on the same byte |
| `:HexPairSwap` | Move the cursor to the opposite column, staying on the same byte |

Editing rules (see `:help hexpair` for details): keep bytes in the hex
area separated by at most one space — a run of two spaces marks the
start of the (ignored) ASCII column — and always write full byte pairs.

### Configuration

```vim
" bytes per dump line (default 16)
let g:hexpair_bytes_per_line = 16

" keep the global 'paste' option on while the cursor is in a hex buffer,
" restored when the cursor leaves it (set to 0 to leave 'paste' alone)
let g:hexpair_paste = 1

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
[CLAUDE.md](CLAUDE.md), including the implementation plan for the
upcoming **paged large-file mode**.

## License

Distributed under the same terms as Vim itself (the Vim License) — see
[LICENSE.md](LICENSE.md). Release notes are in
[CHANGELOG.md](CHANGELOG.md).
