" hexpair.vim - Hex viewing with hex<->ASCII pair highlighting
" Maintainer:  Michal Růžička <ruzicka.mich@gmail.com>
" URL:         https://github.com/michal-ruzicka/hexpair
" Version:     2.1.0-devel
" Date:        2026-08-21
" License:     Vim License - same terms as Vim itself (see LICENSE.md
"              or :help license); SPDX-License-Identifier: Vim
"
" Toggles the current buffer between its normal representation and an
" xxd hex dump (filetype=xxd, so standard syntax highlighting applies).
" While in hex mode, the byte under the cursor is highlighted in BOTH
" columns: put the cursor on a hex byte and the matching ASCII character
" lights up, and vice versa.
"
" Writing (:w) is safe in hex mode: the buffer is transparently converted
" back to binary before the write and re-converted afterwards, so the
" original binary content is what ends up on disk.
"
" Files too large to hold in a buffer are viewed one PAGE at a time with
" :HexPairOpen, which reads only that page off disk - a hex dump with
" ABSOLUTE file offsets, bracketed by a banner saying which page it is.
" :w writes just the page back: an edit that kept its length patches it
" in place, one that changed the length splices the file.
"
" Commands:         :HexPairToggle, :HexPairGoHex, :HexPairGoAscii,
"                   :HexPairSwap, :HexPairRefresh, :HexPairOpen,
"                   :HexPairPageNext, :HexPairPagePrev,
"                   :HexPairPageGoto, :HexPairPages
" Mapping:          none by default; map <Plug>(HexPairToggle) in your vimrc
"
" Configuration (set in your vimrc before the plugin loads):
"   g:hexpair_bytes_per_line   bytes per dump line (default 16)
"   g:hexpair_paste            set to 0 to stop the plugin from managing
"                              the global 'paste' option while the cursor
"                              is in a hex buffer (default 1)
"   g:hexpair_page_size        bytes per page (default 128 KiB)
"   g:hexpair_page_confirm     set to 0 to skip the confirmation a
"                              length-changing write asks for
"   g:hexpair_debug            set to 1 to echo position-mapping traces
"                              (inspect with :messages)
"   HexPairActive, HexPairMirror, HexPairPageBanner  highlight groups
"
" Editing defaults for the dump (tabstop, shiftwidth, no automatic
" formatting) live in the bundled ftplugin/xxd.vim; see
" :help hexpair-ftplugin for how to overrule them.

if exists('g:loaded_hexpair')
  finish
endif
let g:loaded_hexpair = 1

let s:cpo_save = &cpo
set cpo&vim

" ---------------------------------------------------------------------------
" Configuration defaults
" ---------------------------------------------------------------------------

if !exists('g:hexpair_bytes_per_line')
  let g:hexpair_bytes_per_line = 16
endif

if !exists('g:hexpair_paste')
  let g:hexpair_paste = 1
endif

" A page is an ordinary Vim buffer, so everything it costs is what that
" many lines cost: at 16 bytes per line, 128 KiB is 8192 lines, which
" loads in hundredths of a second and writes in about a third of one.
" The size buys nothing in return - :HexPairPageGoto reaches any page
" directly - so it is deliberately small; raise it only to see more of
" the file at once, and expect a write to slow down roughly in
" proportion (1 MiB ~ 2.4 s, 4 MiB ~ 9.5 s on the author's machine).
if !exists('g:hexpair_page_size')
  let g:hexpair_page_size = 128 * 1024
endif

" A write that changes the page's length cannot patch in place - the
" whole file has to be rewritten - so it asks first. Set to 0 to answer
" yes automatically, which is also what makes the length-changing write
" path testable: confirm(), like input(), is unusable under this
" project's `vim -es -u NONE` harness.
if !exists('g:hexpair_page_confirm')
  let g:hexpair_page_confirm = 1
endif

" Position-mapping trace, off by default. Every step that turns a cursor
" position into a byte offset or back says which it made, so :messages
" holds the whole chain after the fact - which is what a field report
" about "the cursor landed on the wrong byte" needs, and how two such
" bugs were actually found.
if !exists('g:hexpair_debug')
  let g:hexpair_debug = 0
endif

" Highlight groups for the byte-pair highlight:
"   HexPairActive - the byte in the column the cursor is in (subtle)
"   HexPairMirror - its counterpart in the other column (prominent)
" Users may redefine either group, e.g.:
"   highlight HexPairMirror ctermbg=52 guibg=#5f0000
highlight default HexPairActive cterm=underline gui=underline
highlight default link HexPairMirror IncSearch

" Highlight group for the page banner (leading/trailing comment lines).
" xxd.vim's bundled syntax file defines no comment group to link to
" (only xxdAddress/xxdSep/xxdAscii, all tied to real dump lines), so
" this is the plugin's own, following the HexPairActive/HexPairMirror
" precedent above.
highlight default link HexPairPageBanner Comment

" --------------------------------------------------------------------------
" Vim version gate
" --------------------------------------------------------------------------
"
" ONLY the splice - a write that shortens the file, a growing one whose
" tail is more than half of it, and ':w {file}' - needs readblob(), available
" since patch 8.2.4906, and 64-bit Numbers for large absolute offsets
" (+num64, standard on modern builds). Everything else - reading pages,
" navigating them, the same-length in-place write and the in-place
" insert - runs on the Vim 8.0 baseline the rest of the plugin requires,
" so the check is made at the moment a splice is actually needed rather
" than refusing to load the feature at all. Factored into a function of an
" explicit boolean (rather than calling has() internally) so its
" failure branch - which cannot be produced by an actual old Vim in
" this project's test environment - can be tested by passing 0.

" Global (not script-local) so test/run-tests.sh can call it directly
" with both true and false without needing an actual unsupported Vim.
" The optional argument names the operation that needs readblob(), so each
" caller says what it was about to do; it defaults to the splice.
function! HexPairPagedGateMessage(supported, ...) abort
  if a:supported
    return ''
  endif
  let what = a:0 ? a:1 : 'rewriting the file to change its length'
  return printf('hexpair: %s needs Vim patch 8.2.4906 or later with ', what)
        \ . '+num64 (readblob(), 64-bit Numbers for large file offsets); '
        \ . 'this Vim does not qualify - nothing was written. An edit that '
        \ . "keeps the page's length, or that inserts bytes with no more "
        \ . 'than half the file after them, does not need it.'
endfunction

" Checked where it matters: s:Splice(). has() cannot be faked, so the
" message itself lives in the function above, which the suite tests
" directly.
function! s:SpliceSupported() abort
  return has('patch-8.2.4906') && has('num64')
endfunction

" Global (not script-local) so it is directly testable: a positive
" multiple of bytesperline is required, and both are passed explicitly
" rather than read from g: internally, so tests do not need to fiddle
" with global state to exercise the error branch.
function! HexPairPagedSizeError(size, bytesperline) abort
  if a:size <= 0 || a:size % a:bytesperline != 0
    return printf('hexpair: g:hexpair_page_size (%d) must be a positive '
          \ . 'multiple of g:hexpair_bytes_per_line (%d)',
          \ a:size, a:bytesperline)
  endif
  return ''
endfunction

" Blocks the length-changing write copies in. Bounded on purpose: the
" whole point of paging is that memory use does not follow the size of
" the file.
let s:blocksize = 8 * 1024 * 1024

" ---------------------------------------------------------------------------
" Debugging
" ---------------------------------------------------------------------------

" One line of the position-mapping trace (g:hexpair_debug). Cheap when
" the trace is off, which is the case that matters: the check comes
" before the formatting.
function! s:Debug(fmt, ...) abort
  if !g:hexpair_debug
    return
  endif
  echomsg 'hexpair: ' . call('printf', [a:fmt] + a:000)
endfunction

" ---------------------------------------------------------------------------
" xxd resolution
" ---------------------------------------------------------------------------

" Resolve the xxd executable: PATH first, then the Vim runtime directory,
" where xxd.exe ships on Windows even when it is not on PATH.
" Returns '' if not found.
function! s:ResolveXxd() abort
  if executable('xxd')
    return 'xxd'
  endif
  for candidate in [$VIMRUNTIME . '/xxd', $VIMRUNTIME . '/xxd.exe']
    if executable(candidate)
      return shellescape(candidate)
    endif
  endfor
  return ''
endfunction

" ---------------------------------------------------------------------------
" Reverse conversion
" ---------------------------------------------------------------------------




" Would this buffer be written as zero bytes?  A binary buffer has two
" representations of that: the state a 0-byte file is read into, where
" line2byte() reports there is no line at all, and one empty line with
" 'eol' off.  A buffer holding a single 0a byte looks like neither -
" which is what makes the two cases distinguishable, since by content
" both are one empty line.
function! s:ZeroBytes() abort
  return line('$') == 1 && getline(1) ==# ''
        \ && (line2byte(1) < 0 || !&l:eol)
endfunction


" ---------------------------------------------------------------------------
" Cursor position mapping (byte offset <-> dump coordinates)
" ---------------------------------------------------------------------------

" 0-based byte offset of the byte under the cursor in a NORMAL (binary)
" buffer.  For a multibyte character this is the offset of its first byte,
" since col('.') points at the first byte of the character.
function! s:BufOffset() abort
  let off = line2byte(line('.')) + col('.') - 2
  return off < 0 ? 0 : off
endfunction



" Length in bytes of the byte order mark the buffer would be written with.
function! s:BomLen() abort
  if !&l:bomb
    return 0
  endif
  let fenc = &l:fileencoding !=# '' ? &l:fileencoding : &encoding
  if fenc =~? '^utf-8'
    return 3
  elseif fenc =~? 'ucs-4\|utf-32'
    return 4
  elseif fenc =~? 'ucs-2\|utf-16'
    return 2
  endif
  return 0
endfunction

" For a buffer loaded WITHOUT 'binary', file-byte offsets cannot be taken
" from the buffer directly: a BOM was stripped, fileformat=dos line endings
" were folded, and the content may have been transcoded from
" 'fileencoding'.  Instead of predicting the on-disk byte layout from the
" converted content (fragile for e.g. mixed CRLF/LF line endings), the
" mapping is done in two phases around the ++bin reload:
"   1. s:PreReloadPos() captures, from the CONVERTED view, the cursor line
"      and the number of FILE bytes its column corresponds to within that
"      line (1 char = 1 byte for single-byte fileencodings, internal bytes
"      for utf-8), plus the BOM length,
"   2. s:PostReloadOffset() then anchors the line start with line2byte()
"      over the RAW bytes - exact by construction, whatever the line
"      endings were - and adds the within-line part (BOM bytes shift
"      line 1).
" Line boundaries survive the reload 1:1 for any fileencoding in which
" 0x0a is the line separator; utf-16/ucs-2 files remain approximate.
function! s:PreReloadPos() abort
  let fenc = &l:fileencoding !=# '' ? &l:fileencoding : &encoding
  let singlebyte = fenc =~? '^\%(latin\|iso-8859\|cp[0-9]\|koi8\|8bit\)'
  let before = strpart(getline('.'), 0, col('.') - 1)
  return {
        \ 'lnum': line('.'),
        \ 'wcol': singlebyte ? strchars(before) : strlen(before),
        \ 'bom':  s:BomLen(),
        \ }
endfunction

function! s:PostReloadOffset(pos) abort
  let lnum = a:pos.lnum > line('$') ? line('$') : a:pos.lnum
  let off = line2byte(lnum) - 1 + a:pos.wcol + (lnum == 1 ? a:pos.bom : 0)
  call s:Debug('++bin reload: line %d, %d bytes into it, %d of BOM -> byte %d',
        \ lnum, a:pos.wcol, a:pos.bom, off)
  return off
endfunction



" ---------------------------------------------------------------------------
" Global 'paste' management
" ---------------------------------------------------------------------------

