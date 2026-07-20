# hexpair — project notes for Claude

## What this is

A Vim plugin that turns the classic `:%!xxd` workflow into a small,
reliable hex editor: live highlighting of the byte pair under the cursor
in both the HEX and ASCII columns, byte-exact cursor mapping between the
normal and the hex view, a safe `:w` path, and forgiving editing where
the offset and ASCII columns are purely decorative.

Everything is pure VimScript plus the `xxd` utility that ships with Vim.
**Portability is a core project value**: no `sed`, `tr`, `dd` or any
other external tool may be introduced — the plugin must behave
identically on Linux, native Windows (Vim/gVim with `xxd.exe` from
`$VIMRUNTIME`) and WSL. This is the main differentiator against
alternatives such as rootkiter/vim-hexedit.

## Repo layout

```
README.md             - end-user docs (bundled in the release tarball)
CONTRIBUTING.md       - developer docs (bundled in the release tarball)
CHANGELOG.md          - Keep-a-Changelog formatted release notes
LICENSE.md            - Vim License + copyright notice
CLAUDE.md             - this file
pack-release          - POSIX wrapper around pack-release.py
pack-release.cmd      - Windows wrapper around pack-release.py
pack-release.py       - the packaging implementation (python3, stdlib
                        only); byte-identical tarball on every platform
                        by construction
plugin/hexpair.vim    - the plugin; header carries Version: and Date:
                        (single source of truth, parsed by pack-release.py)
ftplugin/xxd.vim      - dump-editing defaults (guarded by b:did_ftplugin,
                        reverted via b:undo_ftplugin)
doc/hexpair.txt       - Vim help (:help hexpair)
test/run-tests.sh     - headless regression suite (vim -es)
dist/                 - packaged release tarballs (gitignored)
```

## Architecture (plugin/hexpair.vim)

One script, script-local functions, three public surfaces: the
commands (`:HexPairToggle`, `:HexPairGoHex`, `:HexPairGoAscii`,
`:HexPairSwap`), the `<Plug>` mappings (no default key mappings — the
user maps them in vimrc), and the highlight groups
(`HexPairActive` / `HexPairMirror`).

Key function map:

- `s:Layout()` — column arithmetic of a `xxd -g 1 -c N` dump
  (`hexstart=11`, `hexend=hexstart+3N-2`, `asciistart=hexend+3`).
  Reads the per-buffer snapshot `b:hexpair_n`, never the global
  directly, so a mid-session change of `g:hexpair_bytes_per_line`
  cannot desynchronize an open dump.
- `s:ResolveXxd()` — finds `xxd` on `PATH`, then `$VIMRUNTIME`
  (Windows), shell-escaped; result cached in `s:xxd`.
- `s:StripDumpLine()` — reduces a dump line to its hex payload
  (leading whitespace → offset up to the first `:` → everything from
  the first double space → non-hex characters). Pure VimScript; this
  used to be a `sed | tr` pipeline and was rewritten for Windows.
- `s:ReverseDump()` — strips the whole buffer in-place (`undojoin`ed)
  and filters through `xxd -r -p`. **Offsets and the ASCII column are
  purely decorative by design** — users may insert bare hex lines,
  reorder lines, leave stale offsets.
- `s:ToHex()` / `s:FromHex()` — the toggle. On a non-binary buffer,
  ToHex re-reads the file with `:edit ++bin` (unmodified, file-backed
  buffers only; otherwise warn) — read-time conversions (BOM
  stripping, CRLF folding, fileencoding transcoding) cannot be undone
  after the fact. After that reload the buffer intentionally *stays*
  binary even when hex mode is toggled off.
- `b:hexpair_dump_tick` — `b:changedtick` snapshot taken right after
  the dump is (re)generated (`ToHex`, `PostWrite`, `PostReload`).
  `FromHex` compares it against the current tick *before* calling
  `ReverseDump()` (which itself advances the tick) to tell whether the
  user made a real edit while in hex mode, independently of
  `b:hexpair_saved.modified` (the state from *before* hex mode was
  entered). Toggle-off only clears `'modified'` when *neither* is
  true — mirroring only the pre-hex-mode state here previously caused
  a real edit made purely in hex mode to be silently discarded on
  `:q` (`'modified'` incorrectly cleared on toggle-off).
