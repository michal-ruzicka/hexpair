# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html); the
`Version:` header in `plugin/hexpair.vim` is the single source of truth.

## [v2.0.0-devel] – 2026-07-20

### Added
- Paged large-file mode, Stage 1 (`plugin/hexpair_paged.vim`,
  read-only so far — writing is planned but not implemented yet):
  `:HexPairOpen {file} [page]` shows one configurable-size page
  (`g:hexpair_page_size`, default 1 MiB) of an arbitrarily large file
  as a hex dump with absolute file offsets, without ever loading the
  rest of the file into a buffer — usable straight from the shell,
  e.g. `vim -c 'HexPairOpen bigfile.bin'`. `:HexPairPageNext[!]` /
  `:HexPairPagePrev[!]` / `:HexPairPageGoto[!] {N}` navigate between
  pages, refusing to discard unsaved changes without `!`;
  `:HexPairPages` reports the current page, total pages and byte
  range. Each page is bracketed by a decorative banner line (page
  number, byte range) highlighted via the new `HexPairPageBanner`
  group. Requires a newer Vim than the base plugin (`+num64` and
  patch 8.2.4906+, needed by a later write stage), checked at load
  time with a clear message if unmet; the base toggle mode is
  unaffected. See CLAUDE.md for the remaining write-path stages.
  `HexPairOpenFile({file} [, {page}])` opens a page the same way as
  `:HexPairOpen` but as a direct function call, for scripts, mappings
  or shell wrappers that build the filename programmatically — safer
  than constructing an `:HexPairOpen` command-line string for a name
  containing a space or a literal `$`, which does not fully round-trip
  through the Ex command's own argument parsing. `<Plug>(HexPairPageGoto)`
  prompts for a page number instead of needing a typed `:HexPairPageGoto
  {N}`; `<Plug>(HexPairPageGotoForce)` is the same prompt but discards
  unsaved changes without asking, like the `{N}` variant with `!`.
- `:HexPairRefresh` (`<Plug>(HexPairRefresh)`): regenerate the offset
  and ASCII columns from the current hex payload without writing to
  disk — the same round trip a toggle off followed by a toggle on
  would perform, but staying in hex mode. Validated like `:w`; an
  invalid dump refuses the refresh instead of being converted. The
  `'modified'` flag is unaffected — only the rendering changes, never
  a byte of content.

### Fixed
- The page banner's and `:HexPairPages`' byte range used to be
  0-based and inclusive (`base` to `base + len - 1`), so the last
  page's shown end was always one short of the file's total size,
  reading as though the page did not reach the end of the file. Now
  1-based and inclusive (`base + 1` to `base + len`), so the last
  page's end always equals the total exactly. Only this decorative
  text changed — the underlying page bytes read and shown were always
  correct.
- `:HexPairOpen` with an out-of-range or non-numeric page number used
  to still create and rename a scratch buffer (to `<file> [hexpair
  page]`) before checking whether the page existed, leaving an empty,
  inactive but real-looking buffer behind. It now validates the page
  first and leaves the current buffer completely untouched on a bad
  page number — nothing is created.
- Data loss: toggling hex mode off used to unconditionally mirror the
  buffer's modified state from BEFORE hex mode was entered, so an edit
  made to the dump on an until-then-unmodified buffer silently cleared
  `'modified'` on toggle-off — `:q` would then discard it without a
  warning. The buffer is now tracked for real content changes made
  while in hex mode (via `b:changedtick`, unaffected by cursor
  movement) independently of the pre-hex-mode state, in both
  directions: a pre-existing unsaved change is still preserved, and an
  edit made purely in hex mode now correctly marks the buffer modified
  on toggle-off.

## [v1.1.0] – 2026-07-19

### Added
- Bundled filetype plugin (`ftplugin/xxd.vim`) with dump-editing
  defaults — `tabstop=10`, `expandtab`, `shiftwidth=3` (one hex byte),
  no automatic formatting, wrapping or indenting — applied to any
  buffer with `filetype=xxd` and fully reverted via `b:undo_ftplugin`
  when the hex view is toggled off (including buffers whose original
  filetype was empty, where no `FileType` event fires). Suppress with
  `let b:did_ftplugin = 1` in a personal `ftplugin/xxd.vim`, or
  override individual settings in `after/ftplugin/xxd.vim`
  (`:help hexpair-ftplugin`).