" 'paste' is a GLOBAL option - there is no buffer-local variant - so it
" cannot simply be set for the dump buffer.  Instead it is switched on
" whenever the cursor enters a hex-mode buffer and restored to its
" previous value whenever the cursor leaves it (and when hex mode is
" toggled off): insert-mode mappings and abbreviations then cannot
" mangle typed hex and no automatic formatting interferes, while every
" other buffer keeps the user's own 'paste' state.  Disable with
" g:hexpair_paste = 0.
function! s:PasteOn() abort
  if !g:hexpair_paste
    return
  endif
  if !get(b:, 'hexpair_page_active', 0)
    return
  endif
  if !exists('b:hexpair_paste_save')
    let b:hexpair_paste_save = &paste
  endif
  " Switching 'paste' on resets 'expandtab' as a side effect; preserve
  " the buffer's value (set by the bundled xxd ftplugin, or by the
  " user's override) so a <Tab> typed into the dump still expands to
  " spaces.  Switching 'paste' off later restores the same value, so
  " the two stay consistent.
  let expandtab = &l:expandtab
  set paste
  let &l:expandtab = expandtab
endfunction

function! s:PasteOff() abort
  if exists('b:hexpair_paste_save')
    let &paste = b:hexpair_paste_save
    unlet b:hexpair_paste_save
  endif
endfunction


" ---------------------------------------------------------------------------
" Page boundary arithmetic
" ---------------------------------------------------------------------------

" Pages are plain fixed-size slices of the file: page idx covers
" [idx * size, idx * size + size), the last one short. Nothing about
" the file's content or xxd's formatting perturbs that - see
" s:PagedLineLayout() for why the offset column widening past 4 GiB
" does not have to.
"
" Global (not script-local) and pure (no I/O, no buffer/window state):
" directly testable with a fabricated `total` far larger than any real
" test fixture, without needing an actual multi-GiB file.
"
" [base, len] (0-based byte offset, byte count) of page `idx` (0-based)
" for a file of `total` bytes with page size `size`. Returns [-1, -1]
" for an out-of-range index.
function! HexPairPagedBounds(idx, size, total) abort
  if a:idx < 0
    return [-1, -1]
  endif
  let base = a:idx * a:size
  if base >= a:total
    return [-1, -1]
  endif
  return [base, min([a:size, a:total - base])]
endfunction

" Total number of pages for a file of `total` bytes at page size
" `size` (0 for an empty file).
function! HexPairPagedTotalPages(size, total) abort
  return a:total <= 0 ? 0 : (a:total + a:size - 1) / a:size
endfunction

" Hex digit width xxd uses for offsets in the same width-segment as
" `base` (constant across a whole page by construction - see above).
function! s:HexDigitWidth(base) abort
  return max([8, strlen(printf('%x', a:base))])
endfunction

" 1-based column of the first hex digit on a dump line whose offset
" column holds `base`. The offset column is the hex digits, a ':' and a
" space - so the first digit sits one column past all three, which for
" the base plugin's fixed eight digits is its hardcoded 11.
function! s:HexStart(base) abort
  return s:HexDigitWidth(a:base) + 3
endfunction

" ---------------------------------------------------------------------------
" Page banner
" ---------------------------------------------------------------------------

" Any line whose FIRST character is '"' is a full-line comment,
" contributing zero bytes - never ambiguous with real xxd output (data
" lines always start with a hex digit) or with a bare inserted hex
" line (never starts with '"' either).
function! s:IsBannerLine(line) abort
  return a:line[0] ==# '"'
endfunction

" Byte positions in the banner are 1-based and inclusive (byte 1 is the
" file's first byte), unlike a:base/a:len themselves (0-based, like
" everything else in this file, matching the hex dump's own offset
" column - real xxd -s output, left alone): the LAST page's displayed
" end must equal the total for it to read as "covers through the end
" of the file", which only holds with 1-based-inclusive numbering
" (0-based-inclusive is off by one short of the total; only relevant
" here, this is purely a display convention for these two human-facing
" summaries, not the offsets xxd itself prints per line).
function! s:BannerTop(pageidx, totalpages, base, len, total, fname) abort
  return printf('" hexpair: page %d/%d  bytes %d-%d of %d  %s',
        \ a:pageidx + 1, a:totalpages, a:base + 1, a:base + a:len,
        \ a:total, a:fname)
endfunction

function! s:BannerBottom(pageidx, totalpages) abort
  return printf('" hexpair: end of page %d/%d', a:pageidx + 1, a:totalpages)
endfunction

" ---------------------------------------------------------------------------
" Layout helpers
" ---------------------------------------------------------------------------

" Analogous to plugin/hexpair.vim's s:Layout(), but hexstart is not the
" hardcoded 11: xxd widens its offset column past eight hex digits once
" an offset reaches 4 GiB (16^8), and again at 64 GiB, and so on -
" verified empirically, a single dump can show "fffffffc:" immediately
" followed by "100000000:". So the width is read off the LINE itself,
" from where its offset column ends, which
"   - needs no constraint whatsoever on where pages may start, so pages
"     stay plain fixed-size slices even across a widening (a page that
"     straddles one simply carries both widths, each line correct),
"   - and gets the bare hex lines a user may insert right too: a line
"     with no offset column at all starts its payload after its indent.
" The rule for where the offset column ends is the one the whole plugin
" shares (invariant 1): up to the first ':'.
" Returns [bytes_per_line, hexstart, hexend, asciistart].
function! s:PagedLineLayout(lnum) abort
  let line  = getline(a:lnum)
  let colon = stridx(line, ':')
  let hexstart = colon < 0 ? matchend(line, '^\s*') + 1 : colon + 3
  return s:PagedLayoutFor(hexstart)
endfunction

" The same layout for a line whose offset column holds `off`, for
" callers that know the offset but do not have the line (yet).
function! s:PagedOffsetLayout(off) abort
  return s:PagedLayoutFor(s:HexStart(a:off))
endfunction

function! s:PagedLayoutFor(hexstart) abort
  let n = b:hexpair_n
  let hexend     = a:hexstart + 3 * n - 2
  let asciistart = hexend + 3
  return [n, a:hexstart, hexend, asciistart]
endfunction

" ---------------------------------------------------------------------------
" Reverse conversion (stripping and validation only - Stage 1 has no
" write path yet; kept in sync now so a later stage's :w reuses this
" unchanged)
" ---------------------------------------------------------------------------

" THE payload rule of the paged mode, in ONE function: a banner line
" contributes nothing at all; any other line loses its offset column
" (everything up to the first ':', or just its indent if it has none, so
" a bare hex line the user inserted still works) and its ASCII column
" (everything from the first run of two spaces). Banner-aware
" counterpart of plugin/hexpair.vim's s:StripDumpLine(), extending
" invariant 1 - the stripper, the validator and the cursor mapping all
" go through here, so the three cannot drift apart.
"
" Anchored matchend() plus a plain stridx() rather than a substitute()
" with a pattern that has to be tried at every column: this runs once
" per line of a page, and a page is thousands of lines.
function! s:PagedPayload(line) abort
  if s:IsBannerLine(a:line)
    return ''
  endif
  let start = matchend(a:line, '^\s*[^:]*:')
  if start < 0
    let start = matchend(a:line, '^\s*')
  endif
  let ascii = stridx(a:line, '  ', start)
  return ascii < 0 ? strpart(a:line, start)
        \          : strpart(a:line, start, ascii - start)
endfunction

function! s:PagedStripDumpLine(line) abort
  return substitute(s:PagedPayload(a:line), '[^0-9a-fA-F ]', '', 'g')
endfunction

" Describe the offending character on one line, for the error message
" and for parking the cursor on it. Only called for a line s:PagedScan()
" already rejected, so the match is guaranteed to be found.
function! s:PagedBadChar(lnum) abort
  let line  = getline(a:lnum)
  let start = matchend(line, '^\s*')
  let colon = stridx(line, ':')
  if colon >= 0
    let start = colon + 1
  endif
  let bad = match(line, '[^0-9a-fA-F ]', start)
  return {'lnum': a:lnum, 'col': bad + 1,
        \ 'msg': printf('invalid character %s in the hex area (line %d, column %d)',
        \               string(matchstr(line, '.', bad)), a:lnum, bad + 1)}
endfunction

function! s:PagedPayloadText(text) abort
  " Anchoring to a line start: the newline is part of the match and is put
  " back by the replacement (\1), rather than the \zs the per-line rule's
  " ^ would suggest. Two reasons, both found the hard way: \zs still
  " CONSUMES the newline it matched, so a line whose strip comes out empty
  " - a banner line, an empty line - leaves the scan positioned inside the
  " next line, whose own offset column then survives into the payload; and
  " a lookbehind, which consumes nothing, is quadratic enough here to take
  " ten seconds on one page. The first line has no newline before it, so
  " it gets the same rule ^-anchored once.
  "
  " A banner line contributes nothing at all - and it has to go FIRST,
  " because its own text contains a ':' and would otherwise be mistaken
  " for an offset column, leaving "page 1/1" behind as hex payload.
  let t = substitute(a:text, '^"[^\n]*', '', '')
  let t = substitute(t, '\(\n\)"[^\n]*', '\1', 'g')
  " The offset column: the indent plus everything up to the first ':', or
  " just the indent on a line that has none (a bare hex line the user
  " inserted). One optional group covers both, and neither half may cross
  " a newline into the next line.
  let t = substitute(t, '^\s*\%([^:\n]*:\)\=', '', '')
  let t = substitute(t, '\(\n\)\s*\%([^:\n]*:\)\=', '\1', 'g')
  " The ASCII column: from the first run of two spaces to the end of the
  " line. The offset column is already gone, so - exactly as the per-line
  " rule does by searching from where it ended - a double space inside it
  " can no longer be mistaken for the start of the ASCII column.
  return substitute(t, '  [^\n]*', '', 'g')
endfunction

" The payload of a whole page as ONE flat run: the line breaks holding it
" together are taken out, so what is left is exactly the hex digits and
" the spaces between them - and every test on it is then a plain
" collection, with no end-of-line semantics to get wrong.
"
" The break is removed by the \n ATOM. It must never be put inside a
" collection instead: "[^0-9a-fA-F \n]" looks like it says "not a hex
" digit, not a space, not a line break" and does not keep saying it - a
" negated collection matches the end-of-line whatever is listed in it
" (|/[\n]|), which shows up as the same page validating fine at 2000
" lines and being rejected at 4000 (measured on Vim 9.2 - and the reason
" the whole-page scan is tested against a full-size page, not a handful
" of lines).
function! s:PagedFlatten(text) abort
  return substitute(a:text, '\n', '', 'g')
endfunction

" Hex digits in a flattened payload, which holds nothing else but spaces.
function! s:PagedDigits(flat) abort
  return strlen(substitute(a:flat, ' ', '', 'g'))
endfunction

" Which line the offender is on, for the error message and the cursor.
" Walks the page line by line through the per-line rule - the slow way,
" but only ever on a page that has already been found invalid.
function! s:PagedFirstBadLine(lines) abort
  let i = 0
  while i < len(a:lines)
    if s:PagedPayload(a:lines[i]) =~# '[^0-9a-fA-F ]'
      return s:PagedBadChar(i + 1)
    endif
    let i += 1
  endwhile
  " Unreachable: something in the page failed the whole-page check.
  return {'msg': 'invalid character in the hex area'}
endfunction

function! s:PagedScan(lnum) abort
  let lines = getline(1, '$')
  " The whole page as ONE string, stripped by ONE regex per rule. The
  " same work per line costs about four times as much: VimScript's
  " per-iteration overhead dwarfs the matching itself, and a page is
  " thousands of lines.
  let text = s:PagedPayloadText(join(lines, "\n"))
  let flat = s:PagedFlatten(text)
  if match(flat, '[^0-9a-fA-F ]') >= 0
    return {'err': s:PagedFirstBadLine(lines)}
  endif
  if s:PagedDigits(flat) % 2
    return {'err': {'msg': 'odd number of hex digits - the last nibble would be dropped'}}
  endif
  " Bytes before a:lnum. Digits pair across line ends, exactly as
  " `xxd -r -p` pairs them when the page is written back, so the digits
  " of the preceding lines are counted as one run rather than each line
  " being rounded down on its own.
  let bytes = a:lnum > 1
        \ ? s:PagedDigits(s:PagedFlatten(
        \     s:PagedPayloadText(join(lines[0 : a:lnum - 2], "\n")))) / 2
        \ : 0
  return {'err': {}, 'lines': split(text, "\n", 1), 'bytes': bytes}
