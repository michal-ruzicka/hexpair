# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html); the
`Version:` header in `plugin/hexpair.vim` is the single source of truth.

## [v2.2.0-devel] – 2026-08-24

### Changed
- **`<Leader>G` is the suggested key for `:HexPairPageGoto!`** - ask which
  page to go to, discarding unwritten changes - where `hexpair.vimrc` and
  the `README.md` example both said `<Leader>P`. It belongs beside
  `<Leader>g`, which is the same question without the bang, the way every
  other pair here is a letter and its capital; `G` was the go-to-mark key
  until v2.1.0 moved the marks under `<Leader>m`, and freeing it is what
  the pair was waiting for. The plugin still defines no key mappings of
  its own - this is the mapping file and the documentation.

### Fixed
- **A jump to a byte on another page keeps the scroll-bound windows
  together.** In `vimhexdiff`, walking the differences with
  `:HexPairDiffNext` / `:HexPairDiffPrev` came apart the moment a jump
  crossed a page boundary: the other window turned to the right page but
  stayed at its first byte, while this one went on to the byte it was
  going to - two windows scrolling in step through different parts of two
  files, which is the one thing `'scrollbind'` is there to prevent. A
  page turn and the cursor's arrival are two steps, and the windows were
  being levelled between them: `:syncbind`, which is what tells Vim where
  level is after a page has been loaded under a window, also swallows the
  next scroll it would have followed - and that next scroll was this
  window going to the byte. The levelling now happens after both steps,
  and the bound window lands on the same byte rather than on the page's
  first. Everything that goes to a byte is fixed by the same change:
  `:HexPairDiffNext` / `:HexPairDiffPrev`, `:HexPairFind` and its
  repeats, `:HexPairGoOffset`, `:HexPairGoMark` and
  `:HexPairModifiedNext` / `:HexPairModifiedPrev`.

## [v2.1.0] – 2026-08-24

### Added
- **Search across the file.** `:HexPairFind {bytes}` looks through the
  whole file a block at a time and lands the cursor on the byte it found,
  turning the page on the way; a pattern is bytes (`de ad be ef`,
  `deadbeef`) and `?` stands for any nibble. `:HexPairFindText {string}`
  searches for the bytes of a string, `:HexPairFindNext` /
  `:HexPairFindPrev` repeat it either way and obey `'wrapscan'`, and
  every match on the page is marked (`HexPairFind`) - including one that
  straddles a page boundary, which is marked on both pages it touches.
  `/` could never do this: it searches the page on screen, which is
  a window on the file. A search reads the file a megabyte at a time, and
  from 16 MB up says how far it has got, since a scan of a large file takes
  long enough to look like a hang; `CTRL-C` stops it, and nothing has been
  changed by then. `:HexPairDiffNext` reports the same way.
- **Replacing what was found.** `:HexPairReplace {bytes}` over the match
  under the cursor, `:HexPairReplaceAllInPage {pattern} / {bytes}` over
  every match on the page in view - the scope is in the name, because
  everything here writes one page at a time and a file-wide replace would
  be a different mechanism, not a bigger version of this one. Both edit
  the page exactly as typing over the dump would, so nothing reaches the
  file until `:w` does, and a replacement of a different length asks the
  same question any other insertion does.
- **`:HexPairDiff [file]`** marks every byte of the page that differs
  from the same offset of another file (`HexPairDiff`) and says how many
  differ; `:HexPairDiffNext` / `:HexPairDiffPrev` walk the whole file for
  the next **change** - a run of differing bytes is one change however
  long it is, so the jumps move between changes rather than through the
  bytes of one, and backwards lands on a change's first byte as `[c` does
  in a diff. `:HexPairDiff!` stops comparing and clears the marking
  (`<Plug>(HexPairDiffClear)`, and `<Plug>(HexPairFindClear)` for
  `:HexPairFind!`). The shell wrapper gains `vimhexdiff FILE1 FILE2`,
  which opens both side by side, each marking what differs from the
  other, cursors on the first difference and the windows scroll-bound -
  and a page turn in either window takes the other with it, to the page
  holding the same byte, since `'scrollbind'` promises the two move
  together and a page turn is the one kind of scrolling Vim cannot
  follow on its own (`g:hexpair_bind_pages`).
