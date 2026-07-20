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
plugin/hexpair.vim    - the base plugin (whole-buffer toggle); header
                        carries Version: and Date: (single source of
                        truth, parsed by pack-release.py)
plugin/hexpair_paged.vim - paged large-file mode; separate script scope
                        from plugin/hexpair.vim on purpose (see below)
ftplugin/xxd.vim      - dump-editing defaults (guarded by b:did_ftplugin,
                        reverted via b:undo_ftplugin)
doc/hexpair.txt       - Vim help (:help hexpair)
test/run-tests.sh     - headless regression suite (vim -es)
dist/                 - packaged release tarballs (gitignored)
```

## Architecture (plugin/hexpair.vim)

One script, script-local functions, three public surfaces: the
commands (`:HexPairToggle`, `:HexPairGoHex`, `:HexPairGoAscii`,
`:HexPairSwap`, `:HexPairRefresh`), the `<Plug>` mappings (no default
key mappings — the user maps them in vimrc), and the highlight groups
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
- `s:Refresh()` (`:HexPairRefresh`) — validated round trip through
  binary and back, without writing: same shape as `s:PreWrite()` +
  `s:PostWrite()` but synchronous (no intervening file write, so no
  autocommand split needed) and it must NOT let the buffer end up
  looking clean when it isn't. `&l:modified` is captured *before* the
  two filters (which set it as a side effect regardless of prior
  state) and restored after; `b:hexpair_saved.modified` is set to that
  same captured value (carrying the true "differs from disk" state
  forward across a refresh, unlike `s:PostWrite()` which sets it to 0
  because a real save just happened) and `b:hexpair_dump_tick` is reset
  — both are the inputs `s:FromHex()`'s toggle-off modified check
  reads, so a future toggle-off must still see them correctly whether
  or not the buffer was refreshed in between.
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
discarding an edit made purely in hex mode, `:HexPairOpen` renaming a
scratch buffer to a real-looking path before validating the requested
page, the page banner's 0-based-inclusive byte range reading as
truncated on the last page), first reproduce it as a failing test,
then fix.

**Gotcha for any new `plugin/*.vim` file**: `vim -es -u NONE` (this
suite's harness, with no vimrc) starts in `'compatible'` mode, whose
`'cpoptions'` includes `C` — this disables backslash line
continuations entirely, silently truncating any multi-line statement.
Each plugin file must reset `'cpoptions'` (`set cpo&vim`, saved and
restored around the file, as `plugin/hexpair.vim` already does) before
its own first continuation-using statement; a `:source`d file that
does this restores its *own* prior value on exit, so continuations in
code that runs *after* such a `:source` (e.g. a test script sourcing
the plugin) are affected again unless that code avoids them too —
tests generated by this suite keep every statement on one physical
line for exactly this reason (also why `ftplugin/xxd.vim`'s
`b:undo_ftplugin` is one line). This bit `plugin/hexpair_paged.vim`
during development (its own gate-check function had a truncated error
message) before its `set cpo&vim` was moved to run before that
function's definition instead of after.

## Versioning and releases

Versions follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
(`MAJOR.MINOR.PATCH`). `Version:` and `Date:` in the
`plugin/hexpair.vim` header are the single source of truth;
`pack-release.py` (run via the `pack-release` / `pack-release.cmd`
wrappers) parses them and normalizes all archive timestamps to `Date:`
for reproducible tarballs (see CONTRIBUTING.md). Bump both together. Commits are
SSH-signed, release tarballs GPG-signed locally — CI never publishes.

---

## Paged large-file mode

### Goal: ONE hex mode, always paged

Redesigned after Stage 1 shipped (agreed with the maintainer): there
is to be no separate "base" (whole-buffer) and "paged" (large-file)
hex mode. `:HexPairToggle` (`<Plug>(HexPairToggle)`) is the only
toggle, always shows a page, and always carries the page banner — a
small file just happens to have exactly one page, which behaves
exactly like today's pre-paging plugin plus a `"page 1/1"` banner (the
maintainer explicitly wants this uniformity, not a special case that
hides the banner for a single page). `:HexPairOpen`/`HexPairOpenFile`
remain the *fast entry point* that skips loading the whole file first
— for a file already open normally, `:HexPairToggle` gets you to the
same place, just after Vim already spent the memory to load it.

Consequence: `plugin/hexpair_paged.vim` is absorbed back into
`plugin/hexpair.vim` (single file, single script scope) as part of
Stage 2 below — once hex mode is unconditionally page-aware, keeping
two files would mean duplicating almost everything (`Layout`, strip,
validate, highlight, cursor mapping), not just the one small
`s:ResolveXxd()` helper Stage 1's split cost. `plugin/hexpair_paged.vim`
is deleted; `pack-release.py`'s `FILES` and `CONTRIBUTING.md`'s repo
layout table lose that entry. **This is a decision for Stage 2's own
plan, not yet executed — noted here so Stage 2 doesn't rediscover it.**

### Stages (renumbered; Stage 1 unchanged, Stages 2-3 replaced, Stage 4 new)

Each stage keeps its own review checkpoint with the maintainer before
the next starts — unchanged rationale: a write-path bug could corrupt
a large real file.

- **Stage 1 — read-only paging and navigation: IMPLEMENTED**, as a
  separate `plugin/hexpair_paged.vim` / `:HexPairOpen` entry point.
  Superseded by, not deleted before, Stage 2: its page-read/boundary/
  banner/highlight machinery is the foundation Stage 2 folds into the
  unified mode, largely unchanged in substance, moved and rewired.
- **Stage 2 — unify into a single always-paged mode: PLANNED**, design
  below. No *new* writing capability — `:w` still throws "not
  implemented yet" the same way Stage 1's paged buffers already do,
  now from every hex-mode buffer regardless of entry point, plus the
  new windowed text-mode (below). Deliberately kept separate from
  introducing real disk writes, so this large structural refactor
  (merging two files, three buffer states, two population paths) can
  be reviewed on its own.
- **Stage 3 — same-length in-place patch write: PLANNED** (was "Stage
  2" before this redesign; mechanism unchanged, see "Writing a page"
  below — now applies uniformly to a write from hex-page-view *or*
  windowed-text-view, since both reduce to "these N bytes replace the
  file's `[base, base+len)` range").
- **Stage 4 — length-changing splice write: PLANNED** (was "Stage 3").

### The three buffer states and how a buffer moves between them

1. **Plain** — an ordinary Vim buffer, hex mode never engaged.
   Completely untouched by hexpair; `:w` is 100% vanilla Vim. This is
   the *only* way to see/edit the true whole-file content once a file
   is large enough to need more than one page — there is deliberately
   **no escape hatch back to Plain** once a buffer has left it (see
   below); the maintainer's own call: close and reopen Vim instead.
2. **Hex-page-view** — today's Stage 1 paged view (banner + `xxd -g 1`
   dump of the current page), reached by `:HexPairToggle` from Plain,
   or directly via `:HexPairOpen`/`HexPairOpenFile`.
3. **Windowed-text-view** — *new in Stage 2*: `:HexPairToggle` from
   Hex-page-view goes here instead of back to Plain. Shows the current
   page's raw bytes as text (opened effectively `++bin`, i.e.
   byte-oriented, no fileencoding decoding), bracketed by the *same*
   banner as Hex-page-view (page X/Y, byte range) so the buffer never
   silently pretends to be the whole file. `:HexPairToggle` from here
   goes back to Hex-page-view of the *same* page (byte-offset-exact,
   same mechanism the base plugin already uses for its toggle). A
   plain `:w` here (without going back through hex mode) must **still**
   go through the page-range write path — the buffer's content is only
   one page's worth of bytes, so a literal Vim `:w` would truncate the
   real file down to just that page. This is why Windowed-text-view is
   not "back to Plain": it needs the *same* `BufWritePre`/`BufWriteCmd`
   interception hex-page-view has, just rendering bytes as text instead
   of hex pairs.
   Confirmed with the maintainer: this applies even when there is only
   one page (`N=1`) — banner and page-range write path always active
   once hex mode has been engaged at all, no special-case skip for the
   single-page case. For `N=1` this is functionally identical to a
   normal full-file write (the one page *is* the whole file), so there
   is no behavioural difference from today's plugin beyond the banner.
   Known accepted limitation: a page boundary can fall in the middle of
   a multi-byte UTF-8 sequence, showing two "broken" halves on adjacent
   pages — acceptable because this view is byte-oriented (`++bin`) by
   design, matching the existing "utf-16 remains approximate" class of
   disclaimed limitation elsewhere in this file.

### Entering hex mode: two population paths, chosen by entry point, not by size

`:HexPairToggle` and `:HexPairOpen`/`HexPairOpenFile` both land in
Hex-page-view, but must source the page's bytes differently:

- **Via `:HexPairOpen`/`HexPairOpenFile` (file not loaded at all)** —
  exactly Stage 1's existing path: `xxd -s <base> -l <len> <file>`
  reads only the requested page directly off disk. This is the *only*
  path that actually saves memory for a huge file — the whole point of
  a fast entry that skips loading it first.
- **Via `:HexPairToggle` on an already-existing buffer** — the buffer
  content (whether from a normal `vim file.dat`, from a pipe/`vim -`,
  or already modified with unsaved edits) is **already fully in
  memory**; re-reading the page from disk via `xxd -s` would (a) not
  save any memory at this point — Vim already paid that cost — and (b)
  show *stale* content if the buffer has unsaved edits, silently
  discarding them. So this path must **slice the in-memory buffer**
  for the target page's byte range instead (byte-offset arithmetic via
  `line2byte()`, the same primitive `s:BufOffset()` already uses),
  convert just that slice through `xxd -p` / `xxd -o <base> -g 1 -c N`
  for display. This mirrors the base plugin's existing fork in
  `s:ToHex()` (unmodified + file-backed → `:edit ++bin` reload; else →
  warn and dump in-memory content) — same fork, now also deciding
  *how a page is populated*, not just whether a `++bin` reload happens
  first.
  **Starting page**: the page containing the cursor's current byte
  offset (`s:BufOffset()` divided by the page size), not always page
  1 — consistent with the existing invariant that every mode
  transition in this plugin preserves the cursor's byte position.

This resolves two questions raised while planning this stage:

- **`cat data | vim -` (or any unnamed/pipe-sourced buffer)**: no
  special-casing needed. Vim has no choice but to read all of stdin
  into the buffer before there is anything to display, so by the time
  `:HexPairToggle` could even be pressed, the content is already fully
  in memory — this is exactly the "buffer-slicing" path above, applied
  to a buffer that additionally has no backing file. `:w` on such a
  buffer already fails with Vim's own `E32: No file name` today,
  unrelated to hex mode; paging changes nothing about that. **Paging's
  memory benefit only exists via the `:HexPairOpen` entry point** —
  for an already-loaded buffer (piped or not), paging is a display/
  write-scoping convenience, not a memory optimization, and there is
  no new size limit to invent here.
- **A file opened normally and already fully loaded**: same reasoning
  — the memory is already spent, so page-slicing here is purely about
  giving the same banner/write-scoping/mental-model as a fresh
  `:HexPairOpen`, not about avoiding a big read. If the buffer *is*
  file-backed, the write path can still usefully patch only the
  visible page's range on disk (Stage 3/4), which has a real
  advantage independent of memory: it cannot clobber other regions of
  the file that were never even looked at in this session.

### Vim version gate — narrowed

Re-examined during this redesign: `readblob()` (patch 8.2.4906) is
only actually needed by the Stage 4 **splice** write (growing/
shrinking a page). Reading pages (either population path), Stage 3's
same-length write, and Windowed-text-view all work on the same Vim 8.0
baseline the rest of the plugin already requires. So the blanket
load-time version gate Stage 1 introduced (refusing to load the whole
paged feature below patch 8.2.4906) becomes unnecessarily strict once
paging is the *only* hex mode — it would raise the plugin's minimum
Vim version for basic hex viewing, which used to work on Vim 8.0.
**Stage 4 changes the gate to a runtime check performed only at the
moment a length-changing write is attempted** (clear error, refuse
just that write, everything else keeps working), instead of a
load-time refusal of the entire feature. `HexPairPagedGateMessage()`'s
existing shape (global, pure, parameterized by an explicit boolean for
testability) carries over unchanged to wherever this check ends up
living.

### Reading a page: the `:HexPairOpen` population path

Stage 1's existing mechanism, unchanged by this redesign — one of the
two population paths from "two population paths" above; the other
(buffer-slicing, for `:HexPairToggle` on an already-existing buffer)
is new territory for Stage 2 and not yet designed in this level of
detail.

- `xxd -s <offset> -l <len> -g 1 -c <n> <file>` into a **scratch
  buffer** (`buftype=acwrite`, `bufhidden=hide`, `noswapfile`,
  `filetype=xxd` — reuses the bundled `ftplugin/xxd.vim` editing
  defaults and the base syntax highlighting for free). `-s` makes xxd
  print absolute offsets, so the offset column shows true file
  positions natively (verified: plain `-s`, without `-o`, already does
  this — `-o` is not needed on the read side). **`enew` creates a
  fresh, unrelated buffer** — appropriate here since no buffer existed
  yet. `:HexPairToggle` on an *existing* buffer must instead transform
  that same buffer in place (matching how the base plugin's
  `s:ToHex()` already behaves) — likely NOT `buftype=acwrite` for that
  path, since it is a real, already-named, non-synthetic buffer;
  Stage 2 needs to work out whether `BufWritePre`/`BufWritePost` (the
  base plugin's existing mechanism) or `BufWriteCmd` fits it better,
  and how the two population paths converge on identical buffer state
  (same buffer-local variables below, same commands available)
  afterward, so the rest of the plugin cannot tell which path a given
  Hex-page-view buffer took to get there.
- Buffer-local state: `b:hexpair_page_file`, `b:hexpair_page_index`
  (0-based internally, 1-based in the UI), `b:hexpair_page_size`,
  `b:hexpair_page_base`, `b:hexpair_page_len` (shorter on the last
  page), `b:hexpair_page_total`, `b:hexpair_page_totalpages`,
  `b:hexpair_page_ftime` (`getftime()` at read time — staleness
  detection, not used until Stage 3/4's write path compares it),
  `b:hexpair_n`, `b:hexpair_page_hexstart` (see next point).
- **The offset column is not a fixed width.** Verified empirically:
  `xxd`'s offset column widens past 8 hex digits once an offset
  reaches 4 GiB (`fffffffc:` immediately followed by `100000000:` in
  the *same* dump), which the base plugin's `s:Layout()` (hardcoded
  `hexstart=11`) never has to consider since Vim buffers never
  realistically approach 4 GiB. `s:PagedLayout()` instead *discovers*
  `hexstart` per page (`s:HexDigitWidth(base) + 2`, cached as
  `b:hexpair_page_hexstart`) and `HexPairPagedBounds()`/
  `HexPairPagedWidthBoundaries()` (below) guarantee it is constant
  across any one page by construction.
- Pair highlighting, from the base plugin's `s:Highlight()` (see
  above), additionally skips banner lines entirely (see "Page banner").

### Page boundary arithmetic

`HexPairPagedBounds(idx, size, total)` / `HexPairPagedTotalPages(size,
total)` / `HexPairPagedWidthBoundaries(total)` are global, pure
functions (no I/O, no buffer/window state) treating the file's byte
range as a sequence of **width-uniform segments**, split at every
`16^8`, `16^9`, ... boundary that falls inside it. Within a segment,
pages are plain fixed-size slices of `g:hexpair_page_size`; only the
segment containing a boundary ever produces a page shorter than that.
Being pure and parameterized by a `total` the caller supplies (not
read from a real file), these are directly testable against a
fabricated multi-GiB `total` without needing an actual multi-GiB test
fixture.

### Page banner

Leading/trailing single lines the plugin generates and inserts around
the `xxd` output, e.g. `" hexpair: page 3/21  bytes
2097153-3145728 of 45678901  bigfile.bin"` / `" hexpair: end of page
3/21"`. The byte range in this text (and in `:HexPairPages`, via the
same formula — `s:BannerTop()`/`s:Pages()`, keep in sync) is
deliberately **1-based and inclusive** (`base + 1` to `base + len`),
unlike `b:hexpair_page_base`/`len` themselves or the hex dump's own
offset column (`xxd`'s native 0-based hex address, untouched): with
0-based-inclusive display the *last* page's shown end is one short of
the file's total size, which read as a bug (field bug — reported by
the maintainer testing against a real file: page 3/3 of a 153532-byte
file showed "bytes 131072-153531 of 153532", not obviously covering
the end of the file). 1-based-inclusive is the only one of the
straightforward choices where the last page's end always equals the
total exactly. Recognized structurally by `s:IsBannerLine()`: any line
whose
**first** character is `"` is a full-line comment contributing zero
bytes — never ambiguous with real `xxd` output (data lines always
start with a hex digit) or a bare inserted hex line (never starts with
`"` either). `s:PagedStripDumpLine()`/`s:PagedValidateDump()` (banner-
aware counterparts of the base plugin's `s:StripDumpLine()`/
`s:ValidateDump()` — keep the three in sync, extending invariant 1)
skip banner lines *before* their normal payload logic runs, so banner
text (which contains plain decimal digits and letters, e.g. "page",
"bytes") can never leak into hex-payload parsing. Exposed as global
`HexPairPagedStripLine()`/`HexPairPagedValidate()` purely for
testability, since Stage 1 has no write path yet to exercise them
through — see the `plugin/*.vim` testing note above: shipping this
logic untested until Stage 3 would violate "every change ships with a
test".

`HexPairPageBanner` (`highlight default link ... Comment`) plus a
`syntax match '^".*$'` applied to paged buffers gives the banner a
comment-like appearance; `$VIMRUNTIME/syntax/xxd.vim` defines no
comment group to link to (checked: only `xxdAddress`/`xxdSep`/
`xxdAscii`, all tied to real dump lines), so this is the plugin's own,
following the `HexPairActive`/`HexPairMirror` precedent.

### Commands

Unified by Stage 2 (not yet done — Stage 1's commands below currently
only work on an `:HexPairOpen`-created buffer): once merged,
`:HexPairPageNext`/`Prev`/`Goto`/`Pages` work on *any* Hex-page-view
buffer, however it was reached — `:HexPairToggle` or `:HexPairOpen`
produce indistinguishable buffer state (see "two population paths"
above).

- `:HexPairOpen <file> [page]` — entry point; does **not** first
  `:edit` the file (that would load the whole multi-GB file into a
  normal buffer, defeating the purpose) — creates a scratch buffer via
  `enew` and populates it directly through the page-read path above.
  `[page]` is 1-based, defaults to 1. `-nargs=+` with a variadic
  `s:Open(file, ...)`, not `<f-args>[N]` indexing — `<f-args>` is a
  textual splice of individually-quoted arguments into the call, not a
  Vim List, so it cannot be indexed. `s:ResolvePage()` (shared with
  `s:LoadPage()`) validates the requested page *before* the `enew`/
  `:file` rename below it — this order matters: validating after would
  leave an empty, inactive (`b:hexpair_page_active` never gets set),
  but real-looking `buftype=acwrite` buffer named `<file> [hexpair
  page]` behind on a bad page number, which used to happen (field bug:
  harmless *only* because Stage 1's `:w` unconditionally throws "not
  implemented" regardless of buffer state — a real write path replacing
  that throw would need to special-case this broken state, or worse,
  not notice and write to the made-up path).
- `HexPairOpenFile(file, ...)` — thin global wrapper calling
  `s:Open()` directly, for scripts/wrappers building the filename
  programmatically. Exists because `:HexPairOpen`'s `-nargs=+`/
  `<f-args>` parsing does not fully round-trip `fnameescape()`'s
  escaping: verified empirically that a name containing `$` comes back
  from `<f-args>` with a stray backslash still in front of it
  (`fnameescape()` escapes `$` to stop Vim's own command-line
  file-argument expansion of a literal `$VAR`, but `<f-args>`'s
  unescaping only knows about its own argument-separator characters,
  e.g. a space, and does not undo that one). A direct function call
  has no text round trip to go wrong — confirmed the same name
  (spaces, non-ASCII, a literal `$NAME` substring) survives unchanged
  when passed as a real function argument, e.g. `$ENVVAR` read
  straight into `call HexPairOpenFile($ENVVAR)`.
- `:HexPairPageNext` / `:HexPairPagePrev` / `:HexPairPageGoto <N>
  [!]` — `!` (`-bang`) discards unsaved changes; without it, refuses
  when `'modified'` (Stage 1 can edit the scratch buffer even though
  saving isn't implemented yet, so this guard is meaningful and tested
  now, unchanged for Stage 3/4).
- `HexPairPagedParsePageInput(text)` / `s:PageGotoPrompt()` —
  `<Plug>(HexPairPageGoto)`'s `input()`-driven prompt (a typed `{N}`
  can't come from a bare `<Plug>` mapping). Split into a global, pure
  parsing function and a thin interactive wrapper for the same reason
  as the gate/size-error functions above, but forced by a harder
  constraint this time: confirmed empirically that `input()` itself
  does not behave usably under `vim -es -u NONE` (this project's whole
  test harness) — it hangs waiting on stdin, or (with stdin redirected
  to `/dev/null`) silently aborts the *entire script*, including code
  after a `try`/`catch` around it. `feedkeys()` cannot work around this
  since the process never gets far enough for typeahead to matter.
  `s:PageGotoPrompt(force)` itself is therefore intentionally
  untested; `HexPairPagedParsePageInput()` carries all the actual
  decision logic (empty → cancel, non-digits → error, digits → the
  page number, unvalidated against the page count — `s:LoadPage()`'s
  existing `HexPairPagedBounds()` check already reports a clear error
  for an out-of-range page, no need to duplicate that here) and is
  what the tests exercise directly. `a:force` (0 for
  `<Plug>(HexPairPageGoto)`, 1 for `<Plug>(HexPairPageGotoForce)`)
  flows straight into the same `s:GotoPage()` used by
  `:HexPairPageGoto!` — a direct Ex-command test of the bang variant
  covers this pass-through without needing `input()`.
- `:HexPairPages` — reports `page X of Y, offsets A-B of total S
  bytes (file)`.
- `g:hexpair_page_size` — default `1024 * 1024` (1 MiB — overriding an
  earlier 64 MiB draft of this plan; small enough to set down to e.g.
  `512` for tests). Validated as a positive multiple of
  `g:hexpair_bytes_per_line` by `HexPairPagedSizeError()`, snapshotted
  into `b:hexpair_page_size` at `:HexPairOpen` time (mirrors
  `b:hexpair_n`'s snapshot of `g:hexpair_bytes_per_line` in the base
  plugin) so a later global change cannot desync an open page buffer.

### Stage 1 gaps that Stage 2 should close, not just carry forward

These were out of scope for Stage 1's approved plan, filed as known
gaps rather than regressions — but under the "one mode" redesign they
stop being optional follow-ups, since Hex-page-view is no longer a
separate second-class mode:

- `:HexPairGoHex`/`:HexPairGoAscii`/`:HexPairSwap`, currently keyed on
  `b:hexpair_active` (never set by a paged buffer, which uses
  `b:hexpair_page_active`) — once there is one mode, one active flag,
  these should just work on any Hex-page-view buffer.
- `g:hexpair_paste` management (`s:PasteOn()`/`s:PasteOff()`) —
  likewise should apply uniformly; presumably to Windowed-text-view
  too, on the same reasoning as the ftplugin/banner/write-path
  uniformity decided above (confirm with the maintainer if it's not
  obvious once Stage 2 gets there).

### Writing a page — two mechanisms, chosen by length (Stage 3/4, not yet implemented)

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
patched range are bit-identical before/after. A manual spot check
during Stage 1 planning already confirmed all three, on both
platforms, including with dump lines *reordered* by the user before
the strip → regenerate → patch pipeline (the reorder case is why the
pipeline regenerates a fresh canonical dump instead of patching
directly against the user's possibly-stale embedded offsets) — this
de-risked committing to the architecture, but Stage 3 still needs this
**automated** as tests before the write path is trusted, per the
mandate above. Must be exercised from *both* Hex-page-view and
Windowed-text-view once Stage 2 adds the latter — same underlying
mechanism, but two different sources for "these are the page's new
raw bytes" (strip a hex dump, vs. take the text buffer's bytes as-is).

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

### Testing

Stage 1, in `test/run-tests.sh`: a fixture with recognizable
per-page content (5000 bytes, byte `i` valued `i % 256`) asserting the
banner, absolute offsets, page navigation including the guard on a
modified page and refusal past the last page, `:HexPairPages`'
reported text, the version-gate and page-size-validation functions'
both branches, the digit-width boundary clamping (against a fabricated
multi-GiB `total`, no real large fixture needed since the arithmetic
is pure), and banner-aware stripping/validation (including that banner
text containing letters and slashes is never mistaken for an invalid
hex character).

Needed for Stage 2 (unification, no new writing): `:HexPairToggle` on
a small already-loaded file lands on Hex-page-view with exactly one
page and today's pre-paging byte-for-byte behaviour, plus a `1/1`
banner; on a multi-page file it starts on the page containing the
cursor's byte offset, not always page 1; toggling Hex-page-view →
Windowed-text-view → Hex-page-view round-trips the cursor byte exactly
(same invariant as the existing base-plugin toggle) and shows the
banner in both directions; a `:w` attempt from either view still
throws the same "not implemented yet" it does today; an unnamed/piped
buffer (`vim -` equivalent in the test harness — feed content via
stdin or construct with `enew` + `setline()`) reaches Hex-page-view
via the buffer-slicing path with no crash and no attempt to read a
nonexistent file.

Needed for Stage 3/4 (real writes): same-length patch touches only the
edited range (compare full-file hashes outside the range) — from both
Hex-page-view and Windowed-text-view; splice correctness for grow and
shrink; staleness refusal (`getfsize()`/`getftime()` mismatch); the
`try/finally` temp-file cleanup on both success and a simulated
failure; the splice version gate's *runtime* (not load-time) failure
message, still tested via the same parameterized-function pattern.

### Explicit non-goals (for now)

- No attempt at insert/delete without a full-file rewrite (filesystems
  cannot splice in place).
- No memory-mapped or streaming views; one page = one buffer.
- utf-16 position mapping stays approximate for the whole-buffer byte
  offset math the base plugin already does; a page boundary splitting
  a multi-byte UTF-8 sequence in Windowed-text-view is the paged
  equivalent, and is likewise not fixed — both are accepted, disclosed
  limitations of being fundamentally byte-oriented.
- No way back to the Plain (pre-hex-mode, whole-file, unpaged) buffer
  state once a buffer has engaged hex mode at all — close and reopen
  Vim for that (the maintainer's explicit call, to avoid maintaining a
  second, rarely-exercised code path just for reverting).