endfunction

" Scan without wanting anything but the verdict.
function! s:PagedValidateDump() abort
  return s:PagedScan(0).err
endfunction

" Thin global wrappers so test/run-tests.sh can exercise the banner-
" aware stripping/validation on their own, independently of the write
" path that now also drives them.
function! HexPairPagedStripLine(line) abort
  return s:PagedStripDumpLine(a:line)
endfunction

function! HexPairPagedValidate() abort
  return s:PagedValidateDump()
endfunction

" And the payload the whole-page scan produces, line by line, so the suite
" can hold it against the per-line rule the two must agree on (invariant
" 1). Worth a hook of its own: the two can only drift apart on a page big
" enough that a regex over the whole of it behaves differently from the
" same regex over one line, which is not a scale a unit test reaches by
" accident.
function! HexPairPagedScanLines() abort
  return s:PagedScan(0).lines
endfunction

" Test hooks: the layout of one line, and the absolute file offset the
" cursor is on. Both are what the paged mode's correctness across a
" 4 GiB offset-width change comes down to, and neither is otherwise
" observable from outside this script scope.
function! HexPairPagedReport() abort
  return s:PagesText()
endfunction

function! HexPairPagedLineHexStart(lnum) abort
  return s:PagedLineLayout(a:lnum)[1]
endfunction

" Move the cursor to the HEX column, the ASCII column or the opposite
" one, staying on the same byte - :HexPairGoHex and friends hand a paged
" buffer over here, because the layout of a paged line is its business.
function! s:PagedJumpTo(target) abort
  if !s:RequirePaged()
    return
  endif
  let lnum = line('.')
  if s:IsBannerLine(getline(lnum))
    return
  endif

  " Remembered for s:Reread(): :e moves the cursor away before BufReadCmd
  " runs, so the position has to have been noted while the user was still
  " on it. Recorded only for a real dump line, which is also what keeps
  " that very move - onto the top banner - from overwriting it first.
  let b:hexpair_last_pos = [lnum, col('.')]
  let [n, hexstart, hexend, asciistart] = s:PagedLineLayout(lnum)
  let idx = s:PagedCursorByte()
  let in_hex = col('.') <= hexend
  let target = a:target ==# 'swap' ? (in_hex ? 'ascii' : 'hex') : a:target
  if target ==# 'hex'
    call cursor(lnum, hexstart + idx * 3)
  else
    call cursor(lnum, asciistart + idx)
  endif
  call s:PagedHighlight()
endfunction


function! HexPairPagedByteOffset() abort
  return s:PagedByteOffset()
endfunction

" ---------------------------------------------------------------------------
" Pair highlighting (duplicated from plugin/hexpair.vim's
" s:Highlight()/s:ClearHighlight(): same visual behaviour, but keyed
" off b:hexpair_page_active and s:PagedLineLayout(), and skips the banner
" lines, which the base plugin's dump never has)
" ---------------------------------------------------------------------------

function! s:PagedClearHighlight() abort
  if exists('w:hexpair_page_ids')
    for id in w:hexpair_page_ids
      silent! call matchdelete(id)
    endfor
  endif
  let w:hexpair_page_ids = []
endfunction

" How many dump lines of a Visual selection get their counterpart
" highlighted. Only what is on screen can be looked at anyway, so the
" window is the natural bound - and it keeps the work per cursor movement
" constant however much of a page is selected.
function! s:MirrorLimit() abort
  return winheight(0) + 1
endfunction

" Byte index on a line for a screen column, and which column that is.
function! s:ByteAt(lnum, col) abort
  let [n, hexstart, hexend, asciistart] = s:PagedLineLayout(a:lnum)
  if a:col >= asciistart
    return a:col - asciistart
  endif
  return a:col < hexstart ? 0 : (a:col - hexstart) / 3
endfunction

function! s:InHexColumn(lnum, col) abort
  let [n, hexstart, hexend, asciistart] = s:PagedLineLayout(a:lnum)
  return a:col <= hexend
endfunction

" Where the counterpart of a Visual selection is: a list of
" [lnum, col, len] for matchaddpos(), covering the SAME bytes in the other
" column. Vim already highlights what is selected; this is what it is on
" the other side of the dump, so a run of hex digits shows which text it
" is and a run of text shows which bytes it is.
"
" a:vpos / a:cpos are getpos() results for the selection ends, a:mode the
" mode() string. Split from the drawing so it can be tested directly:
" Visual mode cannot be driven under this project's `vim -es` harness, in
" the same way input() and confirm() cannot.
function! HexPairPagedSelectionPositions(vpos, cpos, mode, first, last) abort
  " Ordered by line AND column: a selection that begins and ends on one
  " line would otherwise come out backwards whenever it was made
  " leftwards, and be skipped as empty.
  let forward = a:vpos[1] < a:cpos[1]
        \ || (a:vpos[1] == a:cpos[1] && a:vpos[2] <= a:cpos[2])
  let [head, tail] = forward ? [a:vpos, a:cpos] : [a:cpos, a:vpos]
  let inhex = s:InHexColumn(a:cpos[1], a:cpos[2])
  let positions = []

  for lnum in range(a:first, a:last)
    if s:IsBannerLine(getline(lnum))
      continue
    endif
    let [n, hexstart, hexend, asciistart] = s:PagedLineLayout(lnum)
    let bytes = strlen(getline(lnum)) - asciistart + 1
    if bytes <= 0
      continue
    endif
    let bytes = min([bytes, n])

    if a:mode ==# "\<C-V>"
      " Blockwise: the same column range on every line of it.
      let lo = s:ByteAt(lnum, min([head[2], tail[2]]))
      let hi = s:ByteAt(lnum, max([head[2], tail[2]]))
    elseif a:mode ==# 'V'
      let [lo, hi] = [0, bytes - 1]
    else
      let lo = lnum == head[1] ? s:ByteAt(lnum, head[2]) : 0
      let hi = lnum == tail[1] ? s:ByteAt(lnum, tail[2]) : bytes - 1
    endif
    let lo = max([lo, 0])
    let hi = min([hi, bytes - 1])
    if hi < lo
      continue
    endif

    call add(positions, inhex
          \ ? [lnum, asciistart + lo, hi - lo + 1]
          \ : [lnum, hexstart + lo * 3, (hi - lo + 1) * 3 - 1])
  endfor
  return positions
endfunction

function! s:HighlightSelection() abort
  let vpos = getpos('v')
  let cpos = getpos('.')
  let first = max([min([vpos[1], cpos[1]]), line('w0')])
  let last = min([max([vpos[1], cpos[1]]), line('w$'), first + s:MirrorLimit()])
  let positions =
        \ HexPairPagedSelectionPositions(vpos, cpos, mode(), first, last)
  " matchaddpos() takes eight positions at a time.
  for i in range(0, len(positions) - 1, 8)
    call add(w:hexpair_page_ids,
          \ matchaddpos('HexPairMirror', positions[i : i + 7]))
  endfor
endfunction

function! s:PagedHighlight() abort
  call s:PagedClearHighlight()
  if !get(b:, 'hexpair_page_active', 0) || !s:IsHexView()
    return
  endif

  let lnum = line('.')
  if s:IsBannerLine(getline(lnum))
    return
  endif

  " In Visual mode the whole selection has a counterpart, not just the
  " byte under the cursor.
  if mode() =~# "^[vV\<C-V>]$"
    call s:HighlightSelection()
    return
  endif

  " Remembered for s:Reread(): :e moves the cursor away before BufReadCmd
  " runs, so the position has to have been noted while the user was still
  " on it. Recorded only for a real dump line, which is also what keeps
  " that very move - onto the top banner - from overwriting it first.
  let b:hexpair_last_pos = [lnum, col('.')]

  let [n, hexstart, hexend, asciistart] = s:PagedLineLayout(lnum)
  let col     = col('.')
  let linelen = strlen(getline('.'))

  let idx    = -1
  let in_hex = 0
  if col >= hexstart && col <= hexend
    let idx    = (col - hexstart) / 3
    let in_hex = 1
  elseif col >= asciistart && col < asciistart + n
    let idx = col - asciistart
  endif
  if idx < 0
    return
  endif

  if asciistart + idx > linelen
    return
  endif

  let hexgrp   = in_hex ? 'HexPairActive' : 'HexPairMirror'
  let asciigrp = in_hex ? 'HexPairMirror' : 'HexPairActive'
  call add(w:hexpair_page_ids,
        \ matchaddpos(hexgrp,   [[lnum, hexstart + idx * 3, 2]]))
  call add(w:hexpair_page_ids,
        \ matchaddpos(asciigrp, [[lnum, asciistart + idx, 1]]))
endfunction

" ---------------------------------------------------------------------------
" Opening and navigating pages
" ---------------------------------------------------------------------------

" Bounds for page `idx` (0-based) of a `size`-byte file at `pagesize`
" bytes/page, reporting the standard "page N does not exist" error via
" echomsg if out of range (a non-numeric page number, e.g. from
" str2nr() on bad :HexPairOpen input, ends up negative here too -
" HexPairPagedBounds() reports that the same way, base < 0). Returns
" [base, len, total, totalpages]; callers must check base before using
" the rest.
" Deliberately callable BEFORE any buffer exists (pure arithmetic plus
" one getfsize() - no buffer/window state), so s:Open() can validate
" the requested page and bail out with nothing created at all on a bad
" one, rather than leaving a renamed, half-initialized scratch buffer
" behind for the caller to clean up.
" What the banner and :HexPairPages call this buffer's content. A spilled
" unnamed buffer has no file name worth showing - its temp is an
" implementation detail - so it says so instead.
function! s:PageLabel() abort
  return get(b:, 'hexpair_page_spill', '') !=# ''
        \ ? '[unnamed buffer]' : b:hexpair_page_file
endfunction

function! s:ResolvePage(file, pagesize, idx) abort
  let total = getfsize(a:file)
  let totalpages = HexPairPagedTotalPages(a:pagesize, total)
  let [base, len] = HexPairPagedBounds(a:idx, a:pagesize, total)
  if base < 0
    echohl ErrorMsg
    echomsg printf('hexpair: page %d does not exist (file has %d page%s)',
          \ a:idx + 1, totalpages, totalpages == 1 ? '' : 's')
    echohl None
  endif
  return [base, len, total, totalpages]
endfunction

