# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html); the
`Version:` header in `plugin/hexpair.vim` is the single source of truth.

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


[v1.0.0]: https://github.com/michal-ruzicka/hexpair/releases/tag/v1.0.0