- **Marks in the file**: `:HexPairMark {name}`, `:HexPairGoMark {name}`,
  `:HexPairMarks`, `:HexPairMarkDelete {name}`, and the byte a mark
  stands on underlined on the page (`HexPairMark`,
  `g:hexpair_show_marks`). All of them are reachable from a key: the
  three that need a name ask for it and complete the names that exist
  (`<Plug>(HexPairMark)`, `<Plug>(HexPairMarkDelete)`,
  `<Plug>(HexPairGoMark)`). Vim's own marks are positions in a buffer, and
  a paged buffer holds a different part of the file from one page to the
  next; these are absolute byte offsets kept per file, shared by every
  view of it.
- **`HexPairModified`**: the bytes edited and not yet written are marked
  in both columns, so an edit in a dump no longer looks exactly like
  everything around it (`g:hexpair_show_modified` turns it off). It links
  to `DiffChange` rather than the closer-sounding `DiffText`, whose own
  default is a red background with no foreground - black on red for
  anyone with a light background.
- **The markings are drawn in the windowed text view too**, one column
  per byte where the dump gives a byte three: the bytes you edited, the
  bytes that differ from the file being compared with, the matches of a
  search, and the byte a mark stands on. The line break that ends a
  text-view line is a byte of the page with no column of its own, and is
  therefore the one byte never marked.
- **`:HexPairModifiedNext` / `:HexPairModifiedPrev`** walk between the
  runs of edited bytes the way `:HexPairDiffNext` walks changes: bytes
  that touch are one edit, the cursor lands on the first byte of each,
  and the message says which of how many. No scan of the file is needed -
  turning a page needs an unmodified buffer or a bang that discards it,
  so bytes edited and not yet written only ever exist on the page in
  view.
- **`hexpair.vimrc`**: the mappings the maintainer uses, shipped in the
  repository and the release tarball so that a vimrc can source them
  rather than copy them - `runtime pack/*/start/hexpair/hexpair.vimrc`,
  one line that resolves on Linux, Windows and WSL alike because
  `'runtimepath'` already names each platform's own per-user directory.
  It never takes a key that is already mapped, and carries every option
  and highlight group as a commented-out example.
- **Every command under a short name too**: `:HPFind`, `:HPToggle`,
  `:HPReplaceAllInPage` - same arguments, same bang, same completion,
  because `:HexPair…` is a lot to type at a `:` prompt.
  `g:hexpair_short_commands = 0` leaves that namespace alone.
- **Prompting `<Plug>` targets** for the commands that take something
  typed: `<Plug>(HexPairFind)`, `<Plug>(HexPairFindText)` and the three
  mark ones above, each completing what it can - the same shape
  `<Plug>(HexPairPageGoto)` has had. The Visual-mode
  `<Plug>(HexPairSelection)` also puts the selection back when it has
  reported on it: asking about a selection from the `:` line is what
  ends Visual mode, and losing it to look at it is not a trade worth
  making.
- **`:HexPairGoOffset +N` / `-N`** steps from the byte the cursor is on,
  crossing pages like a position does.
- **`:HexPairOpen!`** abandons a modified buffer in the window, the bang
  README had documented for a year and the command never had.
- **A data inspector.** `:HexPairInspect` (`<Plug>(HexPairInspect)`)
  reads the bytes at the cursor as the numbers they could be: 8, 16, 32
  and 64 bits wide, unsigned and signed, little- and big-endian, plus
  `float32` and `float64`, with the byte itself also shown as a
  character, in binary and in octal - and what the bytes would be as
  text: UTF-8, UTF-16 and UTF-32, each saying what is wrong with the
  bytes (an overlong sequence, a lone surrogate, a value past U+10FFFF)
  rather than reporting a code point for something that is not one. The
  bytes are the page's, as the buffer holds them — edits included — and
  stop at its end, where the wider rows say how many are left rather than
  reaching into a page that is not on screen.
- **`:HexPairSelection`** (`<Plug>(HexPairSelection)`, worth mapping in
  Visual mode as well as Normal) says how many bytes a Visual selection
  covers and which, 1-based like the banner, so the numbers can be typed
  straight into `:HexPairGoOffset`. Asked from Visual mode it puts the
  selection back and waits for a key, since Vim's own `-- VISUAL --` is
  drawn over the message line the moment it gets there. A blockwise
  selection, whose bytes are not one run, leads with the count and says
  how many lines and how many per line.