" Populates the CURRENT (already-created, empty) buffer with page
" `pageidx` (0-based) of `b:hexpair_page_file` and refreshes all
" buffer-local page state. Does not create or rename the buffer -
" callers do that first (s:Open() for the initial page, s:GotoPage()
" when navigating) - and, unlike s:Open(), an invalid `pageidx` here
" leaves an EXISTING, already-loaded buffer showing its previous page
" untouched, which is the correct behaviour for :HexPairPageNext and
" friends running past either end.
function! s:LoadPage(pageidx) abort
  " No bytes means no pages - but the file is still perfectly openable,
  " and saying so is more use than refusing to show it.
  if getfsize(b:hexpair_page_file) <= 0
    call s:LoadEmpty()
    return 1
  endif
  let [base, len, total, totalpages] =
        \ s:ResolvePage(b:hexpair_page_file, b:hexpair_page_size, a:pageidx)
  if base < 0
    return 0
  endif

  let b:hexpair_page_index      = a:pageidx
  let b:hexpair_page_base       = base
  let b:hexpair_page_len        = len
  let b:hexpair_page_total      = total
  let b:hexpair_page_totalpages = totalpages
  let b:hexpair_page_ftime      = getftime(b:hexpair_page_file)
  let b:hexpair_n               = g:hexpair_bytes_per_line
  " Where the page's FIRST line starts its hex column; later lines
  " derive their own (s:PagedLineLayout()), which differs only on a
  " page that straddles an offset-width change.
  let b:hexpair_page_hexstart   = s:HexStart(base)

  " Replacing the page must not be an undoable edit: undo history that
  " survived a page turn would let a single |u| put the bytes of a
  " DIFFERENT part of the file into a buffer that now claims to be this
  " page - and a :w would then patch them in at this page's offset.
  " |clear-undo|: making the change with 'undolevels' at -1 discards the
  " history; restoring the option afterwards resumes normal undo, so
  " edits made to the page itself stay undoable. Buffer-local, not
  " global: 'undolevels' is global-local, and a buffer-local value would
  " otherwise keep winning over the global one and the history survive.
  let save_ul = &l:undolevels
  setlocal noreadonly modifiable
  try
    setlocal undolevels=-1
    silent %delete _
    silent execute '%!' . s:xxd . printf(' -s %d -l %d -g 1 -c %d %s',
          \ base, len, b:hexpair_n, shellescape(b:hexpair_page_file))
    let b:hexpair_banner_top = s:BannerTop(a:pageidx, totalpages, base,
          \ len, total, s:PageLabel())
    let b:hexpair_banner_bottom = s:BannerBottom(a:pageidx, totalpages)
    call append(0, b:hexpair_banner_top)
    call append(line('$'), b:hexpair_banner_bottom)
  finally
    let &l:undolevels = save_ul
  endtry

  " xxd runs through the shell, which can fail for reasons Vim never
  " reports - leaving an empty or short buffer presented as the page,
  " and a later :w patching that into the file. The dump's shape is
  " known exactly, so check it: one line per bytesperline bytes, plus
  " the two banner lines.
  let expect = (len + b:hexpair_n - 1) / b:hexpair_n + 2
  if line('$') != expect
    throw printf('hexpair: reading page %d of %s produced %d lines, '
          \ . 'expected %d - is xxd working?',
          \ a:pageidx + 1, b:hexpair_page_file, line('$'), expect)
  endif

  call cursor(2, b:hexpair_page_hexstart)
  call s:Debug('page %d/%d loaded: bytes [%d, %d) of %d, %d lines',
        \ a:pageidx + 1, totalpages, base, base + len, total, line('$'))

  setlocal filetype=xxd
  call s:ApplyBannerSyntax()
  setlocal nomodified
  let b:hexpair_page_active = 1
  let b:hexpair_view = 'hex'
  call s:PasteOn()
  call s:PagedHighlight()
  redraw!
  return 1
endfunction

function! s:ApplyBannerSyntax() abort
  if !has('syntax') || !exists('g:syntax_on')
    return
  endif
  syntax match HexPairPageBanner '^".*$'
endfunction

function! s:Open(file, ...) abort
  let page = a:0 > 0 ? str2nr(a:1) : 1
  let s:xxd = s:ResolveXxd()
  if s:xxd ==# ''
    echohl ErrorMsg
    echomsg 'hexpair: xxd not found in PATH nor in $VIMRUNTIME'
    echohl None
    return
  endif
  if !filereadable(a:file)
    echohl ErrorMsg
    echomsg 'hexpair: cannot read ' . a:file
    echohl None
    return
  endif
  let sizeerr = HexPairPagedSizeError(g:hexpair_page_size, g:hexpair_bytes_per_line)
  if !empty(sizeerr)
    echohl ErrorMsg | echomsg sizeerr | echohl None
    return
  endif

  " Validate the requested page BEFORE creating or renaming any
  " buffer: s:LoadPage() also does this, but only after enew/:file
  " below already happened, which would otherwise leave behind an
  " empty scratch buffer named "<file> [hexpair page]" - inactive
  " (b:hexpair_page_active never gets set) but real-looking enough
  " that a later :w would be attempted against that made-up path -
  " which the write path would then patch bytes into.
  let file = fnamemodify(a:file, ':p')
  if s:ResolvePage(file, g:hexpair_page_size, page - 1)[0] < 0
    return
  endif

  enew
  silent execute 'file ' . fnameescape(a:file . ' [hexpair page]')
  let b:hexpair_page_file = file
  let b:hexpair_page_spill = ''
  call s:SetupPagedBuffer()

  call s:LoadPage(page - 1)
endfunction

" ---------------------------------------------------------------------------
" Cursor position <-> absolute file offset
" ---------------------------------------------------------------------------

" Byte index of the cursor within its own dump line: the number of
" complete hex pairs actually present before it, which stays correct on
" edited lines (bare inserted lines, extra bytes typed into a line) where
" layout coordinates would be wrong. Only when the cursor sits in the
" ASCII column - detected by a double space before it, the same rule the
" stripper uses - is the index mapped by layout.
function! s:PagedCursorByte() abort
  let [n, hexstart, hexend, asciistart] = s:PagedLineLayout(line('.'))
  let col = col('.')
  if col <= hexend
    let idx = col < hexstart ? 0 : (col - hexstart) / 3
  else
    let idx = col < asciistart ? 0 : col - asciistart
    if idx >= n
      let idx = n - 1
    endif
  endif
  " Clamp to the bytes actually present on this (possibly short) line.
  let nbytes = strlen(getline('.')) - asciistart + 1
  if nbytes > n
    let nbytes = n
  endif
  if nbytes > 0 && idx >= nbytes
    let idx = nbytes - 1
  endif
  return idx
endfunction

" ABSOLUTE file offset of the byte under the cursor. Banner-aware
" counterpart of plugin/hexpair.vim's s:DumpOffset(): bytes on preceding
" lines are counted from their actual stripped content (banner lines
" contribute none), so the result stays exact even after lines were
" inserted, deleted or reordered within the page.
" Byte index of the cursor WITHIN its own dump line: the number of
" complete hex pairs actually present before it, which stays correct on
" edited lines (bare inserted lines, extra bytes typed into a line)
" where layout coordinates would be wrong. Only when the cursor sits in
" the ASCII column - detected by a double space before it, the same rule
" the stripper uses - is the index mapped by layout.
function! s:PagedCursorLineIndex() abort
  let prefix = strpart(getline('.'), 0, col('.') - 1)
  if prefix =~# '  '
    return s:PagedCursorByte()
  endif
  let payload = s:PagedPayload(prefix)
  return strlen(substitute(payload, '[^0-9a-fA-F]', '', 'g')) / 2
endfunction

function! s:PagedByteOffset() abort
  if s:IsBannerLine(getline('.'))
    return b:hexpair_page_base
  endif
  " On a page nobody has edited, what is above the cursor's line needs no
  " counting: the page is exactly what xxd produced, so dump line k holds
  " bytes k * n .. and the walk can be skipped entirely. That is what
  " keeps a write and |:HexPairPages| off a second pass over the page -
  " the cursor byte is reported after every write, and on the default
  " page size counting it costs as much as the write itself.
  "
  " The WITHIN-line part goes through the same s:PagedCursorLineIndex()
  " either way, so the two paths cannot drift apart in how they read a
  " line - only in how they count the lines above it, which is arithmetic
  " exactly while the page is canonical.
  if !&l:modified
    let off = b:hexpair_page_base
          \ + (line('.') - 2) * b:hexpair_n + s:PagedCursorLineIndex()
    call s:Debug('hex view line %d, column %d -> byte %d '
          \ . '(page base %d, unedited page)',
          \ line('.'), col('.'), off, b:hexpair_page_base)
    return off
  endif
  let scan = s:PagedScan(line('.'))
  let off = b:hexpair_page_base + scan.bytes + s:PagedCursorLineIndex()
  call s:Debug('hex view line %d, column %d -> byte %d (page base %d, '
        \ . '%d bytes above the line)',
        \ line('.'), col('.'), off, b:hexpair_page_base, scan.bytes)
  return off
endfunction

" Put the cursor on the given ABSOLUTE file offset, clamped to the page.
" Dump line k is buffer line k + 1: line 1 is the top banner.
function! s:PagedGotoOffset(abs) abort
  " A page with no bytes has no dump line to land on - only the banner.
  if b:hexpair_page_len <= 0
    call cursor(1, 1)
    return
  endif
  let rel = a:abs - b:hexpair_page_base
  if rel < 0
    let rel = 0
  elseif rel >= b:hexpair_page_len
    let rel = b:hexpair_page_len > 0 ? b:hexpair_page_len - 1 : 0
  endif
  " The target line's own offset decides its column layout, which is not
  " the page's first line's when the page straddles a widening.
  let n = b:hexpair_n
  let [n, hexstart, hexend, asciistart] =
        \ s:PagedOffsetLayout(b:hexpair_page_base + rel / n * n)
  call cursor(rel / n + 2, hexstart + (rel % n) * 3)
  call s:Debug('byte %d -> hex view line %d, column %d',
        \ a:abs, line('.'), col('.'))
endfunction

" ---------------------------------------------------------------------------
" Writing a page
" ---------------------------------------------------------------------------

function! s:Run(cmd) abort
  let out = system(a:cmd)
  if v:shell_error
    throw printf('hexpair: command failed (exit %d): %s: %s',
          \ v:shell_error, a:cmd, substitute(out, '\n', ' ', 'g'))
  endif
  return out
endfunction

" Does the local xxd understand -o (add an offset to the displayed file
" position)? Probed once per session: the in-place patch needs absolute
" offsets in the dump it feeds back to xxd -r, and an xxd without -o has
" to have them prepended by hand.
function! s:HasOffsetOption() abort
  if exists('s:has_o')
    return s:has_o
  endif
  let s:has_o = 0
  let probe = tempname()
  let out   = tempname()
  try
    " One byte, written without a Blob literal: Blobs are Vim 8.1.0735,
    " and everything this probe serves - the same-length patch write -
    " otherwise runs on the 8.0 baseline the rest of the plugin does.
    call writefile(['A'], probe, 'b')
    call s:Run(printf('%s -g 1 -c 16 -o 16 %s %s',
          \ s:xxd, shellescape(probe), shellescape(out)))
    let lines = readfile(out)
    let s:has_o = !empty(lines) && lines[0] =~# '^00000010: 41'
  catch
    let s:has_o = 0
  finally
    call delete(probe)
    call delete(out)
  endtry
  return s:has_o
endfunction

" Canonical 'xxd -g 1 -c n' dump of a:src whose offset column starts at
" the absolute file offset a:base, written to a:out. Generated fresh from
" the raw bytes rather than reusing the user's dump on purpose: the
" offsets in the buffer may be stale or reordered, and it is these
" offsets that xxd -r seeks by.
function! s:CanonicalDump(src, base, out) abort
  if s:HasOffsetOption()
    call s:Run(printf('%s -g 1 -c %d -o %d %s %s', s:xxd,
          \ b:hexpair_n, a:base, shellescape(a:src), shellescape(a:out)))
    return
  endif
  " Fallback for an xxd without -o: dump from zero and rewrite the offset
  " column, one printf per line. %x widens past eight digits exactly as
  " xxd does, so the fallback produces the same text xxd -o would.
  call s:Run(printf('%s -g 1 -c %d %s %s', s:xxd,
        \ b:hexpair_n, shellescape(a:src), shellescape(a:out)))
  let lines = readfile(a:out)
  let i = 0
  while i < len(lines)
    let colon = stridx(lines[i], ':')
    let lines[i] = printf('%08x', a:base + i * b:hexpair_n)
          \ . strpart(lines[i], colon)
    let i += 1
  endwhile
  call writefile(lines, a:out)
endfunction

" Refuse to touch a file that changed underneath us. Size and mtime are
" all a portable Vim can see; mtime has a one-second resolution, so a
" change made within the same second as the read AND of exactly the same
" size can slip through - documented in :help hexpair-paged.
function! s:CheckFresh() abort
  let total = getfsize(b:hexpair_page_file)
  if total == b:hexpair_page_total
        \ && getftime(b:hexpair_page_file) == b:hexpair_page_ftime
    return
  endif
  throw printf('hexpair: %s changed on disk since the page was read '
        \ . '(size %d -> %d); nothing was written - reload it with '
        \ . ':HexPairPageGoto! %d',
        \ b:hexpair_page_file, b:hexpair_page_total, total,
        \ b:hexpair_page_index + 1)
