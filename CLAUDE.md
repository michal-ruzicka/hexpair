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

**The name is `hexpair`, and stays.** It was weighed against `vimhex`
and kept: `vimhex` is one letter from `ImHex` in speech and in a search
box, it is already the name of the shell function in `hexpair.bashrc`
(so `:help vimhex` and `$ vimhex` would be two subjects with one name),
and it names the category every alternative belongs to rather than the
one thing this plugin does that they do not — pairing hex and text, in
both columns of a dump line and between the two views of a page. The
namespace is free either way; that was checked, and is not the point.
Renaming would touch ~1200 occurrences and 30 public names.

## Repo layout

```
README.md             - end-user docs (bundled in the release tarball)
CONTRIBUTING.md       - developer docs (bundled in the release tarball)
CHANGELOG.md          - Keep-a-Changelog formatted release notes
LICENSE.md            - Vim License + copyright notice
CLAUDE.md             - this file
hexpair.bashrc        - the `vimhex` shell wrapper, sourced from the
                        user's ~/.bashrc; opens a file (or piped input)
                        straight in the hex view, and is bundled in the
                        release tarball
hexpair.vimrc         - the mappings the maintainer uses, in a form a
                        vimrc can source rather than copy:
                        `runtime pack/*/start/hexpair/hexpair.vimrc`,
                        which resolves on Linux and Windows alike because
                        'runtimepath' already names each platform's own
                        per-user directory (~/.vim, ~/vimfiles). Package
                        directories are NOT on 'runtimepath' yet while a
                        vimrc runs, which is why the wildcard path is the
                        recommended form and a bare `runtime hexpair.vimrc`
                        only works for plugin-manager installs. Guarded by
                        g:loaded_hexpair_vimrc, restores 'cpoptions', and
                        never takes a key the user has already mapped.
                        Bundled in the release tarball.
vimhex.cmd            the cmd.exe counterparts of the two shell
vimhexdiff.cmd        functions in hexpair.bashrc, same names and same
                      arguments. CRLF line endings, pinned by
                      .gitattributes - a batch file with LF endings
                      breaks `goto` under cmd.exe. Both pass paths
                      through the ENVIRONMENT into $NAME inside a Vim
                      expression, for hexpair.bashrc's reason, and that
                      is also what makes them safe to call from an
                      Explorer verb. vimhexdiff.cmd additionally has
                      /left and /right: a context-menu verb is run once
                      per selected file and there is no %2, so two files
                      take two clicks unless one writes a COM handler.
                      Bundled in the release tarball, and the packaging
                      test's rule was widened to vimhex*.cmd to keep
                      them there (pack-release.cmd is a build tool, not
                      part of a release). NOT exercised by CI: the
                      Windows job runs the Vim suite under Git Bash, so
                      the batch itself is only ever run by hand.
                      Both `:run`/`:stdin` labels check `errorlevel 1`
                      right after invoking `"%VIMHEX_VIM%"` and, only on
                      failure, echo why plus `pause` before `exit /b 1`
                      (`:launchfailed`). Reported by the maintainer:
                      the entries the .reg files add flashed a console
                      and closed too fast to read - `cmd.exe /c` (what
                      Explorer's "command" value runs through) closes
                      its console the instant the batch ends, and on
                      SUCCESS gvim/vim return control (0) almost at
                      once (gVim forks and returns; console Vim returns
                      when the user quits it), so the pause never fires
                      on a normal launch and the fast-flash UX the
                      README documents is unchanged. Root cause NOT
                      confirmed - the maintainer separately reported
                      that `*vimhex*.cmd` run directly from a cmd
                      prompt work first try, which rules out a bad
                      $VIMHEX_VIM/$PATH in that shell and points at
                      something specific to the Explorer-constructed
                      "cmd.exe /c ""path" "%1""" invocation instead
                      (its quoting was re-derived by hand against
                      `cmd /?`'s own documented two rules and comes out
                      correct, so that is not the leading suspect
                      either) - but this pause is what will surface the
                      actual message next time, which is the fix that
                      does not depend on guessing right first.
gvimhex.cmd           the same two commands, defaulting VIMHEX_VIM to
gvimhexdiff.cmd       "gvim" instead of "vim" - what a context-menu verb
                      or a double-click needs, since neither has a
                      console to run the console Vim in or a way to pass
                      VIMHEX_VIM. Each `call`s its vimhex.cmd/
                      vimhexdiff.cmd counterpart via `%~dp0` (this
                      directory) rather than reimplementing the argument
                      parsing and, for the diff pair, the /left-/right
                      state file - one source of truth for that grammar.
                      Consequence: unlike vimhex.cmd/vimhexdiff.cmd
                      themselves, these two are NOT independently
                      relocatable - they must stay next to the
                      vimhex*.cmd they call. Same CRLF and packaging
                      treatment as vimhex.cmd/vimhexdiff.cmd; the
                      packaging test's glob is `*vimhex*.cmd` (leading
                      `*`) so it catches these without a separate rule.
vimhex-contex-entry.  add.reg wires gvimhex.cmd/gvimhexdiff.cmd into the
  add.reg / .remove.reg  Explorer context menu under HKEY_CURRENT_USER, as
                      ONE `vimhex` submenu holding three items (open, a
                      separator, then the diff /left+/right pair);
                      .remove.reg deletes the folder and its child key by
                      name, and needs no path of its own, so it undoes an
                      add.reg generated for ANY path. Each item carries an
                      "Icon" pointing into icons/.
                      It deliberately does NOT clean up after the shapes
                      this menu had earlier in development (three keys
                      straight in the "*" menu). Nothing was ever released
                      with those, so there is no installed base to tidy;
                      carrying deletions for a layout no user ever had is
                      dead weight. Same reasoning applies to the next
                      restructure while v2.3.0 is unreleased.
                      Submenu mechanics, all three of which are load-
                      bearing: the folder is a verb with
                      "ExtendedSubCommandsKey" and NO \command subkey (a
                      \command would make it clickable instead of a
                      folder); the key it names is relative to HKCR, and
                      HKCU\Software\Classes merges into HKCR, which is
                      what keeps this out of HKLM - the older
                      "SubCommands" scheme resolves against HKLM's
                      CommandStore and needs admin; children sort
                      ALPHABETICALLY BY KEY NAME, not by write order,
                      hence the 10-/20-/30- prefixes, and the separator is
                      "CommandFlags"=dword:20 (ECF_SEPARATORBEFORE) on the
                      item BELOW the rule.
                      The two diff items are SYMMETRIC (/left and /right,
                      either order) - see vimhexdiff.cmd's :side.
                      BOTH ARE GENERATED - see make-context-entry-reg.py;
                      do not hand-edit them. Bundled in the release
                      tarball; same packaging-glob mechanism as the .cmd
                      files, `*vimhex*.reg`.
                      NOTE for Windows 11: this is a "legacy" context
                      menu, so it sits under "Show more options". Total
                      Commander (what the maintainer actually uses) shows
                      the classic menu directly, so it is not a problem
                      there.
The console flash        DECIDED, do not re-litigate without new
  from a context-menu    information. A "cmd.exe /c" verb creates a
  verb                   console window; the reported problem was not the
                      flash itself but the FOCUS - with a Windows Terminal
                      window already open, the new console attaches to it
                      and takes focus, dropping the file manager the menu
                      was used from (Total Commander) into the background.
                      A wscript.exe + vimhex-launch.vbs launcher WAS built
                      and did fix it (GUI-subsystem host, .cmd run with
                      window style 0, failures reported in a MsgBox), then
                      was WITHDRAWN at the maintainer's call. Why, so the
                      next person does not rebuild it: "run this command
                      with a hidden window" through the Windows Script
                      Host is one of the shapes antivirus heuristics look
                      for, and VBScript is being removed from Windows
                      (Feature on Demand since 11 24H2). The only other
                      way to lose the console is a GUI-subsystem stub
                      .exe, and an UNSIGNED binary is usually worse for
                      antivirus than the script, besides being the first
                      compiled artefact this project would ship.
                      So the flash is accepted. What survived from that
                      attempt and is still worth keeping: the exit-status
                      check in each .cmd, and HEXPAIR_NO_PAUSE (:holdopen
                      in vimhexdiff.cmd) so a caller that shows the
                      message its own way can skip the pause.
                      If it is ever revisited, the untried idea with the
                      best shape is to have the registry call gvim.exe
                      DIRECTLY (a GUI program, so no console exists to
                      begin with) and move the side-selection state into
                      the plugin - the obstacle being that recording a
                      side must not open a window, which is exactly what
                      launching gVim does.
make-context-entry-   generates the two .reg files above. Exists because
  reg.py              the maintainer's requirement is that a DEFAULT
                      install import and work with nothing edited, and
                      that forces REG_EXPAND_SZ: a plain REG_SZ does NOT
                      expand %USERPROFILE% (the shell would look for a
                      folder literally named that), and REG_EXPAND_SZ is
                      only expressible in .reg text as `hex(2):` plus the
                      string's UTF-16LE bytes - unmaintainable by hand,
                      fine to generate. Takes an optional install path
                      (default %USERPROFILE%\vimfiles\pack\plugins\start\
                      hexpair, which is what README.md installs to), so
                      "installed elsewhere" is a re-run, not an edit.
                      **The expansion ORDER is the subtle part and is
                      why %1 survives**: the shell expands the variable
                      when it READS the value, then substitutes %1 when
                      it builds the command line. Once %USERPROFILE% is
                      consumed as a pair, the only % left in the string
                      is %1's own - a lone %, so it cannot be mis-paired
                      into a bogus variable name. Re-check it whenever a
                      command grows another variable: the rule that has to
                      hold is that each one is a COMPLETE %VAR% pair, so
                      the count of leftover lone % stays exactly one.
                      test/run-tests.sh does this for real - it decodes
                      every hex(2) value back to UTF-16, asserts the
                      round trip, and asserts that count.
                      Writes CRLF itself (the files are
                      generated, so .gitattributes' *.reg rule is a
                      backstop, not the mechanism), and is deterministic
                      - verified by hashing two consecutive runs.
                      Development-only, like icons/*.py: it matches no
                      pattern in the packaging test's shipped-files glob,
                      so it is correctly never expected in FILES.
icons/                three custom icons for the entries above, and
                      what generates them:
                      - rasticon.py: a from-scratch vector rasterizer
                        plus PNG/ICO encoder, stdlib only (no Pillow/
                        ImageMagick on the box this was built on, and
                        the plugin's own no-incidental-tooling rule
                        fit anyway). Draw calls run in 0..1 unit-square
                        coordinates against a Canvas rendered at 4x
                        supersample and box-downsampled, so one shape
                        spec produces every target size cleanly. PNG
                        write path is the minimum valid subset (IHDR/
                        IDAT/IEND, filter type 0, zlib); ICO write path
                        packs PNG-format entries per the Vista+ scheme
                        (a 0 width/height byte in an ICONDIRENTRY means
                        256, since the field is one byte).
                      - design.py: the three icon specs. A V mark
                        (ORIGINAL - not extracted from a real gvim.exe,
                        there being no Windows box handy to pull one off
                        of - in Vim's own green) plus a "0x" badge
                        (bottom-right, smaller, the blocky 5x7 font) on
                        all three, and on the diff pair a bigger
                        bottom-left badge of two window panes (echoing
                        vimhexdiff's own actual `vsplit`) - blue left /
                        orange right, the side THIS icon represents at
                        full colour and the other dimmed toward the
                        badge's dark frame.
                        SUPERSEDED first design, kept here for why:
                        top-right diff mark plus top-left L/R letter (or
                        a left/right arrow) - all discarded once actually
                        compared at 16px, where neither text nor an arrow
                        stayed legible; colour-coding one badge does.
                      - build.py: renders icons/*.ico (sizes 16/24/32/
                        48/256) from design.py. Deterministic (no
                        timestamps, no randomness) - confirmed by hash,
                        re-running it after an unrelated change must not
                        touch the .ico files.
                      Only the three .ico files are bundled in the
                      release tarball (pack-release.py's FILES) - the
                      packaging test's glob gained a bare `*.ico`
                      (asymmetric with the `*vimhex*.{cmd,reg}` rule
                      on purpose: every .ico ships, but rasticon.py/
                      design.py/build.py themselves match no pattern
                      there and so are correctly never expected in
                      FILES - source stays out of the tarball, only
                      what it built goes in).
pack-release          - POSIX wrapper around pack-release.py
pack-release.cmd      - Windows wrapper around pack-release.py
pack-release.py       - the packaging implementation (python3, stdlib
                        only); byte-identical tarball on every platform
                        by construction
plugin/hexpair.vim    - the whole plugin, one script scope; header
                        carries Version: and Date: (single source of
                        truth, parsed by pack-release.py)
ftplugin/xxd.vim      - dump-editing defaults (guarded by b:did_ftplugin,
                        reverted via b:undo_ftplugin)
doc/hexpair.txt       - Vim help (:help hexpair)
demo/                 - the animation at the top of README.md and what
                        records it: hexpair-demo.tape (the vhs script),
                        hexpair-demo.vimrc (the Vim it uses - the plugin
                        out of the working tree, nothing of the person
                        recording), hexpair-demo.sh (records, converts,
                        cleans up) and hexpair-demo.gif. The MP4 the GIF
                        is made from is written beside it and gitignored -
                        only one of the two belongs in a repository. It
                        edits the project's own v2.1.0 release tarball,
                        fetched live - reproducible, so the bytes on
                        screen are the bytes anybody else gets - renamed
                        to .bin because Vim's tar plugin would otherwise
                        show the listing.
                        NOT in the release tarball, and the packaging
                        test does not ask for it: none of those names
                        matches its .md/.vim/.txt/hexpair.* rule. See
                        CONTRIBUTING.md, "The README demo", for the four
                        things that took a recording each to find: vhs
                        cannot type a non-ASCII <Leader>, a freshly
                        started Vim swallows the first key sequence, vhs's
                        own GIF writer is OOM-killed on a recording this
                        long (hence MP4 then ffmpeg), and its work
                        directory must be short as well as off tmpfs
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
- `s:ZeroBytes()` / `s:KeepEmpty()` — a buffer holding NO bytes must
  never be handed to a filter: Vim serializes it as a single newline,
  which xxd faithfully dumps as a `0a` the file never had. Zero bytes
  has two representations (the state a 0-byte file is read into, where
  `line2byte(1)` is -1, and one empty line with `noeol`); a buffer
  holding a lone `0a` looks like neither, which is what makes the two
  distinguishable at all, since by content both are one empty line.
  Every `%!xxd` in this file is guarded by it, and `s:FromHex()`
  re-applies `s:KeepEmpty()` after restoring the saved `'eol'`.
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
- The data inspector's two directions. `s:Inspect()` reads up to eight
  bytes and `b:hexpair_inspect` is `[absolute offset, count]` of what it
  actually got — which near a page or file end is fewer, and the marking
  (layer `'inspect'`, `HexPairPagedRunPositions()` in the dump,
  `HexPairPagedTextPositions()` in the text view) says exactly that many.
  It expires in `s:PagedHighlight()` when the cursor is no longer on the
  byte it was read from — not on any cursor movement, since a redraw, a
  window hop and a `:syncbind` all run through the highlighting without
  the cursor having gone anywhere.
  `HexPairPagedCharBytes()` is the other direction. **The Unicode
  encodings are computed from the code point, not converted**: `iconv()`
  answers with a String, a String cannot hold a NUL, and `A` in utf-16le
  is `41 00`. Anything else goes to `iconv()` and is checked by
  converting it back — and the *name* is probed separately with a
  U+0160 canary, because iconv() answers a conversion it cannot do by
  handing the text back unchanged, which for ASCII in an ASCII-compatible
  encoding is what success looks like too.
- `g:hexpair_debug` — `s:Debug()`, an echomsg trace of every position
  mapping step (`:messages`); keep it working, it has already caught two
  field bugs. The Stage 2 rewrite dropped every call site while the docs
  went on promising it; it is back at the *transitions* (page load,
  `++bin` reload, offset→position and position→offset in both views,
  what a write found), deliberately not on `CursorMoved`. Both
  directions print in the same terms, so a mismatch between them is
  visible at a glance.

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
7. A dump line is buffer line `k + s:HeaderLines()`, **never** a literal
   2: `g:hexpair_ruler` puts a second line above the dump. Every mapping
   between a line number and a byte offset — `s:PagedLineBase()`,
   `s:PagedGotoOffset()`, `s:PosOffset()`, `HexPairStatus()` — goes
   through it. (`s:LoadPage()`'s shape check is the one that does not,
   and must not: it counts the lines xxd produced, before they are a
   buffer and before a banner or a ruler is anywhere near them.)
   The text view has no ruler, so its own header is always the one
   banner line, matched by exact text (`s:TextBodyRange()`).

## Testing

`test/run-tests.sh` drives headless Vim (`vim -es -u NONE`) over
generated fixtures and asserts byte-exact expectations (file content
via `xxd` reference dumps, cursor positions via `line()`/`col()`/
`line2byte()`). Python3 generates fixtures (binary patterns, mixed
line endings, encodings) — `printf` in dash does not expand `\x`
escapes, which has silently neutered tests before; always generate
binary fixtures with python.

The suite runs on Windows in CI too, under Git Bash against a pinned,
SHA-256-checked Vim from `vim/vim-win32-installer`. **Which Vim that is
must be said, not inferred from `PATH`**: a Git Bash step puts Git's own
MSYS Vim first whatever is prepended, and that one understands POSIX
paths, so it passes every test while proving nothing about native
Windows - `$HEXPAIR_VIM` and `$HEXPAIR_XXD` name the binaries, and the
job refuses a Vim whose `--version` does not say `MS-Windows`. Three more
constraints follow from running there, each of which a change made only
on Linux could break without any local run noticing:

- **Stay POSIX-sh and portable**: no GNU-only tools, `$PY` rather than a
  hardcoded `python3` (Windows names it `python`, and a `python3` that
  only opens the Microsoft Store is a common decoy, so the candidate has
  to run before it is believed).
- **Every path written into a generated `.vim` script** goes through the
  `cygpath -m` conversion at the top: Git Bash rewrites paths in the
  arguments it hands a native program, but not inside a file that Vim
  opens itself. The suite then has Vim re-spell both roots with
  `fnamemodify(':p')` — the same call the plugin stores paths with, so
  the two agree by construction. Without it, MSYS maps `/tmp` to
  `%TEMP%`, which can be the 8.3 form, and every banner assertion fails
  on `C:/Users/RUNNER~1/...` versus `C:/Users/runneradmin/...`, two
  names for one directory.
- **`tempname()`'s directory is not private on Windows.** On Unix it is
  a per-session directory, empty until Vim puts something there; on
  Windows the names land straight in the shared `%TEMP%`. A test about
  temp hygiene must measure what a write *added*, never what the
  directory holds.

The general rule behind two of those, and worth applying to the next
one: **assert against the value the code will actually use, not one the
harness constructed to look like it.**

Every change ships with a test. When a field bug is diagnosed, first
reproduce it as a failing test, then fix. **None of the bugs below may
come back**; each names the test that would catch it.

| Bug | Guard |
|---|---|
| Forced `'noeol'` hid the file's final newline | "final newline in dump" |
| Layout desynced when `g:hexpair_bytes_per_line` changed mid-session | "n=23 dump position" / "n=23 cursor byte" |
| Stale `FileOffsetNonBinary` predictions on mixed CRLF/LF | the non-binary reload position tests |
| A 0-byte file grew to one byte: `%!` serializes an empty buffer as a newline | "an empty file stays empty" + the lone-`0a` counter-case |
| Toggle-off mirrored only the pre-hex-mode `'modified'` state, so `:q` discarded an edit made purely in hex mode | "an edit in the hex view survives into the text view, still modified" |
| `:HexPairOpen` renamed a scratch buffer to a real-looking path before validating the page | "out-of-range page number leaves the buffer untouched" |
| The banner's 0-based-inclusive range read as truncated on the last page | the banner assertions |
| `'compatible'` drops backslash continuations in a plugin file | the gate-message test asserts a continuation-built string in full |
| Undo reached across a page boundary | "undo stops at the page boundary" |
| …and would have survived a buffer-local `'undolevels'` | "a buffer-local 'undolevels' is restored, history still cleared" |
| Paged `hexstart` was one column short: the highlight covered a space, the cursor sat beside the byte | "hexstart is the first hex digit" — read off a real page line, not restated as a constant |
| A duplicate `*:HexPairRefresh*` tag aborted `:helptags`, leaving the plugin with no `:help` at all | "helptags accepts the help file" |
| A page read that silently produced nothing would be patched into the file | "a full page is two banner lines plus its dump lines" |
| `:w {other}` patched the page into the view's own file | "':w other' leaves the buffer and its own file alone" |
| `:saveas` wrote the bytes but left `'modified'` set and the view still editing the OLD file, so every later write copied the whole file instead of patching a page. Vim leaves `'modified'` to the autocommand for `acwrite`; and inside `BufWriteCmd` `:saveas` and `:w {file}` both arrive with `<amatch>` = the target, so the only thing telling them apart is that `:saveas` RENAMES THE BUFFER FIRST (`s:IsSaveAs()`). Beware the near-miss fix: updating the cached buffer name from `BufFilePost` fires BEFORE the write and makes a `:saveas` look like a plain `:w` of the view's own file, which patches the page into the file it was saved away from | "':saveas' clears 'modified' and adopts the file" and the four beside it |
| `<amatch>` is absolute, `bufname()` relative — comparing them as strings refuses every write | same test |
| A splice failing while *building* the temp left it behind | "a successful splice leaves no temp files behind" |
| Opening a page could abandon a modified buffer | "opening a page refuses to abandon a modified buffer" |
| A plain `:w` took the save-as path on Windows, where one file has more than one spelling. Save-as truncates its target before reading the source, so this would have destroyed a multi-page file | "on Windows, separators and case are not" + "writing to the same file spelled longhand patches the page" |
| Growing a page in place needed three times the tail in temporary space — it copied the whole tail aside before moving it | "an insert grows the file, in place, and leaves no temp behind" + the cost table in `README.md` |
| The whole-page scan read a line differently from the per-line rule (a `\zs` anchor that consumed the newline; a negated collection that matched the end-of-line only on a long string) | "the whole-page scan says what the per-line rule says" — on a 6250-line page, since neither shows up on a short one |
| `count()` over a string (patch 8.0.0794) and Blob literals (8.1.0735) broke the documented Vim 8.0 baseline: everything past *displaying* a page failed with E712 | the baseline run below, and no `count()`/`0z` left in the plugin |
| `g:hexpair_debug` was documented but no longer implemented at all | "the trace says both directions of the mapping" |
| A second `:HexPairOpen` of one file died with E95: the buffer name was the file's alone | "a split is a second view, on the page it names" |
| Freshness keyed on the file's mtime, so one view writing locked every other view of that file out of writing | "one view writing does not lock the other out" — and its counter-case, two views of the SAME page |
| `:HexPairReplace` decided "is the cursor on a match?" from the page as READ, so a second replace on the same spot overwrote bytes that were no longer a match | "the cursor has to be on a match to replace it" |
| A hex index is a nibble: `match()` on a run of hex finds patterns starting on the wrong half of a byte | "a match must start on a byte, not between two" |
| The cursor in the gap between the hex and ASCII columns reported the NEXT line's first byte, because the pairs counted before it were the whole line's | "and it is the byte the layout says" — which pins the gap column too |
| `count` is a read-only Vim variable (`v:count`), so a local named that aborts the function it is in with E46 | caught by the selection tests; do not name a local `count`, `errmsg`, `line`… |
| A replacement rebuilt the page through the path that LOADS one, which clears the undo history on purpose — so a command's edit could not be undone the way a typed one can | "and one undo takes the whole replacement back" |
| A window scrolled without being ENTERED (`'scrollbind'`, which `vimhexdiff` sets up) raises no event, so its markings stopped part way down | "refreshing the other windows leaves this one current" |
| A temp-hygiene test asked how many files `tempname()`'s directory HOLDS; on Windows that is the shared `%TEMP%`, with sixteen of other people's in it | "a page of a file this user cannot write is read-only" — count what a write ADDED |
| Counting the bytes that differ walked the page, two `strpart()`s per byte: 4.9 s a page, paid twice by `vimhexdiff` — it looked hung | "counting the differing bytes" / "on a page-sized run, one byte in" |
| A page turn left the scroll-bound window on its old page, so `vimhexdiff` scrolled two windows in step through different parts of two files | "a bound window turns to the same page" and the four refusals beside it |
| The diff jumps stepped byte by byte through one change instead of between changes — `]` fifty times to cross fifty differing bytes | "and the next jump clears the whole of it" + the block around it |
| Every match on the PAGE was found and then tested against every visible line: `:HexPairFind 2?` cost a second per page | "a match over a line end is marked on both lines" (the positions are window-scoped now) |
| A new file users are told to source (`hexpair.vimrc`) was in the repo and the docs but not in `pack-release.py`'s hand-written `FILES`, so it did not ship | "the packaging list is what the repository gives a user" — every `.md`, `.vim`, `.txt` and `hexpair.*` outside `test/` must be in the list |
| A page turn left the bound windows scrolling around a stale offset: `'scrollbind'` syncs RELATIVE movement from the position each window was bound at, and loading a page moves a window without telling Vim that this is the new zero | not testable headlessly (a `vim -es` window has no geometry: `line('w0')` came back above `line('w$')`) — checked in tmux, and `:syncbind` after a bound turn is the fix |
| The progress line of a scan was echoed and then wiped by the `redraw!` on the next line, dozens of times a second: it was never readable, and a 70 GiB search looked like a hang with a flicker | not testable headlessly (`vim -es` has no message line) — the tmux recipe above, and `echo` + plain `redraw` is the fix |
| `CTRL-C` could not stop a scan: every block read caught it (a bare `:catch` catches `Vim:Interrupt` too) and read the next block, so it only worked if pressed between two reads | "a scan says how far it has got" pins the message; the catch is `/^hexpair:/` now, and E608 forbids re-throwing what a catch-all would have swallowed |
| A jump to a byte on another page levelled the scroll-bound windows *before* the cursor arrived, and `:syncbind` swallows the next scroll Vim would have followed — so `vimhexdiff` came apart at every page boundary | "and takes the bound window to that byte, not to the page" |
| The `<Plug>`-coverage test was vacuous: `map <Plug>` under `-u NONE` reads `<Plug>` as six literal characters ('compatible' puts `<` in `'cpoptions'`), and the plugin was never sourced in that script, so there were no targets to miss | "and leaves no `<Plug>` target without a key" — `set cpoptions-=<`, the plugin sourced, and the keys looked for in the mappings *file* rather than in `map` (where every target is its own left-hand side) |
| A jump synced the scroll-bound windows only when it crossed a page boundary, so the same keystroke took the other window along or left it behind depending on how far it happened to go | "a jump inside a page takes the bound view along too" and "which is the same rule as across a page" |
| `vimhexdiff` opened with its two windows on different parts of two files: everything it does runs inside `VimEnter`, and `'scrollbind'` syncs only movement made after the main loop has seen the window bound | "and :HexPairSyncViews is the way back" and the block around it — the startup now ends in `:HexPairSyncViews` |
| Two assertions about the diff summary compared the message against a path the harness had built, while the plugin prints one `fnamemodify(':~:.')` has been over. Identical on Linux, where `tempname()` is under `/tmp` and `:~` has nothing to do; on Windows the fixtures live under the user's profile and the message says `~/AppData/...`, so the suite passed everywhere it was run and failed only in Windows CI | "a longer file agrees over the bytes it shares" and "but differs from where it grows" — the expected path is now line 4 of the fixture's own output, written by the same `fnamemodify()` call the plugin makes |
| A page past the end of the file being compared with was marked as though nothing on it differed - reported on 120 GiB against a smaller file. Three guards read an empty run of other-file bytes as "no comparison running" when it means "that file has no bytes here"; the workers underneath were all correct. `HexPairPagedDiffActive()` is now the single predicate, over the diff FILE | "a page past the other file's end differs in every byte" + the three with it |
| **On Windows, everything past 2 GiB was read from the wrong place.** xxd carries its seek in a C `long` (`strtol` into `long seekoff`, then `fseek`), which is 32 bits on Windows - and `strtol` SATURATES, so a large offset does not fail, it becomes 2147483647 and xxd reads a page from there. Reported as a 120 GiB file comparing "equal" to a 77 GiB one on pages past the shorter file's end, correct under WSL on the same files. `s:FileHex()` AND the page-display dump in `s:LoadPage()` read past `s:xxdseekmax` through `s:SeekReadHex()` (PowerShell) instead - NOT readblob(), which was tried and cannot do it: Vim's own `read_blob()` in blob.c declares a plain `struct stat` and calls plain `fstat()` where the rest of Vim uses `stat_T` (`struct _stat64` on Windows, vim.h says why), so for a large file it computes a negative length and returns an empty blob AND success, silently. Worth reporting upstream; until then readblob() is no use on Windows for big files, and `s:CopyRange()` still uses it - which is safe only because writes past the limit are refused - both, because they are two separate `xxd -s` calls and fixing only the first left every page past 2 GiB still showing the bytes at 2 GiB (the visible half of the bug: paging back from the end showed one page repeatedly). The dump is then formatted by `HexPairPagedDumpLines()` rather than by xxd, because `-o` would not save it either - that display offset is an `unsigned long`, so the column wraps at 4 GiB; writes past it are refused, since `xxd -r` has the same limit (`base_off`/`want_off`/`have_off` are all `long`) and Vim has no write-at-offset primitive. NOT probeable: `strtol` saturating makes a too-large offset and a past-the-end one look identical from outside, so it is gated on `has('win32')` - which is every Windows Vim, "32 or 64 bits" per Vim's own docs, with `win64` an extra feature on top rather than an alternative; `long` stays 32 bits on Win64 too (Windows is LLP64), so the bitness of the build is not the question | "reading a range with readblob matches reading it with xxd" + the two with it |
| The PowerShell reader's "is this hex?" check was `'^\%(\x\x\)*$'` - a quantified group over the whole run, which on a page-sized string (262144 characters) is E363, "Pattern uses more memory than 'maxmempattern'". Correct-looking and fine on anything short, so it shipped and reached a user on the first big page. `\X` plus an even-length test says the same thing in one linear scan (~7 ms a page). Same family as the `\zs`-consumes-the-newline and negated-collection traps in `s:PagedScan()`: **a regex over a whole page must be tested on a whole page** | "the hex check runs on a page-sized string at all" + the two with it |
| Formatting a page's dump byte by byte in VimScript, when xxd could not be used for it: correct, and 3.5 SECONDS a page (131072 iterations of strpart/str2nr/concat) - which on Windows read as Vim hanging for half a minute on every page turn. xxd's limit is its SEEK, not its formatting: PowerShell now writes the page's bytes to a temp file and xxd dumps THAT from offset 0, with only the offset column renumbered here (`HexPairPagedRebaseDump()`, 8192 map() calls, 25 ms). 3530 ms -> 48 ms. The same page load also used to read the range TWICE, once for the dump and once for `b:hexpair_page_hex`; on a path where starting the process is the cost, that was half the total | "renumbered offsets are what xxd itself would have printed" + the three with it |
| A search match straddling a page boundary was marked on neither page: it fits whole inside neither, and each page was searched alone | "and the page it starts on marks the byte it has" — `s:PageHexForSearch()` reads the page with span-1 bytes of each neighbour |
| Mark completion with nothing typed yet offered nothing: `v:val[0 : strlen('') - 1]` is `[0 : -1]`, the whole name, which matches no empty lead | "mark completion offers all the names, and the matching ones" |
| A selection report echoed from a Visual-mode mapping was painted over by `-- VISUAL --` before it could be read | not testable headlessly — the tmux recipe above, and the hit-enter prompt is the fix |
| Refreshing the other windows (a `wincmd w` there and back) ENDED the Visual selection on every cursor movement, so Visual mode was unusable in `vimhexdiff` | "a Visual or Insert mode keeps this window" — the modes are a pure function, since mode() cannot be driven into a Visual one here |
| The window's markings survived a toggle to the text view and sat there at the columns the hex view had put them | "the text view is left unmarked, not marked in the wrong columns" |
| A Windows `xxd` ends every dump line CRLF (`xxd.c`: `BIN_ASSIGN(fpo = stdout, revert)`, `BIN_WRITE(revert)` - text mode for a dump, binary only for `-r`), and the page loader read it through a `%!` filter, which leaves the CR to `'fileformats'` auto-detection. With `set fileformats=unix` in a vimrc nothing stripped it: a `^M` on every line of every page, cleared by `:HexPairRefresh` only because that path already went through `readfile()` | "a CRLF dump loads without a ^M at the end of the line" and the four checks with it - Windows CI uses the real `xxd.exe`, everywhere else a stand-in supplies the CRLF |
| The page state was assigned before the dump was read, so a failed read left the buffer's bytes and its idea of which page they are disagreeing - and `:w` would have patched the old page's bytes in at the new page's offset | same block: the read and the shape check both happen before anything about the buffer changes |

**The Vim version floor is a claim that has to be run.** The plugin says
everything but the splice works on Vim 8.0; it did not, for a year, and
nothing noticed because CI only ever ran a current Vim. Build the oldest
one and point the suite at it:

```sh
curl -sSLO https://github.com/vim/vim/archive/refs/tags/v8.0.0000.tar.gz
tar xzf v8.0.0000.tar.gz && cd vim-8.0.0000
# -std=gnu89 is NOT optional on a current compiler (checked on GCC 16.2):
# configure's own "uint32_t is 32 bits" probe is a K&R `main()` calling
# exit() with no <stdlib.h>, which a modern default standard rejects
# outright, and configure reports that as "WRONG! uint32_t not defined
# correctly" rather than as a compiler error. The -Wno-error=* flags the
# recipe used to carry do not help, because this is the language standard
# and not a warning.
CFLAGS="-O1 -w -std=gnu89" \
    ./configure --with-features=normal --disable-gui --without-x \
                --disable-nls --with-tlib=ncurses
cd src && make -j4 vim   # from src/, not the top level: 8.0's top-level
                 # Makefile has no `vim` target. `make` alone stops at
                 # xxd/xxd.c, whose K&R prototypes no modern GCC
                 # compiles - use the system xxd instead
cd ..
HEXPAIR_VIM=$PWD/src/vim VIMRUNTIME=$PWD/runtime test/run-tests.sh
```
 The expected result
is 33 failures, all of them inside the splice and save-as scripts —
shortening a file, `:w {file}`, and a grow whose tail is more than half
the file — each refused with the `readblob()` gate message, plus the
assertions that follow such a refusal in the same script. Anything else
failing there is a regression in the baseline; the count itself moves
whenever a test is added to one of those scripts, so read the names, not
the number. The suite itself must stay 8.0-clean
too: no `trim()`, no Blob literal, no `count()` over a string.

Last run before v2.3.0: 447 ok, 33 failures, all of them those — and no
`E...` from Vim anywhere in the output, which is the other half of what
"refused cleanly" means. A refusal shows up in the log as the file being
*unchanged* (`expected: 4984 / actual: 5000`), not as an error; the gate
message itself is not in the output because nothing echoes it there, so
do not go looking for it as the sign the gate fired — the three
`gate message ...` checks near the top are what pin its wording.

**Linting is worth doing by hand, and is not worth automating** (the
maintainer's call, and the numbers back it): `vint` over the two
`.vim` files gives one finding, and it is a false positive — a string
that must be double-quoted because it contains `\n`. `shellcheck -s sh`
over `test/run-tests.sh` and `pack-release` gives 84, of which 81 are
this suite's own deliberate idiom (`printf "$HEX"`, where the format
string IS data with escapes in it) or escaped quotes inside `tr`. The
three that were real have been fixed: a `cd` without `|| exit`, and two
baseline hashes computed and never compared — which is to say two tests
that did not check what their own comment said they did. That last class
is what a manual run before a release is for.

**What the message line SHOWS is not observable from inside Vim**, and
`vim -es` has no message line at all. A message echoed from a mapping can
be drawn over by whatever Vim paints next - `-- VISUAL --` after a `gv`
is the case that bit - and the only way to find out is to look at a real
terminal:

```sh
tmux new-session -d -s hp -x 100 -y 20 "vim -u rc.vim -c 'HexPairOpen f.bin 2'"
python3 -c "import time; time.sleep(1.5)"      # let Vim draw
tmux send-keys -t hp -l 'jvll'                 # keys, one -l string at a time;
tmux send-keys -t hp -l '\\'                     # a backslash needs '\\'
tmux send-keys -t hp -l 's'
python3 -c "import time; time.sleep(0.8)"
tmux capture-pane -t hp -p | tail -3           # what is actually on screen
tmux kill-session -t hp
```

That is how the hit-enter prompt on the selection report, and the
progress line during a scan, were established rather than assumed. Two
traps in the recipe itself: a test vimrc needs `set nocompatible` before
any `<>` key notation (`'compatible'` puts `<` in `'cpoptions'`, and the
mappings are then silently not what they read as), and packages in
`~/.vim/pack` load even under `-u`, so a plugin can be loaded twice.

**A `:~` bug is invisible on Linux, and one line of environment makes it
visible.** Anything the plugin shortens with `fnamemodify(..., ':~:.')` looks
unchanged in this suite, because `mktemp -d` puts `$WORK` under `/tmp` and `:~`
only does something to a path under `$HOME`. On Windows `%TEMP%` *is* under the
user's profile, so the same code prints `~/AppData/...` and an assertion built
from a literal path fails — in Windows CI only. Put the work directory under a
home of its own and Linux reproduces it exactly:

```sh
mkdir -p /tmp/fakehome
HOME=/tmp/fakehome TMPDIR=/tmp/fakehome test/run-tests.sh
```

Worth running before touching anything that prints a file name. The rule it
serves is the one already stated above: **assert against the value the code will
actually use** — here, by having the fixture's own Vim script write out
`fnamemodify(path, ':~:.')` and comparing against that.

**Read the check COUNT, not just the last line.** The suite is one long
sequence of blocks, and an edit that replaces a span of it can swallow
whole blocks that happen to live inside that span - which the suite then
reports as "All tests passed", because what is gone is not failing, it is
absent. `test/run-tests.sh | grep -c '^ok'` against the number before the
change is the tripwire; touching one block at a time is the way not to
need it.

**The property test** (`test/run-tests.sh`, "Property: any shape of dump
writes the bytes it spells") renders one page's bytes in six shapes a
seeded generator invents — offsets or not, ASCII column or not, either
case, lines of two to sixty-four digits, empty lines through the middle —
and requires each write to produce exactly the bytes python says. When it
fails, the round number names the shape. Note the one shape it must NOT
generate, and why: a line with an ASCII column but no offset column,
whose ASCII part contains a ':' (byte 0x3a), has that colon read as the
end of an offset column — the rule working as written (invariant 1), not
a case to hold the write path to.

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

Consequence, now done: `plugin/hexpair_paged.vim` was absorbed back
into `plugin/hexpair.vim` (single file, single script scope) in Stage 2 — once hex mode is unconditionally page-aware, keeping
two files would mean duplicating almost everything (`Layout`, strip,
validate, highlight, cursor mapping), not just the one small
`s:ResolveXxd()` helper Stage 1's split cost. `plugin/hexpair_paged.vim`
is gone, along with its entries in `pack-release.py`'s `FILES` and
`CONTRIBUTING.md`'s repo layout table.

### Stages (renumbered; Stage 1 unchanged, Stages 2-3 replaced, Stage 4 new)

Each stage keeps its own review checkpoint with the maintainer before
the next starts — unchanged rationale: a write-path bug could corrupt
a large real file.

- **Stage 1 — read-only paging and navigation: IMPLEMENTED**, as a
  separate `plugin/hexpair_paged.vim` / `:HexPairOpen` entry point.
  Superseded by, not deleted before, Stage 2: its page-read/boundary/
  banner/highlight machinery is the foundation Stage 2 folds into the
  unified mode, largely unchanged in substance, moved and rewired.
- **Stage 2 — unify into a single always-paged mode: IMPLEMENTED.**
  `plugin/hexpair_paged.vim` is merged back into `plugin/hexpair.vim`,
  `:HexPairToggle` is always paged and moves between the two views, and
  the whole-file dump machinery is gone: `s:Layout`, `s:Highlight`,
  `s:StripDumpLine`, `s:ValidateDump`, `s:ReverseDump`, `s:DumpOffset`,
  `s:DumpPos`, `s:CursorByte`, `s:PreWrite`, `s:PostWrite`,
  `s:PostReload` and `s:FromHex` all had `s:Paged*` counterparts, which
  are now the only implementation, and `b:hexpair_active` collapses
  into `b:hexpair_page_active`.
- **Stage 3 — same-length in-place patch write: IMPLEMENTED.**
  Mechanism exactly as "Writing a page" below describes, and driven
  from both views: `s:Write()` gets the page's new bytes either by
  stripping the dump or by taking the text view's lines as they are.
- **Stage 4 — length-changing write: IMPLEMENTED**, likewise, including
  the narrowed runtime version gate this redesign called for. Went
  further than the plan: an insert does not rewrite the file at all any
  more, only what follows it (see "Writing a page" below).

Stages 3 and 4 were built before Stage 2 because the write path was
what the feature was missing, and because it turned out to be
independent of the unification: it works on "these N bytes replace the
file's `[base, base+len)` range", which is true of a Hex-page-view
buffer however it was populated - and, once Stage 2 landed, of a
Windowed-text-view one too.

### The three buffer states and how a buffer moves between them
(implemented; `s:IsHexView()`, `s:ToHex()`, `s:ToText()`, `s:ToHexView()`,
`s:PageSource()`, `s:SetupPagedBuffer()`)

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
living. It takes the OPERATION as its second argument for the same
reason: the message used to state flatly that "only same-length edits
can be written", which stopped being true the moment an insert started
moving the tail in place, so each caller names the operation that
actually needs the newer Vim rather than restating the sentence.

### Reading a page: the `:HexPairOpen` population path

Stage 1's existing mechanism, unchanged by this redesign — one of the
two population paths from "two population paths" above; the other
(buffer-slicing, for `:HexPairToggle` on an already-existing buffer)
was designed and built in Stage 2 - see "What Stage 2 decided".

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
  Stage 2 settled both questions, and they are settled still: every
  hex-mode buffer is `buftype=acwrite` with a `BufWriteCmd` (see "What
  Stage 2 decided"), because letting Vim do the writing would put a
  buffer holding one page over the whole file; and both population paths
  end in `s:SetupPagedBuffer()`, so the rest of the plugin cannot tell
  which one a given Hex-page-view buffer took to get there.
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
  realistically approach 4 GiB. `s:PagedLineLayout(lnum)` reads the
  width off **the line itself** — the offset column ends at the first
  `:`, the rule the whole plugin already shares (invariant 1) — so a
  page that straddles a widening simply carries both widths, each line
  laid out correctly, and bare hex lines a user inserts (no offset
  column at all) come out right for free. `s:PagedOffsetLayout(off)` is
  the same thing for a caller that knows an offset but not yet the
  line. `b:hexpair_page_hexstart` remains only as the page's *first*
  line's value, for the initial cursor placement.

  This replaced an earlier scheme that instead kept the width uniform
  per page, by splitting the file into width-segments at every `16^8`,
  `16^9`, … and clamping page boundaries to them
  (`HexPairPagedWidthBoundaries()`, now gone). Both are correct; per
  line wins because it lets pages stay **plain fixed-size slices**, so
  `base = idx * size` holds everywhere, page numbering never shifts
  when a file grows past a boundary, and the page holding a given byte
  offset is a division — and because it is the only one of the two that
  also handles a line with no offset column.
- Pair highlighting, from the base plugin's `s:Highlight()` (see
  above), additionally skips banner lines entirely (see "Page banner").
- `s:PagedScan(lnum)` — ONE pass over the page returning `err`
  (validation), `lines` (stripped payload) and `bytes` (bytes before
  `lnum`), which is what a write needs. It replaced three separate
  walks, and the walk itself is gone too: `s:PagedPayloadText()` applies
  the three rules as **whole-page regexes** (banner lines, then offset
  columns, then ASCII columns), because VimScript's per-iteration
  overhead - not the matching - was what a walk over 8192 lines cost.
  A same-length write on the default page went 571 ms → 129 ms this way,
  `:HexPairPages` 274 ms → under a millisecond (that one via the
  canonical fast path below). The per-line `s:PagedPayload()` stays the
  reference implementation and still locates the offending line when a
  page is rejected; `HexPairPagedScanLines()` lets the suite hold the
  two against each other on a full-size page.
- **Two Vim regex traps live in that pass. Do not undo them:**
  - `'\%(^\|\n\)\zs…'` still CONSUMES the newline it matched, so a
    line whose strip comes out empty (a banner, an empty line) leaves
    the scan inside the *next* line, whose offset column then survives
    into the payload. The newline is matched and put back with `\1`.
    A lookbehind is correct and quadratic: ten seconds on one page.
  - a negated collection matches the end-of-line whatever is listed in
    it (`:help /[\n]`), so `'[^0-9a-fA-F \n]'` does not mean what it
    reads as - and *looks* right on a short string: the same page
    validated at 2000 lines and was rejected at 4000. Line breaks are
    removed with the `\n` ATOM (`s:PagedFlatten()`) before any
    collection is applied. This is why the scan is tested against a
    6250-line page and not a handful of lines.
- `s:PagedLineBase()` / `s:PagedOffsetAt()` — position → byte offset for
  ANY position, not just the cursor's (`s:PagedByteOffset()` is the
  cursor wrapper; the selection report needs the same mapping for the
  two ends of a selection). While the buffer is **unmodified** the page
  is exactly what xxd produced, so the bytes above a line are
  `(line - 1 - header) * n` and no pass is needed; the within-line part
  goes through the same `s:PagedLineIndexAt()` either way, so the two
  paths cannot read a line differently. This is what keeps `:w` (which
  reports the cursor byte when it finishes) off a second pass, and what
  makes `HexPairStatus()` safe to call on every cursor movement.
- `b:hexpair_page_header` / `s:HeaderLines()` — how many lines sit above
  the first dump line: the banner, plus the ruler when
  `g:hexpair_ruler` was on at page load (snapshotted like `b:hexpair_n`,
  and for the same reason). See invariant 7.
- `s:RulerLine()` / `s:HexViewLines()` — the ruler is built for the
  page's FIRST line's layout, and starts with `"`, which is what already
  makes a line contribute no bytes. `s:HexViewLines()` is the one place
  the hex view's shape (banner, ruler, dump, banner) is spelled out, so
  `s:LoadPage()` and `s:ToHexView()` cannot build different views.
- `s:PageDigest()` / `s:CheckFresh()` — freshness is about THIS PAGE,
  not about the file: the size must be unchanged (a different length
  moves every page after the change) and the page's own bytes must hash
  to what they did when it was read. The modification time is only the
  fallback for a Vim without `sha256()` — it cannot see a change made
  within the same second, and it cannot tell a change to this page from
  a change to the rest of the file, which is what made two views of one
  file impossible to write from (see below). A successful check adopts
  the new mtime, so the fallback path does not go on complaining.
- Finding, comparing and marking all rest on **one file read helper**,
  `s:FileHex(file, off, len)` — a byte range of any file as one flat run
  of lowercase hex. What it strips from xxd's output is the line breaks,
  and it does that as **two passes over one character each** (`\n`, then
  `\r` for a Windows xxd) rather than one over a negated collection:
  measured on the 2 MB of hex a 1 MiB block comes to, 16 ms against
  51 ms, and a scan of a large file is thousands of those. A 64 MiB
  `:HexPairDiffNext` went 11.4 s → 5.4 s on that change alone; what is
  left is `system()` and xxd themselves (4.2 s of the 5.4 s), which is
  the floor for as long as reading a range of a file means running xxd.
  Two ways of looking at such a run:
  - `HexPairPagedFindInHex()` — where a pattern matches, **on a byte
    boundary**: an index into hex is a nibble and half of them are the
    wrong half, which is the one thing every caller of `match()` here
    has to remember.
  - `HexPairPagedFirstAgreement()` / `LastAgreement()` — where they agree
    again, which is what makes a CHANGE (a run of differing bytes) a
    thing the jumps can move between. Agreement is not a prefix property,
    so it cannot be halved: a chunk that is identical is one comparison
    and agreement at its first byte, and only a chunk that is not gets
    taken apart with `split()`/`filter()`. A change that runs to the end
    of a large file therefore costs a read of the rest of it — which is
    also what "is there another change?" honestly costs.
  - `HexPairPagedFirstDifference()` / `LastDifference()` — where two runs
    part company, by **halving**, never by walking: comparing two strings
    is one C-level operation and a block is megabytes of hex. One string
    being a prefix of the other IS a difference, at the point where the
    shorter one ends (that is how a longer file compares).
  Blocks overlap by the pattern's length less one byte, so a match across
  a seam is whole in one of them; the diff needs no overlap, since a
  difference is one byte wide.
- `HexPairPagedCountDifferences(mine, theirs)` — how many bytes of a page
  differ and where the first one is. **Never walk two runs of hex**: a
  block that matches is one string comparison, and only a block that
  differs is taken apart (with `split()` into pairs and `filter()`, which
  beats a loop even when everything differs). Measured over a 128 KiB
  page: a walk cost 4.9 s, this costs 0.6 ms when the pages match, 8 ms
  with a handful of differences and 260 ms when every byte differs. The
  block is 1024 bytes because that is where skipping matching bytes
  faster and taking apart differing ones slower meet (256…16384 measured).
- `s:ModifiedRuns()` / `s:ModifiedJump()` — walking the bytes edited and
  not yet written, the way the diff jumps walk changes. **Page-scoped by
  nature, not by limitation**: turning a page needs an unmodified buffer
  or a bang that discards, so edited bytes only ever exist on the page in
  view — which is why this needs no file-wide scan. The runs come from
  `HexPairPagedDifferingByteRuns()` in the hex view (the page's payload
  against `b:hexpair_page_hex`) and from `HexPairPagedTextRuns()` per line
  in the text view, and `HexPairPagedJoinRuns()` puts touching ones
  together — the text view compares line by line, so an edit spanning a
  line break arrives as two. Cached against `b:changedtick`, because the
  hex view's half is a whole-page scan and the key gets pressed repeatedly.
- `s:Progress()` / `HexPairPagedProgressText()` — a file-wide scan reads a
  megabyte at a time and can run for minutes, which is indistinguishable
  from a hang, so from 16 MB up it says how far it has got. **The redraw
  goes after the echo and must not be `redraw!`**: a forcing redraw
  repaints from scratch, and what it paints does not include a message a
  running function echoed, so `echo` + `redraw!` wrote the line and wiped
  it again dozens of times a second and the report was never readable —
  which the measurement that put the `!` there missed by counting how
  often something appeared rather than how long it stood. `s:Stopped()`
  is the one that redraws *first*: it is the last word after an
  interrupted scan, and a repaint after it would take it with it.
  The line is echoed only when it would differ from the one already
  there, and it carries the size as well as the percentage — one per cent
  of 70 GiB is 700 MB, minutes between two figures.
  **`CTRL-C` reaches a scan only if nothing swallows it**: inside a
  `:try` it is the exception `Vim:Interrupt`, a bare `:catch` catches it
  like anything else, and it cannot be caught and re-thrown (E608). Every
  `:catch` on a scan's path therefore names what it is for
  (`s:FileHex()`: `catch /^hexpair:/`), and the two scan entry points
  (`s:FindFrom()`, `s:DiffJump()`) catch `/^Vim:Interrupt$/` and say
  `hexpair: stopped`. Interrupting is safe because a scan only reads.
- `s:BindPageTurn()` / `s:FollowPageTurn()` — `'scrollbind'` is Vim's own
  "these windows move together", and a page turn is the one kind of
  scrolling it cannot follow: the bound window keeps its page and the two
  then scroll in step through different parts of their files, which is
  what `vimhexdiff` looked like it was doing wrong. Every bound window
  showing a page follows by BYTE (two views need not be paged the same
  way), cursor included. `s:binding` stops a followed turn from being
  passed back; the followed window's own `'scrollbind'` comes off while
  its page loads, since filling a window scrolls it and that scroll would
  drag the window the turn came from. A window with unwritten changes, or
  whose file does not reach that far, is left where it is **and says so** —
  a bound window quietly showing something else is the bug being fixed.
  `g:hexpair_bind_pages` turns the whole thing off. It ends with
  `:syncbind`: 'scrollbind' syncs RELATIVE movement from wherever each
  window was when it was bound, and a page load moves a window without
  saying that this is the new zero - so without it the two scroll in step
  around whatever offset they happened to have before the turn.
  **That `:syncbind` must be the last thing in the key press that
  scrolls.** It sets Vim's `did_syncbind`, and the next scrollbind check
  Vim would have made is then skipped — so a levelling done before this
  window has finished moving swallows the movement that follows it. That
  is why `s:GotoOffset()` passes `s:GotoPage()` a 0 and calls
  `s:BindPageTurn()` itself once the cursor has arrived, with the byte it
  arrived at: a jump to a byte on another page is two movements, and only
  the second one is where level is. It is called for EVERY jump, page turn
  or not (`force`): syncing only across a page boundary meant the same
  keystroke took the other window along or did not, depending on how far it
  happened to go. Moving the cursor by hand is the one thing that does not
  sync — `:HexPairSyncViews` is the way back from that.
- **The markings are drawn in both views**, and `HexPairPagedMarkingPositions(layer, first, last)`
  is the one entry point that says where — dispatching on the view so the
  four layers cannot drift apart about which one they are drawing in, and
  so the suite can ask for lines a headless window (one line tall) never
  shows. The text view builds them out of byte RUNS (`[offset, length]`,
  page-relative) and one mapper (`HexPairPagedTextPositions()`) puts the
  runs on the lines: a dump has three columns per byte, a page of text
  one, and the line break ending a line is a byte with no column, so it
  is the one byte never marked.
  The two comparing layers there work **string against string in the text
  view's own spelling** (`HexPairPagedTextRuns()`), not by turning the
  buffer back into hex: a Vim string cannot hold a NUL and both sides
  write one as a line break, since both come from `readfile(..., 'b')`.
  That costs one documented blind spot — a NUL replaced by a line break
  at the same offset is not marked — and buys a comparison that needs no
  per-byte conversion. Everything else is in bytes and stays right on the
  two inputs a test rarely has: CRLF line endings (the CR is data, and
  `s:SetupPagedBuffer()` forces `'fileformat'` unix so `line2byte()`
  counts one byte per break on Windows too) and multi-byte characters
  (`strlen()`, `strpart()` and `matchaddpos()`'s columns are all byte
  counts). The one thing a byte offset cannot do there is put the cursor
  INSIDE a character; the hex view reaches every byte.
  Guard: "a paged buffer is 'fileformat' unix whatever the platform
  prefers" and the block of checks under it. The other side of each comparison (the page as
  read, the file being compared with) is one `xxd -r -p` per page, kept
  against the hex it was made from (`s:BytesAsText()`), so a redraw pays
  nothing for it.
- `HexPairPagedComparePositions(first, last, hex)` — the shared body of
  every byte-level marking: compare the lines on screen against a run of
  hex at the position the layout puts them, and give back
  `matchaddpos()` runs for both columns. Three callers, three groups:
  the modified bytes (against `b:hexpair_page_hex`, the page as read),
  the diff (against the other file's bytes for this page), and the
  search (`HexPairPagedFindPositions()`, from the match list). Each
  caches on its own `w:` state (`[pattern/tick, page, w0, w$]`) so a
  plain cursor movement redraws nothing.
- **`:HexPairReplace` checks the BUFFER, the marking shows the FILE.**
  The two part company as soon as anything is replaced — the file still
  holds the pattern where the buffer no longer does — and a second
  replace on the spot would otherwise overwrite bytes that are no longer
  a match. The marking stays about the file because that is what makes
  it free to draw; an edit shows as a changed byte instead.
- `s:SpliceIntoPage()` — how both replace commands edit: splice the new
  hex into the page's current digit run and rebuild the view through the
  same `s:CanonicalDump()`/`s:HexViewLines()` the toggle uses. Nothing
  new touches the file: `:w` writes it, and a length change meets the
  same confirmation as any other insert or delete.
- `s:marks` — absolute byte offsets per FILE, not per buffer, so two
  views share them and a page turn cannot disturb them. Vim's own marks
  cannot do this: a paged buffer holds a different part of the file from
  one page to the next.
- `s:WindowView()` — the `WinEnter` half of the same feature, behind
  `g:hexpair_split_views` (default 0): a window that has just become the
  SECOND one showing a page turns into a view of its own. `WinEnter`
  rather than `WinNew` (8.1.1058, past the baseline) or `BufWinEnter`
  (does not fire when an already-displayed buffer is shown again —
  measured). It runs once per window because every window holding a view
  is marked `w:hexpair_own_view`, and **window-local variables are not
  copied into the window a `:split` creates** — measured too, and the
  whole reason the mark can mean "this window was here first". The
  windows are counted across all tabs (`tabpagebuflist()`), so
  `:tab split` counts.
- `s:NewViewHere()` — the one place a window becomes a fresh view:
  marks the window first (so the events its own `s:Open()` raises cannot
  re-enter `s:WindowView()`), then reopens and puts the cursor back on
  the byte, in the same view (hex/text) the window came from.
- `s:NamePageBuffer()` / `s:SplitView()` — a second view of one file.
  The buffer name is the file's plus a tag, numbered when that name is
  taken; the collision is detected by TRYING the rename and catching
  E95, because Vim's own rules for when two buffer names are the same
  (a relative path and its absolute form, case on Windows) are not
  worth reimplementing. `:HexPairSplit`/`:HexPairVSplit` resolve the
  requested page in the CURRENT view's terms and hand the new view the
  byte it starts at, so the two agree even if `g:hexpair_page_size`
  changed in between; everything that can be refused is refused before
  the window is split. A spilled (piped) view refuses to split at all:
  its temp belongs to that buffer and dies with it.
- `HexPairStatus()` — `'statusline'` support; empty outside hexpair
  buffers so one statusline serves every buffer. Must never walk the
  page: it is called on every cursor movement. On an edited page it
  marks a `+` and reports the canonical byte, and says so in the help.
- `HexPairPagedSelectionBytes()` / `HexPairPagedSelectionText()` — what
  a Visual selection covers, split into geometry and wording. Global and
  parameterized by the two ends and the mode, like
  `HexPairPagedSelectionPositions()` next to it, because Visual mode
  cannot be driven under `vim -es`.
- The data inspector — `s:InspectBytes()` reads at most eight bytes
  **from the page as the buffer holds it**, without walking it: out of
  the payload digits from the cursor onward in the hex view, and through
  `writefile(..., 'b')` on the two or three lines involved in the text
  view (the only exact way to get bytes out of a Vim string, where a NUL
  lives as a NL). Everything downstream of it is pure and tested
  directly: `HexPairPagedInspectLines()`, `HexPairPagedIeeeText()`
  (decoded from the BYTES, with the mantissa carried as a Float, so
  nothing depends on how wide a Number is), `HexPairPagedU64Text()` and
  `HexPairPagedDecSub()` (a 64-bit pattern with its top bit set has no
  unsigned form in a signed Number, so it is printed by subtracting in
  decimal), `HexPairPagedBinaryText()` (no `%b` on the supported Vim).
- Loading a page happens with `'undolevels'` at **-1, buffer-locally**
  (|clear-undo|), so the undo history never survives a page turn:
  a single `u` afterwards would otherwise put the bytes of a different
  part of the file into a buffer that claims to be this page, which a
  write would then patch in at this page's offset. Buffer-local because
  `'undolevels'` is global-local — setting only the global one leaves a
  buffer that has its own value with its history intact. Undo of edits
  made *within* the loaded page works normally.

### Page boundary arithmetic

`HexPairPagedBounds(idx, size, total)` / `HexPairPagedTotalPages(size,
total)` are global, pure functions (no I/O, no buffer/window state):
page `idx` is simply `[idx * size, idx * size + size)`, clipped by
`total`, and the page count is `total` divided by `size`, rounded up.
Nothing about the file's content or xxd's formatting perturbs that —
see the offset-width note above for why it does not have to. Being
pure and parameterized by a `total` the caller supplies (not read from
a real file), they are directly testable against a fabricated multi-GiB
`total` without needing an actual multi-GiB test fixture.

### Page banner

Leading/trailing single lines the plugin generates and inserts around
the `xxd` output, e.g. `" hexpair: page 3/349  bytes
262145-393216 of 45678901  bigfile.bin"` / `" hexpair: end of page
3/349"`. The byte range in this text (and in `:HexPairPages`, via the
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
`"` either). `s:PagedPayload()` (banner-aware counterpart of the base plugin's
`s:StripDumpLine()` — extending invariant 1, and the one place the rule
lives for this mode: the stripper, the validator and the cursor mapping
all call it) skips banner lines *before* its normal payload logic runs, so banner
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

Unified by Stage 2: `:HexPairPageNext`/`Prev`/`Goto`/`Pages` work on
*any* Hex-page-view buffer, however it was reached — `:HexPairToggle` or `:HexPairOpen`
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
  bytes (file)`, plus the byte under the cursor.
- `:HexPairPageGoto {page}` — `{page}` is a number, `+N`/`-N` to step,
  or `$` for the last page; `HexPairPagedParsePageInput()` (pure) says
  which, `HexPairPagedResolvePage()` (pure) turns it into a page number
  against the one in view, and both feed the prompt as well as the
  command. A step past either end is REFUSED, not clamped — the same
  "page N does not exist" a number out of range gets — so a mistyped
  step does not quietly land somewhere else.
- `:HexPairInspect`, `:HexPairSelection` — the data inspector and the
  selection report; see the function map above for how the bytes and
  the geometry are obtained without walking the page.
- `g:hexpair_ruler` — see invariant 7; the option is snapshotted into
  `b:hexpair_page_header` at page load, never read directly by the
  arithmetic.
- `g:hexpair_page_size` — default `128 * 1024` (128 KiB; the plan drafted
  64 MiB, then 1 MiB, and what settled it was how long a page takes to
  scan rather than how much of the file one wants in view — small enough
  to set down to e.g. `512` for tests). Validated as a positive multiple of
  `g:hexpair_bytes_per_line` by `HexPairPagedSizeError()`, snapshotted
  into `b:hexpair_page_size` at `:HexPairOpen` time (mirrors
  `b:hexpair_n`'s snapshot of `g:hexpair_bytes_per_line` in the base
  plugin) so a later global change cannot desync an open page buffer.

### Stage 1 gaps — CLOSED

Both were closed without waiting for the unification, since they are
missing behaviour rather than structure, and both needed only a
hand-off across the two script scopes rather than a copy of the logic:

- `:HexPairGoHex`/`:HexPairGoAscii`/`:HexPairSwap` — `s:JumpTo()` in
  the base plugin hands a buffer with `b:hexpair_page_active` over to
  `HexPairPagedJumpTo()`, which does the same job against
  `s:PagedLineLayout()` and skips banner lines.
- `g:hexpair_paste` — `s:PasteOn()`/`s:PasteOff()` now accept either
  mode's active flag, and are reachable from the paged script as
  `HexPairPasteOn()`/`HexPairPasteOff()`, which its `BufEnter`/
  `BufLeave` autocommands call. One implementation, one buffer-local
  saved value, both modes.

### Writing a page — two mechanisms, chosen by length (Stages 3/4, IMPLEMENTED)

`s:Write()` on `BufWriteCmd` is the entry point; every refusal is a
`throw`, not an `echomsg` — Vim does not clear `'modified'` just
because a `BufWriteCmd` ran, but a thrown error is a hard-to-miss
`:write` failure rather than a message that scrolls past, and matches
how a genuine write failure (disk full) surfaces. Around both
mechanisms: `s:CheckWriteTarget()` refuses a `:w {other}` (the
autocommand fires for those too, and the page would otherwise be
patched into this view's own file), `s:PagedScan()` validates,
`s:CheckFresh()` compares size and mtime against the read-time
snapshot, and `s:ReloadAfterWrite()` re-reads from disk afterwards and
puts the cursor back by absolute offset — clamping the page index to
what is left, since a splice can change the page count, and falling
back to `s:LoadEmpty()`'s lone banner if a shrink emptied the file.

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

**Grew (insert): IN PLACE, tail only.** Bytes cannot be spliced into the
middle of a file, but only what FOLLOWS an insertion has to move — what
precedes it is never even read. `s:GrowInPlace()` shifts the tail right
from the END backwards (so a block is never written over one that has
not moved yet) and then patches the page in; appending to the last page
moves nothing at all. Two xxd calls do it, so this path needs nothing
newer than the base plugin's Vim:

    xxd -s O -l L -p FILE HEX     read a byte range out as plain hex
    xxd -r -p -s O HEX FILE       write it back at any offset, in place

Verified before being relied on: a multi-line plain dump lands
contiguously, neither call ever truncates the target, and writing past
the end extends the file. The tail is copied out first — while it is
moving that copy is the only intact one of those bytes, and writing it
first also makes a full disk fail before anything has been touched.
`s:TailShiftIsCheaper()` picks between this and the splice: moving the
tail costs about 8× its size, rewriting the file about 4× its own, so
the shift wins while the tail is under half the file — which is also
exactly when its recovery copy is the smaller of the two.

**Shrank (delete): still a full rewrite.** Moving the tail left is the
same operation, but the file would then still be its old length with
stale bytes at the end, and nothing in Vim or xxd can shorten a file
except by writing it afresh. Splice in pure VimScript
(`s:Splice()`/`s:CopyRange()`, 8 MiB blocks) —
`readblob(file, off, len)` block-copy loop (block size ~8 MiB, bounded
memory) of head → temp, append the edited page's raw bytes, block-copy
tail, then replace the original by block-copying back (not `rename()`:
temp usually lives on a different filesystem, notably with `/mnt/c/...`
paths under WSL). O(file size), therefore:
- the size delta and the rewrite are stated and confirmed
  (`HexPairPagedResizeMessage()` + `confirm()`; `g:hexpair_page_confirm`
  = 0 answers yes automatically, which is also the only way the path is
  testable — `confirm()`, like `input()`, cannot run under this
  project's headless harness);
- the temp is kept as a recovery copy **only** where it is one: a
  failure while *building* it deletes it, since nothing has reached the
  target yet, while a failure while *copying it back* keeps it and
  reports its path.

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

Stage 2, done: `:HexPairToggle` on a small already-loaded file lands
on Hex-page-view with exactly one page and the pre-paging byte-for-byte
behaviour, plus a `1/1` banner; on a multi-page file it starts on the
page containing the cursor's byte offset, not always page 1; toggling
Hex-page-view → Windowed-text-view → Hex-page-view round-trips the
cursor byte exactly (same invariant as the base-plugin toggle) and
shows the banner in both directions; an unnamed/piped buffer (`vim -`
equivalent in the test harness — feed content via stdin or construct
with `enew` + `setline()`) reaches Hex-page-view via the
buffer-slicing path with no crash and no attempt to read a nonexistent
file.

Stages 3/4, done: the same-length patch leaves the head and the tail of
the file bit-identical (hashed on both sides of the page) and does not
change its length, on a full page, on the short last page, and across
the 4 GiB offset-width change on a **sparse** fixture; splice
correctness for grow and shrink, hashing the moved head and tail; the
temp directory is empty again after a successful splice, while a splice
whose copy back fails — simulated by making the target read-only,
skipped when running as root — keeps the complete new content and
leaves the original untouched; an invalid dump, a file changed on disk
and a `:w {other}` are each refused with the file untouched; emptying
the only page leaves a view saying so; and both the splice version gate
and the resize prompt are tested through their parameterized message
functions, since neither `has()` nor `confirm()` can be driven here.
The same paths are covered from Windowed-text-view too, because that
view sources the page's bytes differently (a `readfile`/`writefile`
binary round trip instead of stripping a dump): an unedited write
changes nothing, a same-length edit patches only the page and leaves
the rest of it byte-identical, a growing edit moves the tail, and an
edited banner refuses the write.

### What Stage 2 decided

Three questions the redesign left open, and how they came out:

- **The banner cannot be recognized by content in the text view.** In a
  dump, a line starting with `"` is unambiguous — data lines start with
  a hex digit. In a page of raw bytes, `0x22` is a perfectly ordinary
  first byte, and the write path takes the buffer's bytes as they are.
  So the exact banner text is kept in `b:hexpair_banner_top` /
  `b:hexpair_banner_bottom` when a view is built, and only an exact
  match on line 1 and line `$` counts (`s:TextBodyRange()`); anything
  else refuses the write and says to reload the page. `s:IsBannerLine()`
  still does the job in the dump, where it is not ambiguous.
- **Exact bytes through a text buffer** go through `readfile(f, 'b')`
  and `writefile(lines, f, 'b')`, which are inverses of each other about
  the split on newlines, about a trailing one, and about Vim storing a
  NUL byte as a NL *inside* a line — which is what `getline()` alone
  cannot round-trip.
- **`buftype`** is `acwrite` with a `BufWriteCmd` on *every* hex-mode
  buffer, both entry points, both views. Not `BufWritePre`/`BufWritePost`:
  those let Vim do the writing, and a buffer holding one page would be
  written over the whole file.

A fourth question the redesign did not raise: **a modified file-backed
buffer**. The plan chose buffer-slicing partly so that `:HexPairToggle`
would not discard unsaved edits by re-reading from disk — but slicing
does not save them either, because a page-range write only ever writes
the visible page, so every edit outside it is dropped at `:w` instead.
Both ways lose data quietly, so this case is refused (`s:PageSource()`),
naming the two ways out: write the buffer, or `:HexPairOpen` the file.

### Explicit non-goals (for now)

- No way to make a file SHORTER without rewriting it. Inserting bytes
  moves only the tail, in place; deleting them cannot, because nothing
  in Vim or `xxd` can truncate. (This line used to say the same about
  inserts, and stopped being true.)
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

### Accepted risks — decided, not overlooked

- **Staleness detection is size plus mtime**, all a portable Vim can
  see. A change made within the same second as the page was read *and*
  of exactly the same size slips through. Documented in the help.
- **A length-changing write is not atomic.** The temp is copied back
  over the original rather than renamed onto it, so the target keeps
  its inode, owner and permissions — and because the temp usually lives
  on another filesystem, notably for `/mnt/c/...` under WSL. If that
  copy is interrupted the file is incomplete, and the temp, kept in
  exactly that case, is the recovery copy whose path is reported.
- **The cursor across a `++bin` reload** is exact for single-byte
  encodings and for any encoding where 0x0a separates lines; binary
  data opened *without* `-b` still maps approximately.
