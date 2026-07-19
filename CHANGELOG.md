# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html); the
`Version:` header in `plugin/hexpair.vim` is the single source of truth.

## [v1.1.0-devel] – 2026-07-19

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


[v1.1.0-devel]: https://github.com/michal-ruzicka/hexpair/compare/v1.0.0...devel
[v1.0.0]: https://github.com/michal-ruzicka/hexpair/releases/tag/v1.0.0