endfunction

" Same length: patch the page in place. xxd -r with the target file as an
" ARGUMENT opens it read-write and overwrites exactly the dumped range -
" shell redirection ('>') would truncate the file instead, so it must
" never be used here. Everything outside the page keeps its bytes and the
" file keeps its length; cost is O(page), not O(file).
function! s:PatchInPlace(raw) abort
  let dump = tempname()
  try
    call s:CanonicalDump(a:raw, b:hexpair_page_base, dump)
    call s:Run(printf('%s -r %s %s', s:xxd,
          \ shellescape(dump), shellescape(b:hexpair_page_file)))
  finally
    call delete(dump)
  endtry
endfunction

" Do two path strings name the same file? They cannot simply be compared:
" they reach here from different places - <amatch> is the full path Vim
" stored for the buffer, bufname() gives the short one - and on Windows two
" spellings of one path differ in their separators and in the case of the
" drive letter without naming anything different.
"
" Global, pure, and parameterized by the two things that differ between
" platforms rather than reading them itself, so both branches are testable
" wherever the suite happens to run. a:fnamecase is has('fname_case'), true
" where case distinguishes file names; a:backslash says whether a backslash
" is a path separator rather than an ordinary character in a name, which it
" is on Windows and is not on Unix.
function! HexPairPagedSamePath(a, b, fnamecase, backslash) abort
  if a:a ==# a:b
    return 1
  endif
  if a:a ==# '' || a:b ==# ''
    return 0
  endif
  let [a, b] = [a:a, a:b]
  if a:backslash
    let a = substitute(a, '\\', '/', 'g')
    let b = substitute(b, '\\', '/', 'g')
  endif
  return a:fnamecase ? a ==# b : a ==? b
endfunction

function! s:SamePath(a, b) abort
  if a:a ==# '' || a:b ==# ''
    return 0
  endif
  " simplify() takes './' and resolvable '..' out of the way; ':p' makes
  " both absolute. '+shellslash' exists only where a backslash is a path
  " separator rather than an ordinary character in a name.
  return HexPairPagedSamePath(simplify(fnamemodify(a:a, ':p')),
        \ simplify(fnamemodify(a:b, ':p')),
        \ has('fname_case'), exists('+shellslash'))
endfunction

" ':w {other}' fires BufWriteCmd like any write, and means something
" different from a plain ':w': not "patch this page into its own file" but
" "save what I am looking at, as a whole, over there". Returns the target
" for that, or '' for a plain write of the page - which is also what
" naming this view's own file, spelled out longhand, means.
function! s:WriteTarget() abort
  let target = expand('<amatch>')
  if target ==# ''
        \ || s:SamePath(target, get(b:, 'hexpair_page_bufname', ''))
        \ || s:SamePath(target, b:hexpair_page_file)
    return ''
  endif
  return target
endfunction

" Append a byte range of a:src to a:dst in bounded blocks, so memory use
" does not follow the size of the file. a:truncate starts a:dst from
" scratch, which is also how a shrinking file gets its new length: Vim
" cannot truncate a file except by writing it.
function! s:CopyRange(src, off, len, dst, truncate) abort
  if a:truncate && a:len == 0
    call writefile([], a:dst, 'b')
    return
  endif
  let done = 0
  while done < a:len
    let chunk = a:len - done
    if chunk > s:blocksize
      let chunk = s:blocksize
    endif
    let blob = readblob(a:src, a:off + done, chunk)
    if empty(blob)
      throw printf('hexpair: short read from %s at offset %d',
            \ a:src, a:off + done)
    endif
    call writefile(blob, a:dst, (a:truncate && done == 0) ? 'b' : 'ab')
    let done += len(blob)
  endwhile
endfunction

" Global and pure, like the gate and page-size messages: the interactive
" confirm() around it cannot run under this project's headless harness,
" so the text it asks is testable on its own. a:moved is how many of the
" file's bytes have to be written - the tail alone when the file can grow
" in place, all of them when it has to be rewritten.
function! HexPairPagedResizeMessage(delta, total, moved) abort
  let head = printf("hexpair: this page changed length by %+d bytes.\n", a:delta)
  if a:moved >= a:total
    return head . printf('Shortening a file means writing it afresh, so all '
          \ . "%d of its bytes are rewritten (%d -> %d bytes).\nContinue?",
          \ a:total, a:total, a:total + a:delta)
  endif
  return head . printf('Everything after this page has to move, so %d of '
        \ . "the file's %d bytes are rewritten in place - the rest is not "
        \ . "touched, and no second copy of it is made (%d -> %d bytes)."
        \ . "\nContinue?", a:moved, a:total, a:total, a:total + a:delta)
endfunction

function! s:ConfirmResize(newlen) abort
  if !g:hexpair_page_confirm
    return 1
  endif
  let inplace = a:newlen > b:hexpair_page_len && s:TailShiftIsCheaper()
  let msg = HexPairPagedResizeMessage(a:newlen - b:hexpair_page_len,
        \ b:hexpair_page_total, inplace ? s:TailSize() : b:hexpair_page_total)
  return confirm(msg, "&Write it\n&Cancel", 2, 'Question') == 1
endfunction

" ---------------------------------------------------------------------------
" Inserting bytes without rewriting the file
" ---------------------------------------------------------------------------
"
" Bytes cannot be spliced into the middle of a file - but they do not have
" to be, to insert some. Everything AFTER the insertion point has to move;
" everything before it does not, and need not even be read. So a page that
" grew is written by moving the tail right, in place, and then patching the
" page's new bytes in.
"
" Two xxd invocations are all that takes, so this path needs nothing newer
" than the Vim the rest of the plugin does:
"   xxd -s O -l L -p FILE HEX     read a byte range out as plain hex
"   xxd -r -p -s O HEX FILE       write it back at any offset, in place,
"                                 extending the file if that is past its end
" Both verified, including that a multi-line plain dump lands contiguously
" and that neither ever truncates the target.
"
" Shortening a file cannot be done this way. Moving the tail left is the
" same operation, but the file is then still its old length with stale
" bytes at the end, and nothing in Vim or xxd can shorten a file except
" writing it afresh - which is what s:Splice() does.

" Move [a:from, a:from + a:len) of the paged file to a:to, in place.
function! s:MoveRange(from, len, to, hex) abort
  call s:Run(printf('%s -s %d -l %d -p %s %s', s:xxd, a:from, a:len,
        \ shellescape(b:hexpair_page_file), shellescape(a:hex)))
  call s:Run(printf('%s -r -p -s %d %s %s', s:xxd, a:to,
        \ shellescape(a:hex), shellescape(b:hexpair_page_file)))
endfunction

" Is moving the tail cheaper than rewriting the whole file? Moving it costs
" about eight times its size in reads and writes - out as hex, back as
" bytes, plus the copy kept for recovery - while rewriting the file costs
" about four times its own. So the shift wins while the tail is under half
" the file, which is also exactly when the recovery copy is the smaller of
" the two.
function! s:TailShiftIsCheaper() abort
  let tailsize = b:hexpair_page_total - b:hexpair_page_base
        \ - b:hexpair_page_len
  return tailsize * 2 <= b:hexpair_page_total
endfunction

function! s:TailSize() abort
  return b:hexpair_page_total - b:hexpair_page_base - b:hexpair_page_len
endfunction

" Make room at the end before anything is moved into it: the file is
" extended by exactly the number of bytes being inserted. Doing that first
" means a full disk - the likely failure when a file is growing - fails
" here, before a byte of the tail has been touched.
function! s:ExtendBy(delta) abort
  let hex = tempname()
  try
    call writefile([repeat('00', a:delta)], hex)
    call s:Run(printf('%s -r -p -s %d %s %s', s:xxd, b:hexpair_page_total,
          \ shellescape(hex), shellescape(b:hexpair_page_file)))
  finally
    call delete(hex)
  endtry
endfunction

" Grow the file in place: move the tail right by the difference, working
" from the END backwards, then patch the page's new bytes in.
"
" Backwards is what makes this safe without a copy of the tail. Each step
" reads a block and writes it further along, into space that either lies
" past the old end of the file or holds bytes an earlier step has already
" moved - so a byte is never overwritten before it has been copied. A
" failure part way through leaves a file whose tail is half moved, but not
" one that has lost anything.
"
" Keeping a copy would need room for the whole tail, which is precisely
" what this path exists to avoid: the temporary space it uses is one
" block's worth of hex, whatever the size of the file.
function! s:GrowInPlace(raw, newlen) abort
  let base = b:hexpair_page_base
  let tail = base + b:hexpair_page_len
  let size = s:TailSize()
  let delta = a:newlen - b:hexpair_page_len

  call s:ExtendBy(delta)

  let hex = tempname()
  let moved = 0
  try
    while moved < size
      let chunk = size - moved
      if chunk > s:blocksize
        let chunk = s:blocksize
      endif
      let from = tail + size - moved - chunk
      call s:MoveRange(from, chunk, from + delta, hex)
      let moved += chunk
    endwhile
    call s:PatchInPlace(a:raw)
    let moved = -1
  finally
    call delete(hex)
    if moved >= 0
      echohl ErrorMsg
      echomsg printf('hexpair: %s was left with its tail half moved - the '
            \ . 'last %d bytes are %d further along, the %d before them are '
            \ . 'not. Nothing was lost: to finish it by hand, move the %d '
            \ . 'bytes at offset %d forward by %d, working from the end.',
            \ b:hexpair_page_file, moved, delta, size - moved,
            \ size - moved, tail, delta)
      echohl None
    endif
  endtry
endfunction

" Changed length: splice the file. Head, edited page and tail are
" block-copied into a temp file, which then replaces the original by
" being copied BACK over it - not rename()d, because the temp usually
" lives on a different filesystem (notably for /mnt/c/... paths under
" WSL) and because copying back keeps the target's inode, owner and
" permissions.
"
" That copy back is the one window in which a failure leaves the file
" incomplete, so the temp is deleted only after it succeeded; when it
" does not, the temp holds the complete new content and its path is
" reported as the recovery copy instead.
function! s:Splice(raw, newlen) abort
  let msg = HexPairPagedGateMessage(s:SpliceSupported())
  if !empty(msg)
    throw msg
  endif

  let base     = b:hexpair_page_base
  let tail     = base + b:hexpair_page_len
  let tailsize = b:hexpair_page_total - tail
  let total    = base + a:newlen + tailsize
  let tmp      = tempname()

  try
    call s:CopyRange(b:hexpair_page_file, 0, base, tmp, 1)
    call s:CopyRange(a:raw, 0, a:newlen, tmp, 0)
    call s:CopyRange(b:hexpair_page_file, tail, tailsize, tmp, 0)
    if getfsize(tmp) != total
      throw printf('hexpair: internal error - spliced %d bytes, expected %d',
            \ getfsize(tmp), total)
    endif
  catch
    " Nothing has reached the target yet, so this temp is worthless.
    call delete(tmp)
    throw v:exception . '; nothing was written'
  endtry

  let replaced = 0
  try
    call s:CopyRange(tmp, 0, total, b:hexpair_page_file, 1)
    let replaced = 1
  finally
    if replaced
      call delete(tmp)
    else
      echohl ErrorMsg
      echomsg printf('hexpair: rewriting %s failed part way through; the '
            \ . 'complete new content is kept in %s - recover it from there',
            \ b:hexpair_page_file, tmp)
      echohl None
    endif
  endtry
endfunction