- `g:hexpair_paste` (default on): the global `'paste'` option is
  switched on while the cursor is in a hex-mode buffer and restored to
  its previous value when the cursor leaves it or hex mode is toggled
  off, so insert-mode mappings and abbreviations cannot mangle typed
  hex; all other buffers keep the user's own `'paste'` state. The
  buffer's `'expandtab'` is preserved across the switch.

- Dump validation: a character in the hex area that is not a hex
  digit, or an odd total number of hex digits, now aborts `:w` and
  hex-mode toggle-off with an error and the cursor parked on the
  offender, instead of silently dropping data — the file on disk and
  the dump keep their previous content. This also limits the damage
  after an `u` that undid the conversion itself: the non-dump content
  is refused rather than converted.
- `:e` / `:e!` while hex mode is active now regenerates the dump from
  the freshly read file and keeps hex mode and the cursor byte offset,
  instead of leaving raw binary content in a buffer that still
  believed it was a dump.

### Changed
- Documented mapping examples now use the conventional `<Leader>`
  prefix instead of `§`, which only exists on some keyboard layouts
  (e.g. Czech); the plugin still defines no mappings of its own. The
  help and README now also explain the `<Leader>`/`mapleader` and
  `<Plug>` mechanisms for readers new to them.

## [v1.0.0] – 2026-07-19

Initial public release, consolidating fourteen internal iterations that
shaped the plugin before this import; the highlights of that evolution,
in one place:

### Added
- Hex view toggle (`:HexPairToggle`) built on `xxd -g 1`, with
  `filetype=xxd` syntax highlighting and automatic `:edit ++bin`
  reload for buffers not opened in binary mode.
- Live pair highlighting: the byte under the cursor is highlighted in
  both the HEX and the ASCII column, with direction-aware groups
  (`HexPairActive` for the cursor side, `HexPairMirror` for the
  counterpart).
- Column navigation commands: `:HexPairGoHex`, `:HexPairGoAscii`,
  `:HexPairSwap` — jump between the two representations of the byte
  under the cursor.
- Safe `:w` in hex mode: transparent reverse conversion before the
  write and dump regeneration afterwards; the file on disk always
  receives real binary content.
- Forgiving editing: the offset and ASCII columns are stripped before
  the reverse conversion and are purely decorative — lines may be
  inserted (bare hex pairs, optionally indented), deleted or
  reordered; offsets and ASCII columns self-heal on the next `:w`.
- Byte-exact cursor mapping across toggles and writes: the cursor
  stays on the same byte (first byte of a multibyte character),
  including across dumps reflowed by insertions. Exact for files with
  a BOM, CRLF or mixed CRLF/LF line endings, and single-byte file
  encodings; utf-16 remains approximate.
- Per-buffer snapshot of `g:hexpair_bytes_per_line`, so changing the
  global cannot desynchronize an open dump.
- `g:hexpair_debug` position-mapping trace for field diagnostics.
- Windows portability: the former `sed | tr` reverse pipeline
  rewritten in pure VimScript; `xxd` resolved from `$VIMRUNTIME` when
  not on `PATH`.
- Vim help documentation (`:help hexpair`).

### Fixed (during the internal iterations)
- Forced `noeol` used to hide a genuine final newline from the dump
  and could drop it on write.
- Non-binary buffers used to be dumped after read-time conversions
  (CR stripping, transcoding) without a reload, silently diverging
  from the on-disk bytes.
- Cursor placement after a `++bin` reload used raw line/column
  coordinates and drifted on files with a BOM or transcoded content;
  replaced by byte-offset anchoring via `line2byte()` over raw bytes.
- Stale screen state after conversions addressed with an explicit
  full redraw.


[v2.0.0-devel]: https://github.com/michal-ruzicka/hexpair/compare/v1.1.0...devel
[v1.1.0]: https://github.com/michal-ruzicka/hexpair/compare/v1.0.0...v1.1.0
[v1.0.0]: https://github.com/michal-ruzicka/hexpair/releases/tag/v1.0.0