- **`HexPairStatus()`** for `'statusline'`: `hex 3/349 @0x50a01 (330241)`
  in the hex view, `txt 3/349 @0x50a01 (330241)` in the text view, and
  an empty string in every buffer hexpair has not touched, so one
  statusline serves both. It never walks the page — it is called on every
  cursor movement — and marks a page with unwritten edits with a `+`.
- **`g:hexpair_ruler`** (default 0): a ruler line between the banner and
  the dump, numbering the byte columns — two digits over each hex byte,
  the low nibble over each ASCII character. Like the banners it starts
  with a `"` and therefore carries no bytes.
- **`:HexPairPageGoto` takes `$` and `+N`/`-N`** as well as a page
  number, at the command line and at the `<Plug>` prompt alike — and
  therefore in `vimhex` too: `vimhex disk.img '$'` opens the end of a
  file without working out how many pages it has.
- **`:HexPairSplit [page]` and `:HexPairVSplit [page]`**: a second view
  of the same file in a new window, showing a page named the way
  `:HexPairPageGoto` names one and counted from the view you are in. The
  two views share nothing but the file — each has its own buffer, page,
  cursor and unwritten changes, and a `:w` in either patches only the
  page that view holds, so one region can be read while another is
  edited. Previously a second `:HexPairOpen` of the same file failed with
  `E95`, because the buffer's name was the file's alone; the second one
  is now numbered (`disk.img [hexpair page #2]`).
- **`g:hexpair_split_views`** (default 0): with it set, a plain `:split`,
  `:vsplit` or `:tab split` of a hex page becomes an independent view of
  the same file too, opened on the same page and byte — and a split of
  the text view stays a text view. Left off by default, because a page is
  thousands of lines and looking at two parts of one page in two windows
  is what `:split` is for everywhere else in Vim.
- **The page's own bytes are hashed** when it is read and again before it
  is patched, so a writer that changes bytes in place within the same
  second — invisible to the file's size and modification time, which is
  all a portable Vim can see — is caught rather than overwritten. It
  costs one page read on either side (a page turn 13 ms → 26 ms, a
  same-length write 129 ms → 144 ms at the default page size, both
  independent of the size of the file). It also replaces the modification
  time as the freshness test: what a write now asks is whether **its own
  page** changed, not whether the file did, so a second view of the same
  file — or any other process writing elsewhere in it — no longer locks a
  write out. A file whose *length* changed is still refused outright,
  since that moves every page after the change.

### Changed
- **A page is scanned with whole-page regexes instead of a walk over its
  lines**, which is most of what a write used to cost. On the default
  128 KiB page, measured on the author's machine: a same-length `:w`
  goes from 571 ms to 129 ms, a toggle to the text view from 539 ms to
  83 ms, and `:HexPairPages` from 274 ms to under a millisecond. Nothing
  about the payload rule changed — the per-line rule is still the
  reference the whole-page pass is tested against, on a page of
  thousands of lines. One consequence is visible: the bytes before the
  cursor's line are counted from the digits of the preceding lines as
  one run rather than rounding each line down on its own, which is what
  `xxd -r -p` does when the page is written back, so a heavily edited
  page with an odd number of digits on some line reports the byte the
  write would actually produce.
- **A page of a file the user cannot write opens `'readonly'`**, so `:w`
  refuses it with Vim's own E45 the moment the page is opened, instead
  of converting the page and surfacing a `Permission denied` from `xxd`
  about a temporary file. `:w!` overrides it as everywhere else.
- `:HexPairGoOffset` refuses a hex number written without the `0x`
  (`ff`), which used to be read as the decimal 0 and reported as "byte
  positions start at 1, not 0" — a complaint about the wrong thing.

### Fixed
- **The cursor in the gap between the hex and the ASCII column** reported
  the first byte of the NEXT line rather than the last of its own: the
  pairs counted before it were the whole line's. `:HexPairPages`, the
  byte a write puts the cursor back on and the statusline all read that.
- **`g:hexpair_debug` does something again.** The documented
  position-mapping trace had lost every one of its call sites in the
  v2.0.0 rewrite, while `README.md` and the plugin header went on
  describing it. It traces the transitions — a page load, the `++bin`
  reload, a byte turned into a position and a position turned back into
  a byte in either view, and what a write found.