" The file has no bytes left - a shrinking write emptied it - so there is
" no page to show. Leave a lone banner saying so, rather than a dump of
" bytes that are gone.
function! s:LoadEmpty() abort
  let b:hexpair_page_index      = 0
  let b:hexpair_page_base       = 0
  let b:hexpair_page_len        = 0
  let b:hexpair_page_total      = 0
  let b:hexpair_page_totalpages = 0
  let b:hexpair_page_ftime      = getftime(b:hexpair_page_file)
  let b:hexpair_n               = g:hexpair_bytes_per_line
  let b:hexpair_page_hexstart   = s:HexStart(0)
  let b:hexpair_banner_top      = printf('" hexpair: %s is empty', s:PageLabel())
  let b:hexpair_banner_bottom   = '" hexpair: end of empty file'

  let save_ul = &l:undolevels
  setlocal noreadonly modifiable
  try
    setlocal undolevels=-1
    silent %delete _
    call setline(1, [b:hexpair_banner_top, b:hexpair_banner_bottom])
  finally
    let &l:undolevels = save_ul
  endtry
  call cursor(1, 1)
  setlocal filetype=xxd
  call s:ApplyBannerSyntax()
  setlocal nomodified
  let b:hexpair_page_active = 1
  let b:hexpair_view = 'hex'
  call s:PasteOn()
endfunction

" After a successful write, show what is on disk now. A splice moved
" every byte behind this page and may have changed how many pages there
" are, so the page index is clamped to what is left.
function! s:ReloadAfterWrite(off) abort
  let wastext = !s:IsHexView()
  let total = getfsize(b:hexpair_page_file)
  let totalpages = HexPairPagedTotalPages(b:hexpair_page_size, total)
  if totalpages == 0
    call s:LoadEmpty()
  else
    let idx = b:hexpair_page_index
    if idx >= totalpages
      let idx = totalpages - 1
    endif
    call s:LoadPageInView(idx)
    if wastext
      call s:TextGotoOffset(a:off)
    else
      call s:PagedGotoOffset(a:off)
    endif
  endif
  setlocal nomodified
  call s:PagedHighlight()
endfunction

" Put the page's bytes AS THE BUFFER NOW HOLDS THEM into a:raw, and
" return the absolute file offset the cursor is on. The two views hold
" them differently - a dump to be stripped, or the bytes themselves - and
" that is the only difference between writing from one and the other.
function! s:PageBytes(raw) abort
  let hex = tempname()
  try
    if s:IsHexView()
      " One scan does the validation, the stripping and the cursor
      " mapping; three separate walks over the page would cost three
      " times as much.
      let scan = s:PagedScan(line('.'))
      if !empty(scan.err)
        if has_key(scan.err, 'lnum')
          call cursor(scan.err.lnum, scan.err.col)
          call s:PagedHighlight()
        endif
        throw 'hexpair: ' . scan.err.msg . '; nothing was written'
      endif
      let off = s:IsBannerLine(getline('.')) ? b:hexpair_page_base
            \ : b:hexpair_page_base + scan.bytes + s:PagedCursorLineIndex()
      call writefile(scan.lines, hex)
      call s:Run(printf('%s -r -p %s %s', s:xxd,
            \ shellescape(hex), shellescape(a:raw)))
    else
      " The text view's bytes need no conversion at all - they are the
      " page's bytes already, once the banner is off them.
      let lines = s:TextViewLines()
      let off = s:TextByteOffset()
      call writefile(lines, a:raw, 'b')
    endif
  finally
    call delete(hex)
  endtry
  if getfsize(a:raw) < 0
    throw 'hexpair: the reverse conversion produced no output; '
          \ . 'nothing was written'
  endif
  return off
endfunction

" ':w {file}' - write the WHOLE content being paged, with this page's
" edits in it, to somewhere else. For a view paged from piped input this
" is the only way to save at all; for one paged from a file it is a plain
" save-as that leaves the original alone.
"
" Vim itself refuses an existing target without a ! (E13) before this
" autocommand ever runs, so there is no need to check for that here.
function! s:WriteWholeTo(target) abort
  " s:WriteTarget() sends a write naming this view's own file down the
  " plain path, so this cannot normally happen - but copying a file over
  " itself truncates the source before a byte of it has been read, so it
  " is worth being certain about rather than merely confident.
  if s:SamePath(a:target, b:hexpair_page_file)
    throw printf('hexpair: refusing to copy %s over itself', a:target)
  endif
  let msg = HexPairPagedGateMessage(s:SpliceSupported(),
        \ 'writing the whole file somewhere else')
  if !empty(msg)
    throw msg
  endif
  call s:CheckFresh()

  let raw = tempname()
  try
    call s:PageBytes(raw)
    let newlen = getfsize(raw)
    let base = b:hexpair_page_base
    let tail = base + b:hexpair_page_len
    let tailsize = b:hexpair_page_total - tail
    call s:CopyRange(b:hexpair_page_file, 0, base, a:target, 1)
    call s:CopyRange(raw, 0, newlen, a:target, 0)
    call s:CopyRange(b:hexpair_page_file, tail, tailsize, a:target, 0)
  finally
    call delete(raw)
  endtry

  let total = getfsize(a:target)
  if get(b:, 'hexpair_page_spill', '') ==# ''
    " A file-backed view: this was a copy, so nothing about the buffer
    " changes - exactly as Vim's own ':w {file}' leaves a buffer alone.
    echomsg printf('hexpair: "%s" %dB written; %s is unchanged',
          \ a:target, total, b:hexpair_page_file)
    return
  endif

  " A view paged from piped input has just acquired a file. Adopt it, the
  " way Vim's own ':w {file}' adopts a name for an unnamed buffer, so the
  " next plain :w patches pages into it and the spill can go.
  call s:DropSpill()
  silent execute 'file ' . fnameescape(a:target)
  let b:hexpair_page_file = fnamemodify(a:target, ':p')
  let b:hexpair_page_bufname = bufname('%') ==# ''
        \ ? '' : fnamemodify(bufname('%'), ':p')
  call s:LoadPageInView(b:hexpair_page_index)
  setlocal nomodified
  echomsg printf('hexpair: "%s" %dB written; this view now edits it',
        \ a:target, total)
endfunction

function! s:Write() abort
  if !get(b:, 'hexpair_page_active', 0)
    throw 'hexpair: not a paged hex buffer; nothing was written'
  endif

  let target = s:WriteTarget()
  if target !=# ''
    call s:WriteWholeTo(target)
    return
  endif

  if get(b:, 'hexpair_page_spill', '') !=# ''
    throw 'hexpair: this view was paged from piped input, so there is no '
          \ . 'file to write it back to; use :w {file} to save all of it'
  endif

  let raw = tempname()
  try
    call s:CheckFresh()
    let off = s:PageBytes(raw)
    let newlen = getfsize(raw)
    call s:Debug('write: page holds %d bytes, was %d; cursor on byte %d',
          \ newlen, b:hexpair_page_len, off)
    if newlen == b:hexpair_page_len
      call s:PatchInPlace(raw)
    elseif !s:ConfirmResize(newlen)
      echomsg 'hexpair: cancelled; nothing was written'
      return
    elseif newlen > b:hexpair_page_len && s:TailShiftIsCheaper()
      call s:GrowInPlace(raw, newlen)
    else
      call s:Splice(raw, newlen)
    endif
  finally
    call delete(raw)
  endtry

  " Re-read from disk rather than trusting the buffer, and put the cursor
  " back on the byte it was on by absolute offset.
  call s:ReloadAfterWrite(off)
  echomsg s:PagesText()
endfunction

" BufReadCmd: the buffer's name is not a file Vim could read, so :e
" means "show this page as it is on disk now".
" Absolute file offset of [lnum, col] in the page as this buffer last
" rendered it, by canonical layout: dump line k is buffer line k + 1, and
" the column maps as s:PagedCursorByte() would. Deliberately reads no
" buffer content, so it works when there is none left to read.
function! s:PosOffset(pos) abort
  let [lnum, col] = a:pos
  let idx = lnum - 2
  if idx < 0
    return b:hexpair_page_base
  endif
  let [n, hexstart, hexend, asciistart] =
        \ s:PagedOffsetLayout(b:hexpair_page_base + idx * b:hexpair_n)
  if col >= asciistart
    let byte = col - asciistart
  elseif col >= hexstart
    let byte = (col - hexstart) / 3
  else
    let byte = 0
  endif
  if byte >= n
    let byte = n - 1
  endif
  return b:hexpair_page_base + idx * n + byte
endfunction

function! s:Reread() abort
  if !get(b:, 'hexpair_page_active', 0)
    return
  endif
  try
    " Neither the old content nor the cursor is available by the time
    " BufReadCmd runs, so the byte is mapped from the position noted while
    " the user was still on it (see s:PagedHighlight()) by CANONICAL
    " layout - no buffer access at all. Exact for a page as it was read,
    " best-effort for one that was edited, which :e is discarding anyway.
    let off = s:PosOffset(get(b:, 'hexpair_last_pos', [2, 1]))
    call s:LoadPageInView(b:hexpair_page_index)
    if s:IsHexView()
      call s:PagedGotoOffset(off)
      call s:PagedHighlight()
    else
      call s:TextGotoOffset(off)
    endif
  catch /^hexpair:/
    echohl ErrorMsg
    echomsg v:exception
    echohl None
  endtry
endfunction

function! s:RequirePaged() abort
  if !get(b:, 'hexpair_page_active', 0)
    echohl WarningMsg
    echomsg 'hexpair: not a paged hex buffer'
    echohl None
    return 0
  endif
  return 1
endfunction

" s:LoadPage() always builds the hex view, so anything that turns a page
" while the user is in the text view has to put them back in it. Turning
" a page must not also change which view they are looking at.
function! s:LoadPageInView(pageidx) abort
  let wastext = !s:IsHexView()
  if !s:LoadPage(a:pageidx)
    return 0
  endif
  if wastext
    call s:ToText()
  endif
  return 1
endfunction

function! s:GotoPage(pageidx, force) abort
  if !s:RequirePaged()
    return
  endif
  if &l:modified && !a:force
    echohl ErrorMsg
    echomsg 'hexpair: page has unsaved changes; use ! to discard them'
    echohl None
    return
  endif
  call s:LoadPageInView(a:pageidx)
endfunction

function! s:PageNext(force) abort
  if !s:RequirePaged()
    return
  endif
  call s:GotoPage(b:hexpair_page_index + 1, a:force)
endfunction

function! s:PagePrev(force) abort
  if !s:RequirePaged()
    return
  endif
  call s:GotoPage(b:hexpair_page_index - 1, a:force)
endfunction

function! s:PageGoto(n, force) abort
  if !s:RequirePaged()
    return
  endif
  call s:GotoPage(a:n - 1, a:force)
endfunction

" Parses the text typed at the :HexPairPageGoto prompt (see
" s:PageGotoPrompt() below): {} for an empty string (cancelled), a
" 'msg' key for invalid input, otherwise a 'page' key (1-based, as
" typed - not yet converted to a 0-based index or bounds-checked; the
" existing HexPairPagedBounds()-backed s:LoadPage() already reports a
" clear error for an out-of-range page, no need to duplicate that
" here). Global and pure so it is directly testable: confirmed
" empirically that input() itself does not behave usably under this
" project's `vim -es -u NONE` test harness (hangs or silently aborts
" the whole script depending on stdin), so the interactive prompt
" below is deliberately a thin, untested wrapper around this.
function! HexPairPagedParsePageInput(text) abort
  if empty(a:text)
    return {}
  endif
  if a:text !~# '^\d\+$'
    return {'msg': 'hexpair: not a page number: ' . a:text}
  endif
  return {'page': str2nr(a:text)}
endfunction

" Prompt for a page number (bounds are reported so the user knows the
" valid range) and jump to it - the <Plug> mapping equivalent of
" :HexPairPageGoto, which itself needs a typed {N} argument that a
" plain <Plug> target cannot supply. a:force mirrors :HexPairPageGoto's
" own ! - <Plug>(HexPairPageGoto) passes 0 (refuses to discard unsaved
" changes, same as the bare command), <Plug>(HexPairPageGotoForce)
" passes 1 (same as the command with !).
function! s:PageGotoPrompt(force) abort
  if !s:RequirePaged()
    return
  endif
  let n = input(printf('hexpair: goto page (1-%d): ', b:hexpair_page_totalpages))
  redraw
  let parsed = HexPairPagedParsePageInput(n)
  if has_key(parsed, 'msg')
    echohl ErrorMsg
    echomsg parsed.msg
    echohl None
  elseif has_key(parsed, 'page')
    call s:GotoPage(parsed.page - 1, a:force)
  endif