- Cursor position mapping — always via **byte offsets**, never
  line/column coordinates:
  - normal→offset: `line2byte(line('.')) + col('.') - 2`;
  - dump→offset: `s:DumpOffset()` counts the hex pairs actually
    present (stripped) on preceding lines plus, on the current line,
    the pairs before the cursor — exact even in a heavily edited dump;
  - offset→normal: `:goto off+1`;
  - offset→dump: `s:DumpPos()` (canonical layout);
  - non-binary load: `s:PreReloadPos()` (line + within-line file-byte
    column + BOM length, captured from the converted view) and
    `s:PostReloadOffset()` (line start anchored with `line2byte()`
    over the raw bytes — exact regardless of line endings, including
    mixed CRLF/LF). utf-16/ucs-2 do not preserve line boundaries
    across the reload and remain approximate.
- Write path — buffer-local `BufWritePre`/`BufWritePost`: convert
  back, let Vim write, regenerate the dump, restore the cursor to the
  *same byte* (offsets may have shifted if bytes were inserted).
- `s:ValidateDump()` — runs before every reverse conversion (`:w` and
  toggle-off): a non-hex character in the payload region or an odd
  total digit count refuses the conversion (throw aborts the write;
  toggle-off errors and stays in hex mode), cursor parked on the
  offender. Mirrors the payload-region logic of `s:StripDumpLine()` —
  keep them in sync (invariant 1).
- `s:PostReload()` — `BufReadPost` on the hex buffer: `:e`/`:e!`
  re-dumps the fresh content, refreshes the toggle-off snapshot and
  restores the cursor from `b:hexpair_last_pos` (tracked on every
  `CursorMoved` in `s:Highlight()`, because at `BufReadPre` time the
  old buffer content is already gone).
- `s:PasteOn()` / `s:PasteOff()` — the global `'paste'` option is
  switched on while the cursor is in a hex buffer (`BufEnter`/`BufLeave`
  plus the toggle lifecycle) and restored elsewhere; `g:hexpair_paste`
  opts out. In `s:FromHex()`, `s:PasteOff()` must run *before* the
  filetype restore ('paste' off restores the options it overrode, only
  then may `b:undo_ftplugin` revert them), and when the restored
  filetype is empty no `FileType` event fires, so the plugin executes
  `b:undo_ftplugin` and clears `b:did_ftplugin` itself.
- `g:hexpair_debug` — echomsg trace of every position mapping step
  (`:messages`); keep it working, it has already caught two field bugs.

### Invariants — do not break

1. The double-space rule is shared among `s:StripDumpLine()`,
   `s:DumpOffset()` and `s:ValidateDump()`: a run of two spaces ends
   the hex payload of a line in *all three*. A cursor past a double
   space must never map to a byte that the reverse conversion would
   not write, and the validator must scan exactly the payload region
   that the stripper would keep.
2. Round trip (toggle on → toggle off, no edits) is byte-identical for
   any input, and the cursor offset is preserved exactly.
3. `:w` in hex mode writes the real binary content and leaves the
   buffer in hex mode, unmodified flag cleared, cursor on the same byte.
4. No default key mappings; commands + `<Plug>` only.
5. English only: code, comments, docs, commit messages.
6. Author attribution: `Michal Růžička <ruzicka.mich@gmail.com>`.

## Testing

`test/run-tests.sh` drives headless Vim (`vim -es -u NONE`) over
generated fixtures and asserts byte-exact expectations (file content
via `xxd` reference dumps, cursor positions via `line()`/`col()`/
`line2byte()`). Python3 generates fixtures (binary patterns, mixed
line endings, encodings) — `printf` in dash does not expand `\x`
escapes, which has silently neutered tests before; always generate
binary fixtures with python.

Every change ships with a test. When a field bug is diagnosed (the
project history includes several: forced `noeol` hiding the final
newline, layout desync on `g:hexpair_bytes_per_line` change, stale
`FileOffsetNonBinary` predictions on mixed CRLF/LF, toggle-off
mirroring only the pre-hex-mode `'modified'` state and silently
discarding an edit made purely in hex mode), first reproduce it as a
failing test, then fix.

## Versioning and releases

Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
(`MAJOR.MINOR.PATCH`). `Version:` and `Date:` in the
`plugin/hexpair.vim` header are the single source of truth;
`pack-release.py` (run via the `pack-release` / `pack-release.cmd`
wrappers) parses them and normalizes all archive timestamps to `Date:`
for reproducible tarballs (see CONTRIBUTING.md). Bump both together. Commits are
SSH-signed, release tarballs GPG-signed locally — CI never publishes.

---

## PLANNED: paged large-file mode

The next major feature. Design agreed with the maintainer; implement
in this order, with verification tests **before** wiring the UI.

### Goal