- **The plugin runs on the Vim it claims again.** `count()` over a
  string (patch 8.0.0794) and Blob literals (8.1.0735) had made
  everything past *displaying* a page fail on Vim 8.0, which the docs
  promised for viewing, navigating, same-length writes and in-place
  inserts. Verified against a Vim 8.0.0000 build: only the splice paths
  are refused there, each with the `readblob()` gate message.
- **A cursor in the offset column** reported a byte a few along from the
  line's first: the offset's own digits were counted like any other hex
  payload, so `00000210:` read as four bytes of nothing.
  `:HexPairPages`, the byte a write puts the cursor back on and the data
  inspector all read that. It is the line's first byte now, which is
  what the column says.
- Documentation that had stopped being true: a Vim requirement justified
  by lambda expressions the plugin no longer uses, and a Limitations
  section still describing undo across the conversion boundary and a
  plugin that "operates on the whole buffer", which paging replaced.

## [v2.0.0] – 2026-08-21

### Added
- **Paged large-file mode**, the reason for the major version:
  `:HexPairOpen {file} [page]` shows one configurable-size page
  (`g:hexpair_page_size`, default 128 KiB) of an arbitrarily large file
  as a hex dump with absolute file offsets, without ever loading the
  rest of the file into a buffer — usable straight from the shell,
  e.g. `vim -c 'HexPairOpen bigfile.bin'`. `:HexPairPageNext[!]` /
  `:HexPairPagePrev[!]` / `:HexPairPageGoto[!] {N}` navigate between
  pages, refusing to discard unsaved changes without `!`;
  `:HexPairPages` reports the current page, total pages and byte
  range. Each page is bracketed by a decorative banner line (page
  number, byte range) highlighted via the new `HexPairPageBanner`
  group. `HexPairOpenFile({file} [, {page}])` opens a page the same way as
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
- **`:w` on a paged view writes just that page**, by one of three
  mechanisms chosen by what the edit did to its length. An edit that
  KEPT the length - overwriting values, the common case - patches the
  page **in place** through `xxd -r` with the target as an argument: the
  file keeps its length and every byte outside the page keeps its
  content, at a cost independent of the file's size. An edit that
  INSERTED bytes moves only what follows them - the tail is shifted
  right in place with `xxd` and the page patched in, so the head of the
  file is never even read, appending to the last page moves nothing at
  all, and the temporary space needed is one block's worth of hex
  whatever the file's size; the tail is moved from the end backwards, so
  a byte is never overwritten before it has been copied and no second
  copy of it is kept. An edit that DELETED bytes writes the file afresh,
  because moving the tail left is the same operation but nothing in Vim
  or `xxd` can then shorten the file: head, edited page and tail are
  block-copied (8 MiB blocks, so memory does not follow the file's size)
  into a temporary file, which replaces the original by being copied
  back over it, keeping its inode, owner and permissions - and if that
  copy back fails part way through, the temporary file holds the
  complete new content and its path is reported rather than deleted.
  Either change of length says by how much the file will change and how
  many bytes that writes, and asks first; `g:hexpair_page_confirm = 0`
  answers yes automatically, for scripts. Before any of them the dump is
  validated exactly as in the whole-file mode, and the file's size and
  modification time are compared with what they were when the page was
  read - a file that changed on disk meanwhile is refused rather than
  patched at offsets that may no longer mean anything. Afterwards the
  page is re-read from disk and the cursor returns to the byte it was
  on, even when a splice moved every byte behind it; a shrinking write
  that empties the file leaves a view saying so instead of a stale dump.
- The `vimhex` shell wrapper now ships as `hexpair.bashrc` in the plugin
  directory, so it can be sourced from `~/.bashrc` rather than copied
  out of the documentation:
  `source ~/.vim/pack/plugins/start/hexpair/hexpair.bashrc`. It handles
  `-` for standard input, a page number or an `@BYTE` position, and
  `$VIMHEX_VIM` picks a particular Vim.
- `:HexPairPages` also reports the byte under the cursor, in hex with
  the decimal in brackets and 1-based — exactly the form
  `:HexPairGoOffset` and the `vimhex` wrapper's `@BYTE` take, so a
  position can be written down and gone back to.
- A **Visual selection** is mirrored in the other column, the way the
  byte under the cursor already was: select hex digits and the text they
  are is highlighted, select text and the bytes it is are highlighted.
  Characterwise, linewise and blockwise selections all work, and one
  spanning several lines is mirrored line by line. Only the part on
  screen is mirrored, which keeps the work per cursor movement the same
  however much of a page is selected.
- `:HexPairGoOffset[!] {byte}` jumps straight to a byte, decimal or
  `0x`-prefixed, turning the page it falls on and leaving you in
  whichever view you were in. The position is 1-based — byte 1 is the
  file's first byte, the numbering the page banner and `:HexPairPages`
  already use, so a number read off the banner can be typed back in. Pages are fixed-size slices, so the page
  holding an offset is a division. `<Plug>(HexPairGoOffset)` prompts for
  the offset the way `<Plug>(HexPairPageGoto)` prompts for a page;
  `<Plug>(HexPairGoOffsetForce)` is the `!` variant.
- `:w {file}` on a paged view writes the **entire** content being paged,
  with the current page's edits in it, to `{file}`, leaving the original
  alone — a save-as rather than a refusal. For a view paged from piped
  input (`cat x | vim -`) that is the only way to save at all, and the
  view adopts `{file}` afterwards, so a later plain `:w` patches pages
  into it. hexpair also warns when it pages a buffer that was not read
  in binary mode, since piped input cannot be re-read with `++bin` the
  way a named file can.
- `<Plug>(HexPairPages)`, so every command that takes no argument now
  has a `<Plug>` target and can be bound to a key — the README and
  `:help hexpair-mappings` list the whole set on a `<Leader>` prefix.

### Changed
- **One hex mode, always paged.** `:HexPairToggle` no longer converts a
  whole buffer: it shows one page, always with the banner — a small
  file simply has exactly one — and toggles from there to a **windowed
  text view** of the same page's raw bytes and back. There is
  deliberately no way back to the plain buffer, since a buffer holding
  one page is not the file and a plain `:w` would truncate the file
  down to it; every hex-mode buffer is `buftype=acwrite` with the
  page-range write path for the same reason. Where a toggled buffer's
  pages come from depends on what it was: an unmodified file-backed
  buffer is paged from its file, an unnamed one (`cat x | vim -`) from
  a private temp it is spilled into, and a modified file-backed one is
  refused — the buffer and the file disagree, and both ways of
  resolving that lose edits quietly.
- A file with no bytes is viewable - it simply has no pages and the view
  says so - and `:e` re-reads the current page.
- Pages are plain fixed-size slices: the paged view reads the width of
  each line's offset column off the line itself, so a page may
  span the point at 4 GiB where `xxd` widens that column from eight hex
  digits to nine, instead of page boundaries being clamped to keep each
  page uniform. Page `N` always starts at `(N-1) * g:hexpair_page_size`,
  page numbering no longer shifts when a file grows past 4 GiB, and a
  bare hex line with no offset column at all is laid out correctly too.
- Only a write that **shortens** a file - and `:w {file}`, and a growing
  write whose tail is more than half the file, both of which go through
  the same splice - requires Vim patch 8.2.4906 with `+num64`, for
  `readblob()`, checked when such a write is attempted and refusing just
  that write. Viewing pages, navigating them, same-length writes and
  inserts work on the Vim 8.0 baseline the rest of the plugin requires.
- Writing a page walks it once instead of three times (validation,
  cursor mapping and stripping share one scan): a write on a 128 KiB
  page went from 0.5 s to 0.32 s, and the saving scales with the page
  size.

### Fixed
- An empty file grew to one byte when it went through the hex view.
  Vim serializes an *empty* buffer for a filter as a single newline, so
  the dump showed a `0a` the file did not contain and writing it back
  created one. Deleting the whole dump and writing now also produces an
  empty file rather than a one-byte one. A file that really holds a
  lone `0a` looks identical in the buffer and still dumps that byte.
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


[v2.2.0-devel]: https://github.com/michal-ruzicka/hexpair/compare/v2.1.0...devel
[v2.1.0]: https://github.com/michal-ruzicka/hexpair/compare/v2.0.0...v2.1.0
[v2.0.0]: https://github.com/michal-ruzicka/hexpair/compare/v1.1.0...v2.0.0
[v1.1.0]: https://github.com/michal-ruzicka/hexpair/compare/v1.0.0...v1.1.0
[v1.0.0]: https://github.com/michal-ruzicka/hexpair/releases/tag/v1.0.0