endfunction

" 1-based, inclusive byte positions - see the comment on s:BannerTop(),
" which this must stay consistent with (it reports the same
" information the banner shows).
" Position of the byte under the cursor, 1-based, or 0 when the cursor is
" not on one - a banner line has no byte, and an empty file has none at
" all. 1-based to match the banner's range and what |:HexPairGoOffset|
" takes, so the number can be typed straight back in.
function! s:CursorBytePosition() abort
  if b:hexpair_page_len <= 0
    return 0
  endif
  if s:IsHexView()
    return s:IsBannerLine(getline('.')) ? 0 : s:PagedByteOffset() + 1
  endif
  try
    return s:TextByteOffset() + 1
  catch /^hexpair:/
    return 0
  endtry
endfunction

function! s:PagesText() abort
  if b:hexpair_page_totalpages == 0
    return printf('hexpair: %s is empty (no pages)', b:hexpair_page_file)
  endif
  let text = printf('hexpair: page %d of %d, offsets %d-%d of total %d bytes (%s)',
        \ b:hexpair_page_index + 1, b:hexpair_page_totalpages,
        \ b:hexpair_page_base + 1, b:hexpair_page_base + b:hexpair_page_len,
        \ b:hexpair_page_total, s:PageLabel())
  " The byte under the cursor, in the form :HexPairGoOffset and vimhex's
  " @BYTE both accept, so where you are can be written down and gone back
  " to - in this session or another one.
  let at = s:CursorBytePosition()
  return at > 0 ? printf('%s; cursor on byte 0x%x (%d)', text, at, at) : text
endfunction

" Prompt for a byte offset and jump to it - the <Plug> equivalent of
" :HexPairGoOffset, which needs a typed {byte} a bare <Plug> cannot
" supply. a:force mirrors the command's own !. Deliberately untested, for
" the reason given at s:PageGotoPrompt(): input() does not behave usably
" under `vim -es`. All the decision logic lives in
" HexPairPagedParseOffsetInput(), which the suite exercises directly.
function! s:GotoOffsetPrompt(force) abort
  if !s:RequirePaged()
    return
  endif
  let text = input(printf('hexpair: goto byte (1-%d): ',
        \ b:hexpair_page_total))
  redraw
  let parsed = HexPairPagedParseOffsetInput(text)
  if has_key(parsed, 'msg')
    echohl ErrorMsg
    echomsg parsed.msg
    echohl None
  elseif has_key(parsed, 'offset')
    call s:GotoOffset(text, a:force)
  endif
endfunction

function! s:Pages() abort
  if !s:RequirePaged()
    return
  endif
  echo s:PagesText()
endfunction

" Function form of :HexPairOpen, for scripts and mappings building the
" filename programmatically (e.g. from an environment variable or a
" shell wrapper) instead of typing it on the Ex command line.
" :HexPairOpen's own -nargs=+ parsing round-trips a filename through
" <f-args>, which only un-escapes the handful of characters IT treats
" as argument separators (e.g. a space) - fnameescape()'s broader
" escaping (also covers '$', to stop Vim's command-line file-argument
" expansion of a literal "$VAR" in the name) does not fully round-trip
" through it, confirmed empirically: a name containing '$' comes out
" with a stray backslash still in front of it. A direct function call
" has no such text round trip - the string is evaluated once as a
" plain expression and reaches s:Open() unchanged, verified against a
" name containing spaces, non-ASCII characters and a literal '$NAME'
" substring.
" Jump straight to a byte offset, wherever in the file it is: the page
" holding it is a division now that pages are plain fixed-size slices.
" Global and pure so the arithmetic is testable without a file.
" a:off is 0-based, the message 1-based - see
" HexPairPagedParseOffsetInput() for why the two differ.
function! HexPairPagedOffsetError(off, total) abort
  if a:off < 0 || (a:off >= a:total && a:total > 0) || (a:off > 0 && a:total == 0)
    return printf('hexpair: byte %d is outside the file (%d bytes)',
          \ a:off + 1, a:total)
  endif
  return ''
endfunction

" {} for an empty string (cancelled), a 'msg' key for input that is not a
" byte position, otherwise an 'offset' key with the 0-based offset it
" names. Global and pure so it is directly testable, like the page-number
" parser above.
"
" What the user types is 1-BASED: byte 1 is the file's first byte, which
" is what the page banner and |:HexPairPages| say ("bytes 1-131072 of
" ..."), so a number read off the banner can be typed straight back in.
" The 0-based offsets are the dump's own column, xxd's native addresses,
" and are left alone - the same split the banner already makes.
function! HexPairPagedParseOffsetInput(text) abort
  if empty(a:text)
    return {}
  endif
  if a:text !~# '^\%(0[xX]\)\=\x\+$'
    return {'msg': printf('hexpair: not a byte position: %s '
          \ . '(decimal, or 0x for hex; byte 1 is the first)', string(a:text))}
  endif
  let n = a:text =~# '^0[xX]' ? str2nr(a:text[2:], 16) : str2nr(a:text)
  if n < 1
    return {'msg': 'hexpair: byte positions start at 1, not 0'}
  endif
  return {'offset': n - 1}
endfunction

function! s:GotoOffset(text, force) abort
  if !s:RequirePaged()
    return
  endif
  try
    let parsed = HexPairPagedParseOffsetInput(a:text)
    if has_key(parsed, 'msg')
      throw parsed.msg
    endif
    if !has_key(parsed, 'offset')
      return
    endif
    let off = parsed.offset
    let err = HexPairPagedOffsetError(off, getfsize(b:hexpair_page_file))
    if !empty(err)
      throw err
    endif
    let page = off / b:hexpair_page_size
    if page != b:hexpair_page_index
      call s:GotoPage(page, a:force)
      if page != b:hexpair_page_index
        return
      endif
    endif
    if s:IsHexView()
      call s:PagedGotoOffset(off)
      call s:PagedHighlight()
    else
      call s:TextGotoOffset(off)
    endif
  catch /^hexpair:/
    echohl ErrorMsg
    echomsg v:exception
    echohl None
  endtry
endfunction

function! HexPairOpenFile(file, ...) abort
  call call('s:Open', [a:file] + a:000)
endfunction

" ---------------------------------------------------------------------------
" The buffer's three states
" ---------------------------------------------------------------------------
"
" 1. PLAIN         an ordinary Vim buffer; hexpair has never touched it.
" 2. HEX-PAGE      one page of the file as an 'xxd -g 1' dump with absolute
"                  offsets, bracketed by the page banner.
" 3. WINDOWED-TEXT the SAME page's raw bytes as text, with the same banner.
"
" :HexPairToggle moves PLAIN -> HEX-PAGE -> WINDOWED-TEXT -> HEX-PAGE -> ...
" There is deliberately no way back to PLAIN: once a buffer holds one page
" rather than the whole file, presenting it as the file again would be a
" lie, and a plain :w would truncate the file down to that page. Close and
" reopen the file to get back.
"
" b:hexpair_page_active marks states 2 and 3; b:hexpair_view says which.

function! s:IsHexView() abort
  return get(b:, 'hexpair_view', '') ==# 'hex'
endfunction

" Where this buffer's pages are read from. :HexPairOpen names a file
" outright; :HexPairToggle has to work it out, because what a buffer holds
" and what its file holds are not always the same thing:
"
"   - unmodified and backed by a readable file: the file is the truth, so
"     pages come off disk. The buffer is re-read with ++bin first, since a
"     buffer loaded without it has already had CRs stripped, a BOM removed
"     and its content transcoded, none of which can be undone afterwards;
"   - no file at all (an unnamed buffer, `cat x | vim -`): the only copy of
"     the content is in memory, so it is spilled once into a private temp
"     file and paged from there. There is nothing to write back to, and a
"     write says so;
"   - modified and backed by a file: the two disagree, and every way of
"     resolving that silently loses something. Paging from disk would hide
"     the edits; paging from memory would let a page-range write drop every
"     edit outside the visible page. So this one is refused.
"
" Returns the cursor's byte offset in the content being paged, or -1 to
" mean "work it out from the buffer afterwards".
function! s:PageSource() abort
  let name = expand('%')
  if name !=# '' && filereadable(name)
    if &l:modified
      throw 'hexpair: the buffer has unwritten changes, so it and the file '
            \ . 'on disk no longer agree; write them with :w first, or use '
            \ . ':HexPairOpen to page the file as it stands on disk'
    endif
    let b:hexpair_page_file = fnamemodify(name, ':p')
    let b:hexpair_page_spill = ''
    if &l:binary
      return s:BufOffset()
    endif
    " Capture the cursor byte offset BEFORE the reload, in file-byte
    " terms: the reload changes the buffer content (BOM bytes and CRs
    " materialize, fileencoding transcoding is undone) while the cursor
    " keeps its old line/column coordinates, which would then point at a
    " different byte.
    let pos = s:PreReloadPos()
    silent edit ++bin
    return s:PostReloadOffset(pos)
  endif

  " A named file can be re-read with ++bin to undo what Vim did on the way
  " in; piped input cannot - there is nothing to re-read. So if this buffer
  " was not read in binary mode, its content may already be transcoded or
  " have had its line endings folded, and no dump of it can put that back.
  if !&l:binary
    echohl WarningMsg
    echomsg 'hexpair: this buffer was not read in binary mode, so Vim may'
          \ 'already have transcoded it; the bytes shown are the buffer''s,'
          \ 'not necessarily the input''s. Use `vim -b -` for binary input.'
    echohl None
  endif

  let off = s:BufOffset()
  let spill = tempname()
  " writefile()'s binary mode is the exact inverse of readfile()'s: list
  " items joined by NL with no trailing one, and a NL inside an item
  " written as the NUL it stands for. A trailing empty item is therefore
  " how a content that ends in a newline is expressed - and a buffer that
  " holds no bytes at all must produce an empty file, not a lone newline.
  let lines = s:ZeroBytes() ? [] : getline(1, '$') + (&l:eol ? [''] : [])
  call writefile(lines, spill, 'b')
  let b:hexpair_page_file = spill
  let b:hexpair_page_spill = spill
  return off
endfunction

" Turn the current buffer into a paged one. Both entry points converge
" here, so nothing downstream can tell which of them a buffer came from.
function! s:SetupPagedBuffer() abort
  setlocal buftype=acwrite bufhidden=hide noswapfile
  let b:hexpair_page_size = g:hexpair_page_size
  let b:hexpair_page_bufname = bufname('%') ==# ''
        \ ? '' : fnamemodify(bufname('%'), ':p')

  augroup HexPairPagedBuffer
    autocmd! * <buffer>
    autocmd CursorMoved,CursorMovedI <buffer> call s:PagedHighlight()
    autocmd BufWinLeave              <buffer> call s:PagedClearHighlight()
    autocmd BufWriteCmd              <buffer> call s:Write()
    autocmd BufReadCmd               <buffer> call s:Reread()
    autocmd BufEnter                 <buffer> call s:PasteOn()
    autocmd BufLeave                 <buffer> call s:PasteOff()
    autocmd BufWipeout               <buffer> call s:DropSpill()
  augroup END
endfunction

" The temp a spilled (unnamed) buffer is paged from belongs to that buffer
" and nothing else, so it goes when the buffer does.
function! s:DropSpill() abort
  if get(b:, 'hexpair_page_spill', '') !=# ''
    call delete(b:hexpair_page_spill)
    let b:hexpair_page_spill = ''
  endif
endfunction