Edit files of arbitrary size (multi-GB) without loading them into a
Vim buffer: show one *page* (configurable, default 64 MiB) as a hex
dump with **absolute** file offsets, navigate between pages, and write
changes back so that unchanged parts of the file on disk are never
rewritten (for same-length edits).

### Vim version gate

The splice write path requires `readblob({fname}, {offset}, {size})`
— available since **patch 8.2.4906**. On plugin load of the paged
feature (not of the base plugin), check
`has('patch-8.2.4906')` and fail loudly with a clear error message
instead of failing silently on older Vim. The base (whole-file) mode
keeps its current Vim 8.0 requirement.

### Reading a page

- `xxd -s <offset> -l <len> -g 1 -c <n> <file>` into a **scratch
  buffer** (`buftype=acwrite`, `bufhidden=hide`, no swapfile). `-s`
  makes xxd print absolute offsets, so the offset column shows true
  file positions natively.
- Page state in buffer-local vars: file path, page index, page start
  offset, page length, `getfsize()` and `getftime()` snapshot at read
  time (staleness detection), `b:hexpair_n`.
- Existing pair highlighting, column jumps and editing semantics work
  unchanged — the page layout is identical to today's dump. Position
  helpers must add the page base offset where absolute positions are
  reported.

### Commands (paged mode)

- `:HexPairOpen <file> [page]` — open paged view (entry point; the
  whole-file toggle stays as-is and is not used for paged buffers).
- `:HexPairPageNext` / `:HexPairPagePrev` — refuse to leave a modified
  page without `!` (or a prior `:w`).
- `:HexPairPageGoto <N>` — jump to page N (1-based).
- `:HexPairPages` — report `page X of Y, offsets A–B of total S bytes`.
- `g:hexpair_page_size` — default `64 * 1024 * 1024`; validate it is a
  positive multiple of `g:hexpair_bytes_per_line`.

### Writing a page — two mechanisms, chosen by length

**Same length (the common case — value overwrites):** in-place patch
via xxd's documented reverse-with-seek behaviour. Pipeline: strip the
edited page dump → `xxd -r -p` to a raw temp file → verify the length
equals the page length → generate a canonical dump of the temp with
absolute offsets (`xxd -o <base>`; if the local xxd lacks `-o`,
prepend offsets in VimScript — one printf per line) → run
`xxd -r <dump> <target-file>` with the target as an **argument** (an
argument is opened read-write and patched in place; shell redirection
`>` would truncate — never use it). Cost is O(page), the rest of the
file is untouched.
**Pre-implementation verification (mandatory):** prove on both Linux
xxd and Windows `xxd.exe` from `$VIMRUNTIME` that (a) the target is
not truncated, (b) no padding is appended, (c) bytes outside the
patched range are bit-identical before/after. Automate as tests.

**Changed length (insert/delete):** splice in pure VimScript —
`readblob(file, off, len)` block-copy loop (block size ~8 MiB, bounded
memory) of head → temp, append the edited page's raw bytes, block-copy
tail, then replace the original by block-copying back (not `rename()`:
temp usually lives on a different filesystem, notably with `/mnt/c/...`
paths under WSL). O(file size), therefore:
- always tell the user the size delta and that the whole file must be
  rewritten, and require an explicit confirmation (`confirm()`);
- keep the temp as a recovery copy on failure; delete on success in
  `try/finally`.

**Both paths:** before any write, compare `getfsize()`/`getftime()`
against the read-time snapshot; refuse with a clear message if the
file changed on disk (another process may be writing it). After a
successful write, refresh the snapshot and re-read/regenerate the
page, cursor restored by absolute byte offset.

### Temp file hygiene

`tempname()` only (private 0700 temp dir on Unix; per-user `%TEMP%`
ACLs on Windows) — never predictable names in shared locations.
Delete in `try/finally`. Document in the help file that a
file-size-sized temp is needed for length-changing writes.

### Testing the paged mode

Extend `test/run-tests.sh`: fixture ≥ 3 pages with recognizable
per-page content; assert page boundaries, absolute offsets in the
dump, navigation guards on modified pages, same-length patch touches
only the edited range (compare full-file hashes outside the range),
splice correctness for grow and shrink, staleness refusal, and the
version gate error message on a simulated old Vim
(`has()` cannot be faked — factor the check into a function and test
its failure branch directly).

### Explicit non-goals (for now)

- No attempt at insert/delete without a full-file rewrite (filesystems
  cannot splice in place).
- No memory-mapped or streaming views; one page = one buffer.
- utf-16 position mapping stays approximate in the base mode; paged
  mode is byte-oriented and unaffected.