" PLAIN -> HEX-PAGE.
function! s:ToHex() abort
  let s:xxd = s:ResolveXxd()
  if s:xxd ==# ''
    throw 'hexpair: xxd not found in PATH nor in $VIMRUNTIME'
  endif
  let sizeerr = HexPairPagedSizeError(g:hexpair_page_size, g:hexpair_bytes_per_line)
  if !empty(sizeerr)
    throw sizeerr
  endif

  let off = s:PageSource()
  call s:Debug('entering hex mode on byte %d, page %d',
        \ off, off / g:hexpair_page_size + 1)
  call s:SetupPagedBuffer()

  " Start on the page holding the byte the cursor was on, not on page 1 -
  " every mode transition in this plugin keeps the cursor's byte.
  try
    if !s:LoadPage(off / b:hexpair_page_size)
      call s:AbandonSetup()
      return
    endif
  catch
    call s:AbandonSetup()
    throw v:exception
  endtry
  call s:PagedGotoOffset(off)
  call s:PagedHighlight()
  redraw!
endfunction

" Undo s:SetupPagedBuffer() when the page never got loaded, so a buffer
" is never left looking paged (acwrite, our BufWriteCmd) without the page
" state a write would need.
function! s:AbandonSetup() abort
  augroup HexPairPagedBuffer
    autocmd! * <buffer>
  augroup END
  call s:DropSpill()
  setlocal buftype= bufhidden=
  unlet! b:hexpair_page_file b:hexpair_page_size b:hexpair_page_bufname
        \ b:hexpair_page_spill
endfunction

" ---------------------------------------------------------------------------
" Windowed text view
" ---------------------------------------------------------------------------
"
" The page's raw bytes as text. Two things make it more than a display
" variant: it carries the same banner, so the buffer never quietly
" pretends to be the whole file, and a :w from here goes through the same
" page-range write - the buffer holds one page's worth of bytes, so a
" literal Vim write would truncate the file down to it.
"
" Bytes survive the round trip through readfile()/writefile()'s binary
" mode, which is exact in a way getline() alone is not: Vim stores a NUL
" byte as a NL inside a line, and those two functions are inverses of each
" other about that, about the split on newlines, and about a trailing one.

" The banner cannot be recognized by its first character here the way it
" can in a hex dump: a dump line always starts with a hex digit, but a
" page of raw bytes may perfectly well start with a double quote. So the
" exact banner text is remembered when the view is built, and only an
" exact match at the top and bottom counts - anything else means the user
" edited or deleted a banner line, and the write is refused rather than
" guessing which bytes are content.
function! s:TextBodyRange() abort
  if line('$') < 2
        \ || getline(1) !=# get(b:, 'hexpair_banner_top', "\<NUL>")
        \ || getline('$') !=# get(b:, 'hexpair_banner_bottom', "\<NUL>")
    throw 'hexpair: the page banner was edited or removed, so which lines '
          \ . 'are content can no longer be told apart from which are the '
          \ . 'banner; reload the page with :HexPairPageGoto! '
          \ . (get(b:, 'hexpair_page_index', 0) + 1)
  endif
  return [2, line('$') - 1]
endfunction

" The page's bytes as the text view currently holds them.
function! s:TextViewLines() abort
  let [first, last] = s:TextBodyRange()
  return last < first ? [] : getline(first, last)
endfunction

" Byte offset within the page of the cursor, and the reverse.
function! s:TextByteOffset() abort
  let [first, last] = s:TextBodyRange()
  let lnum = line('.') < first ? first : (line('.') > last ? last : line('.'))
  let off = 0
  for l in range(first, lnum - 1)
    let off += strlen(getline(l)) + 1
  endfor
  call s:Debug('text view line %d, column %d -> byte %d',
        \ lnum, col('.'), b:hexpair_page_base + off + col('.') - 1)
  return b:hexpair_page_base + off + col('.') - 1
endfunction

function! s:TextGotoOffset(abs) abort
  let [first, last] = s:TextBodyRange()
  let rel = a:abs - b:hexpair_page_base
  let acc = 0
  for l in range(first, last)
    let len = strlen(getline(l))
    if rel <= acc + len
      call cursor(l, rel - acc + 1)
      return
    endif
    let acc += len + 1
  endfor
  call cursor(last, 1)
endfunction

" Replace the buffer with a:lines bracketed by the current page's banner,
" without making it an undoable edit (see s:LoadPage() for why).
function! s:SetViewLines(lines) abort
  let save_ul = &l:undolevels
  setlocal noreadonly modifiable
  try
    setlocal undolevels=-1
    silent %delete _
    call setline(1, [b:hexpair_banner_top] + a:lines + [b:hexpair_banner_bottom])
  finally
    let &l:undolevels = save_ul
  endtry
endfunction

" HEX-PAGE -> WINDOWED-TEXT, carrying the page's bytes as they stand -
" including edits made in the dump, which is why this converts the buffer
" rather than re-reading the page from disk.
function! s:ToText() abort
  let scan = s:PagedScan(0)
  if !empty(scan.err)
    if has_key(scan.err, 'lnum')
      call cursor(scan.err.lnum, scan.err.col)
      call s:PagedHighlight()
    endif
    throw 'hexpair: ' . scan.err.msg . '; still in the hex view'
  endif

  let off = s:PagedByteOffset()
  let modified = &l:modified
  let hex = tempname()
  let raw = tempname()
  try
    call writefile(scan.lines, hex)
    call s:Run(printf('%s -r -p %s %s', s:xxd,
          \ shellescape(hex), shellescape(raw)))
    call s:PagedClearHighlight()
    call s:SetViewLines(readfile(raw, 'b'))
  finally
    call delete(hex)
    call delete(raw)
  endtry

  let b:hexpair_view = 'text'
  " The bundled xxd ftplugin's editing defaults belong to a dump, not to
  " raw bytes. Clearing 'filetype' fires no FileType event (there is no
  " new filetype to fire for), so its undo has to be run by hand - the
  " same thing the whole-file toggle used to do on its way out of hex
  " mode. Going back to the hex view sets filetype=xxd, which does fire,
  " and re-applies them.
  setlocal filetype=
  if exists('b:undo_ftplugin')
    execute b:undo_ftplugin
    unlet b:undo_ftplugin
  endif
  unlet! b:did_ftplugin
  call s:ApplyBannerSyntax()
  if !modified
    setlocal nomodified
  endif
  call s:TextGotoOffset(off)
  redraw!
endfunction

" WINDOWED-TEXT -> HEX-PAGE, the same way round.
function! s:ToHexView() abort
  let off = s:TextByteOffset()
  let modified = &l:modified
  let raw = tempname()
  let dump = tempname()
  try
    call writefile(s:TextViewLines(), raw, 'b')
    call s:CanonicalDump(raw, b:hexpair_page_base, dump)
    call s:SetViewLines(readfile(dump))
  finally
    call delete(raw)
    call delete(dump)
  endtry

  let b:hexpair_view = 'hex'
  setlocal filetype=xxd
  call s:ApplyBannerSyntax()
  if !modified
    setlocal nomodified
  endif
  call s:PagedGotoOffset(off)
  call s:PagedHighlight()
  redraw!
endfunction

function! s:Toggle() abort
  try
    if !get(b:, 'hexpair_page_active', 0)
      call s:ToHex()
    elseif s:IsHexView()
      call s:ToText()
    else
      call s:ToHexView()
    endif
  catch /^hexpair:/
    echohl ErrorMsg
    echomsg v:exception
    echohl None
  endtry
endfunction

" ---------------------------------------------------------------------------
" Refreshing the rendering
" ---------------------------------------------------------------------------

" Regenerate the offset and ASCII columns from the current hex payload,
" without touching the file on disk: the same round trip a toggle to the
" text view and back would perform, but without leaving the hex view.
" 'modified' must come out exactly as it went in - no byte changes, only
" the rendering of it.
function! s:Refresh() abort
  if !get(b:, 'hexpair_page_active', 0)
    echohl WarningMsg | echomsg 'hexpair: hex mode is not active' | echohl None
    return
  endif
  if !s:IsHexView()
    echohl WarningMsg
    echomsg 'hexpair: the text view has no offset or ASCII columns to refresh'
    echohl None
    return
  endif
  try
    let modified = &l:modified
    call s:ToText()
    call s:ToHexView()
    if !modified
      setlocal nomodified
    endif
  catch /^hexpair:/
    echohl ErrorMsg
    echomsg v:exception
    echohl None
  endtry
endfunction

" ---------------------------------------------------------------------------
" Command and mappings
" ---------------------------------------------------------------------------

command! -bar HexPairToggle  call s:Toggle()
command! -bar HexPairGoHex   call s:PagedJumpTo('hex')
command! -bar HexPairGoAscii call s:PagedJumpTo('ascii')
command! -bar HexPairSwap    call s:PagedJumpTo('swap')
command! -bar HexPairRefresh call s:Refresh()

command! -bar -nargs=+ -complete=file HexPairOpen call s:Open(<f-args>)
command! -bar -bang HexPairPageNext call s:PageNext('<bang>' ==# '!')
command! -bar -bang HexPairPagePrev call s:PagePrev('<bang>' ==# '!')
command! -bar -bang -nargs=1 HexPairPageGoto call s:PageGoto(str2nr(<q-args>), '<bang>' ==# '!')
command! -bar -bang -nargs=1 HexPairGoOffset
      \ call s:GotoOffset(<q-args>, '<bang>' ==# '!')
command! -bar HexPairPages call s:Pages()

" No default key mappings are defined; map the <Plug> mappings (or the
" commands directly) in your vimrc, e.g.:
"   nmap <Leader>j <Plug>(HexPairPageNext)
"   nmap <Leader>k <Plug>(HexPairPagePrev)
"   nmap <Leader>g <Plug>(HexPairPageGoto)
" Force variants (discard unsaved changes, like the ! commands) need no
" <Plug> target for Next/Prev - map the bang command directly:
"   nnoremap <silent> <Leader>J :HexPairPageNext!<CR>
"   nnoremap <silent> <Leader>K :HexPairPagePrev!<CR>
"   nmap <Leader>G <Plug>(HexPairPageGotoForce)
nnoremap <silent> <Plug>(HexPairPageNext) :<C-U>HexPairPageNext<CR>
nnoremap <silent> <Plug>(HexPairPagePrev) :<C-U>HexPairPagePrev<CR>
nnoremap <silent> <Plug>(HexPairPageGoto) :<C-U>call <SID>PageGotoPrompt(0)<CR>
nnoremap <silent> <Plug>(HexPairPageGotoForce) :<C-U>call <SID>PageGotoPrompt(1)<CR>
nnoremap <silent> <Plug>(HexPairGoOffset) :<C-U>call <SID>GotoOffsetPrompt(0)<CR>
nnoremap <silent> <Plug>(HexPairGoOffsetForce) :<C-U>call <SID>GotoOffsetPrompt(1)<CR>
nnoremap <silent> <Plug>(HexPairPages) :<C-U>HexPairPages<CR>

" No default key mappings are defined; map the <Plug> mappings (or the
" commands directly) in your vimrc, e.g.:
"   nmap <Leader>h <Plug>(HexPairToggle)
"   nmap <Leader>< <Plug>(HexPairGoHex)
"   nmap <Leader>> <Plug>(HexPairGoAscii)
"   nmap <Leader>- <Plug>(HexPairSwap)
"   nmap <Leader>r <Plug>(HexPairRefresh)
nnoremap <silent> <Plug>(HexPairToggle)  :<C-U>HexPairToggle<CR>
nnoremap <silent> <Plug>(HexPairGoHex)   :<C-U>HexPairGoHex<CR>
nnoremap <silent> <Plug>(HexPairGoAscii) :<C-U>HexPairGoAscii<CR>
nnoremap <silent> <Plug>(HexPairSwap)    :<C-U>HexPairSwap<CR>
nnoremap <silent> <Plug>(HexPairRefresh) :<C-U>HexPairRefresh<CR>

let &cpo = s:cpo_save
unlet s:cpo_save
