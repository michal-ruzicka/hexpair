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
" Views:            :HexPairToggle, :HexPairGoHex, :HexPairGoAscii,
"                   :HexPairSwap, :HexPairRefresh
" Pages:            :HexPairOpen, :HexPairPageNext, :HexPairPagePrev,
"                   :HexPairPageGoto, :HexPairGoOffset, :HexPairPages,
"                   :HexPairSplit, :HexPairVSplit
" Reading bytes:    :HexPairInspect, :HexPairSelection
" Finding bytes:    :HexPairFind, :HexPairFindText, :HexPairFindNext,
"                   :HexPairFindPrev, :HexPairReplace,
"                   :HexPairReplaceAllInPage
" Comparing:        :HexPairDiff, :HexPairDiffNext, :HexPairDiffPrev
" Marks:            :HexPairMark, :HexPairGoMark, :HexPairMarks,
"                   :HexPairMarkDelete
" Functions:        HexPairStatus() for 'statusline', HexPairOpenFile()
"                   and HexPairDiffWith() for scripts and wrappers
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
"   g:hexpair_ruler            set to 1 for a line numbering the byte
"                              columns of the dump (default 0)
"   g:hexpair_show_modified    set to 0 to stop marking the bytes edited
"                              and not yet written (default 1)
"   g:hexpair_show_marks       set to 0 to stop underlining the byte a
"                              mark stands on (default 1)
"   g:hexpair_split_views      set to 1 to make a plain :split of a hex
"                              page a view of its own (default 0)
"   g:hexpair_short_commands   set to 0 to leave the short HP names
"                              undefined (default 1, define them)
"   g:hexpair_bind_pages       set to 0 to stop a page turn from taking
"                              the scroll-bound windows with it
"                              (default 1, take them)
"   g:hexpair_debug            set to 1 to echo position-mapping traces
"                              (inspect with :messages)
"   HexPairActive, HexPairMirror, HexPairPageBanner, HexPairModified,
"   HexPairDiff, HexPairFind, HexPairMark   highlight groups
"
" Editing defaults for the dump (tabstop, shiftwidth, no automatic
" formatting) live in the bundled ftplugin/xxd.vim; see
" :help hexpair-ftplugin for how to overrule them.

" This file has a multibyte character in it (the maintainer's name), so it
" says which encoding that is in: without this, a Vim whose 'encoding' is
" not utf-8 reads those bytes as whatever its own encoding makes of them.
scriptencoding utf-8

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
" loads in hundredths of a second and writes in about a seventh of one.
" The size buys nothing in return - :HexPairPageGoto reaches any page
" directly - so it is deliberately small; raise it only to see more of
" the file at once, and expect a write to slow down roughly in
" proportion (1 MiB ~ 0.9 s, 4 MiB ~ 3.6 s on the author's machine).
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

" A ruler line under the top banner, numbering the byte columns of the
" dump. Off by default: it is one more line of decoration on a view whose
" whole point is the bytes, and the ASCII column already tells you where
" you are once you know the layout. A page carries the setting it was
" opened with, so changing it mid-session cannot desynchronize an open
" page from the arithmetic that maps its lines to byte offsets.
if !exists('g:hexpair_ruler')
  let g:hexpair_ruler = 0
endif

" Whether the bytes of the page that differ from the ones on disk are
" highlighted (HexPairModified). What it costs is a comparison of the
" lines on screen whenever the page changes or scrolls, and one copy of
" the page's bytes as hex - 256 KB for the default 128 KiB page.
if !exists('g:hexpair_show_modified')
  let g:hexpair_show_modified = 1
endif

" Whether every command is also defined under a short "HP" name -
" :HPFind for :HexPairFind, and so on. Set it to 0 to leave that
" namespace alone.
if !exists('g:hexpair_short_commands')
  let g:hexpair_short_commands = 1
endif

" Whether the bytes that have a mark on them (|:HexPairMark|) are
" highlighted (HexPairMark). Marks are sparse and the marking is one byte
" wide, so this costs a walk over the file's marks whenever the page
" changes or scrolls, and nothing at all in between.
if !exists('g:hexpair_show_marks')
  let g:hexpair_show_marks = 1
endif

" Whether a window that ends up showing a page a SECOND time becomes an
" independent view of the same file - its own buffer, its own page, its
" own cursor - instead of a second window onto the same buffer, which is
" what :split means everywhere else in Vim and therefore what it means
" here by default. Off, because a page is thousands of lines and looking
" at two parts of ONE page in two windows is a real use of :split, which
" turning it into a second view would take away. |:HexPairSplit| does the
" same thing explicitly, whatever this is set to.
if !exists('g:hexpair_split_views')
  let g:hexpair_split_views = 0
endif

" Whether a page turn in a window is passed on to the windows that are
" scroll-bound to it. 'scrollbind' is Vim's own "these windows move
" together", and a page turn is the one kind of scrolling it cannot
" follow by itself: the other window keeps the page it had, so the two go
" on scrolling in step through different parts of their files - which is
" what `vimhexdiff` looked like it was doing wrong. On, because a bound
" window that shows a different region is not showing anything useful;
" set it to 0 to have 'scrollbind' mean scrolling alone.
if !exists('g:hexpair_bind_pages')
  let g:hexpair_bind_pages = 1
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

" Highlight group for bytes that differ from what the file holds at that
" position - the edits not yet written.
"
" DiffChange rather than DiffText, though DiffText is the closer name:
" Vim's own default for DiffText is `guibg=Red` with NO foreground, so it
" leaves the text whatever colour 'Normal' has - black on red for anyone
" with a light background, which is the worst pairing of the two. Both of
" DiffChange's default backgrounds (LightMagenta, DarkMagenta) keep their
" contrast with a light or a dark foreground, and "this part changed" is
" what it means anyway.
"
" An override should set a foreground AND a background, for the same
" reason: giving only one leaves the other at the colour scheme's, and
" the two can land on top of each other.
highlight default link HexPairModified DiffChange

" Highlight group for bytes that differ from the file being compared
" against (|:HexPairDiff|), as opposed to from this view's own file.
highlight default link HexPairDiff DiffAdd

" Highlight group for what |:HexPairFind| is looking for, wherever it is
" on the page - the byte equivalent of 'hlsearch'.
highlight default link HexPairFind Search

" Highlight group for a byte a mark stands on (|:HexPairMark|). Underline
" and bold rather than a colour, deliberately: a mark says "this place",
" not "these bytes are different", and the three colourings around it -
" edited, differing, found - are about the bytes. Underlining coexists
" with a colour scheme instead of competing with it, and a mark sitting
" on a byte that is also edited or found yields to that, since the
" markings do not blend (see the priorities in s:MarkHighlight()).
highlight default HexPairMark term=underline,bold cterm=underline,bold
      \ gui=underline,bold

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

" Blocks the file-wide comparison reads in. Smaller than the write's,
" because two of them are held as hex at once - a megabyte of file is two
" megabytes of hex on each side.
let s:diffblock = 1024 * 1024

" How much of two runs of hex is compared at once when counting the bytes
" that differ (HexPairPagedCountDifferences()). Measured over a 128 KiB
" page, from 256 to 16384: a bigger block skips matching bytes faster and
" takes apart differing ones slower, and 1024 is where the two meet -
" 8 ms for a page with a handful of differences either way.
let s:cmpblock = 1024

" Set while a page turn is being passed on to the scroll-bound windows, so
" that their own turns do not pass it back.
let s:binding = 0

" From what size a file-wide scan (|:HexPairFind|, |:HexPairDiffNext|)
" says where it has got to. Below it a scan is over before a message
" could be read, and a progress line that flashes past is noise; above it
" a scan is minutes of a silent Vim, which is indistinguishable from a
" hang.
let s:progressfrom = 16 * 1024 * 1024

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

" The ruler line (g:hexpair_ruler): the byte index of every column of the
" dump, two digits per byte in the hex column and the low nibble alone in
" the ASCII one, so a byte can be counted off without counting spaces.
" Starts with a '"', which is what makes it contribute no bytes - the
" same rule the banner lines rely on (s:IsBannerLine()).
"
" It is drawn for the layout of the page's FIRST line. A page that
" straddles the 4 GiB offset-width change carries lines of two widths
" (s:PagedLineLayout()), and the ruler can only line up with one of
" them; the dump itself stays correct either way.
function! s:RulerLine(hexstart, n) abort
  let hex = []
  let ascii = ''
  for i in range(a:n)
    call add(hex, printf('%02x', i))
    let ascii .= printf('%x', i % 16)
  endfor
  return '"' . repeat(' ', a:hexstart - 2) . join(hex, ' ') . '  ' . ascii
endfunction

" Lines before the first dump line of a hex page: the top banner, plus
" the ruler when the page was opened with one. The one number that turns
" a dump line into a byte offset and back, so it is read from the buffer
" it belongs to rather than from the global option.
function! s:HeaderLines() abort
  return get(b:, 'hexpair_page_header', 1)
endfunction

" The whole hex view around a page's dump lines.
function! s:HexViewLines(dump) abort
  let head = [b:hexpair_banner_top]
  if s:HeaderLines() > 1
    call add(head, s:RulerLine(b:hexpair_page_hexstart, b:hexpair_n))
  endif
  return head + a:dump + [b:hexpair_banner_bottom]
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

" ---------------------------------------------------------------------------
" The bytes that differ from the file
" ---------------------------------------------------------------------------
"
" What has been edited and not yet written, marked in both columns. The
" comparison is against the page's bytes as they were READ (kept in
" b:hexpair_page_hex), at the position the layout puts each line at - so a
" byte is marked when what is on the screen at that offset is not what the
" file holds there. After an insertion that means everything after it, and
" that is the truth: those offsets really do hold something else now.
"
" Only the lines on screen are compared, and only when the page has
" changed or scrolled - the matches are left alone on a plain cursor
" movement, which is the thing that happens most.

" Byte runs that differ, as matchaddpos() positions for both columns.
"
" Global and given the range to look at, rather than reading the window's
" own: `vim -es`, this project's test harness, has no window to speak of -
" line('w$') comes out BEFORE line('w0') there - so the drawing has to be
" separable from what it draws, the same split
" HexPairPagedSelectionPositions() makes for Visual mode.
function! HexPairPagedComparePositions(first, last, hex) abort
  let n = b:hexpair_n
  let orig = a:hex
  let out = []
  for lnum in range(a:first, a:last)
    let line = getline(lnum)
    if s:IsBannerLine(line)
      continue
    endif
    let idx = lnum - 1 - s:HeaderLines()
    if idx < 0
      continue
    endif
    let cur = tolower(s:PagedLineDigits(line))
    let bytes = strlen(cur) / 2
    if bytes <= 0
      continue
    endif
    let [n, hexstart, hexend, asciistart] = s:PagedLineLayout(lnum)
    let hasascii = strlen(line) >= asciistart
    let lo = -1
    let i = 0
    while i <= bytes
      " One past the end closes a run that reaches the end of the line.
      let differs = i < bytes && strpart(cur, i * 2, 2)
            \ !=# strpart(orig, (idx * n + i) * 2, 2)
      if differs && lo < 0
        let lo = i
      elseif !differs && lo >= 0
        call add(out, [lnum, hexstart + lo * 3, (i - lo) * 3 - 1])
        if hasascii
          call add(out, [lnum, asciistart + lo, i - lo])
        endif
        let lo = -1
      endif
      let i += 1
    endwhile
  endfor
  return out
endfunction

function! s:ClearModifiedHighlight() abort
  if exists('w:hexpair_mod_ids')
    for id in w:hexpair_mod_ids
      silent! call matchdelete(id)
    endfor
  endif
  let w:hexpair_mod_ids = []
  let w:hexpair_mod_state = []
endfunction

" What the modified-byte marking compares against: the page as it was read.
function! HexPairPagedModifiedPositions(first, last) abort
  return HexPairPagedComparePositions(a:first, a:last,
        \ get(b:, 'hexpair_page_hex', ''))
endfunction

function! s:ModifiedHighlight() abort
  if !g:hexpair_show_modified || !get(b:, 'hexpair_page_active', 0)
        \ || get(b:, 'hexpair_page_hex', '') ==# ''
    return
  endif
  " Nothing to recompute while the page, the window's view of it and the
  " modified flag are all as they were.
  let state = [b:changedtick, line('w0'), line('w$'), &l:modified]
  if get(w:, 'hexpair_mod_state', []) ==# state
    return
  endif
  call s:ClearModifiedHighlight()
  let w:hexpair_mod_state = state
  if !&l:modified
    return
  endif
  let positions = HexPairPagedMarkingPositions('modified',
        \ line('w0'), line('w$'))
  " matchaddpos() takes eight positions at a time.
  for i in range(0, len(positions) - 1, 8)
    call add(w:hexpair_mod_ids,
          \ matchaddpos('HexPairModified', positions[i : i + 7]))
  endfor
endfunction

" Every marking is a window-local match, and a window that is SCROLLED
" without being entered - which is what 'scrollbind' does, and what
" vimhexdiff sets up - raises no event of its own, so its markings stay
" where they were drawn and simply stop part way down. Each window that
" shows a paged buffer is therefore refreshed from here; the state check
" inside each marking makes that free for the windows that did not move.
"
" noautocmd, so hopping between them raises nothing (least of all another
" CursorMoved), and the window that was current is current again at the
" end whatever happens in between.
"
" Not from every mode, though: going to another window and back is what
" refreshes one that scrolled without being entered, and it is also what
" ENDS a Visual selection - and would take Insert mode with it. In
" vimhexdiff, where two windows are what make this run at all, that made
" Visual mode unusable: `v` held until the cursor moved and then dropped
" it, `V` flashed and was gone. So this happens from Normal mode and from
" the command line (which is also where a script drives it from), and not
" from a Visual, Select, Insert or Replace one. While a selection is being
" made the other window's markings stay as they were; the next movement
" outside it brings them up to date.
" Which modes that is, as a function, because mode() cannot be put into a
" Visual one under this project's headless harness (there it is always
" 'c', which is a mode this does allow - a script driving the plugin is
" not holding a selection).
function! HexPairPagedMayLeaveWindow(mode) abort
  return a:mode =~# '^[nc]'
endfunction

function! s:RefreshOtherWindows() abort
  if winnr('$') < 2 || !HexPairPagedMayLeaveWindow(mode())
    return
  endif
  let here = winnr()
  try
    let w = 1
    while w <= winnr('$')
      if w != here && getbufvar(winbufnr(w), 'hexpair_page_active', 0)
        noautocmd execute w . 'wincmd w'
        call s:ModifiedHighlight()
        call s:DiffHighlight()
        call s:FindHighlight()
        call s:MarkHighlight()
      endif
      let w += 1
    endwhile
  finally
    noautocmd execute here . 'wincmd w'
  endtry
endfunction

" A size as a person reads one. Sizes here span a boot sector and a disk
" image, so the unit follows the number rather than the number the unit.
function! HexPairPagedSizeText(bytes) abort
  if a:bytes >= 1024 * 1024 * 1024
    return printf('%.1f GiB', a:bytes / 1024.0 / 1024.0 / 1024.0)
  endif
  if a:bytes >= 1024 * 1024
    return printf('%.1f MiB', a:bytes / 1024.0 / 1024.0)
  endif
  if a:bytes >= 1024
    return printf('%.1f KiB', a:bytes / 1024.0)
  endif
  return printf('%d bytes', a:bytes)
endfunction

" What a scan says while it runs. Pure, and therefore testable: the
" message is the only part of a progress report that can be wrong in a
" way anyone would notice.
function! HexPairPagedProgressText(what, done, total) abort
  return printf('hexpair: %s %d%% of %s (CTRL-C stops)', a:what,
        \ a:total > 0 ? a:done * 100 / a:total : 100,
        \ HexPairPagedSizeText(a:total))
endfunction

" Scans of a big file report where they have got to. The redraw AFTER the
" echo is what puts the line on the screen while a function is still
" running, and it has to be the forcing one: measured in a terminal over
" five updates, a plain :redraw before the echo showed one of them, after
" it two, and :redraw! all five - Vim skips a redraw it believes changes
" nothing, and a message written from inside a running function is
" exactly that.
function! s:Progress(what, done, total) abort
  if a:total < s:progressfrom
    return
  endif
  echo HexPairPagedProgressText(a:what, a:done, a:total)
  redraw!
endfunction

" A page turn is scrolling by a whole page, and 'scrollbind' cannot follow
" it: the bound window stays on the page it had, and the two then scroll
" in step through different parts of their files. Every scroll-bound
" window showing a page is therefore moved to the page holding the same
" BYTE - by offset, not by page number, because two views need not be
" paged the same way - and lands its cursor on it, so the two are aligned
" exactly rather than merely level.
"
" A window with unwritten changes is left where it is: following would
" mean discarding them, and this window's page turn is no reason to. So
" is one whose file does not reach that far. Both say so, because a
" bound window quietly showing something else is the bug this fixes.
function! s:BindPageTurn(offset) abort
  if !g:hexpair_bind_pages || !&l:scrollbind || winnr('$') < 2 || s:binding
    return
  endif
  let here = winnr()
  let s:binding = 1
  try
    let w = 1
    while w <= winnr('$')
      if w != here && getbufvar(winbufnr(w), 'hexpair_page_active', 0)
        noautocmd execute w . 'wincmd w'
        call s:FollowPageTurn(a:offset)
      endif
      let w += 1
    endwhile
  finally
    let s:binding = 0
    noautocmd execute here . 'wincmd w'
  endtry
endfunction

" The bound window's half of it, run with that window current. Its own
" 'scrollbind' comes off while the page loads: a window being filled
" scrolls, and a scroll here would drag the window the turn came from.
function! s:FollowPageTurn(offset) abort
  if !&l:scrollbind || !get(b:, 'hexpair_page_active', 0)
    return
  endif
  let page = a:offset / b:hexpair_page_size
  if page == b:hexpair_page_index
    return
  endif
  if &l:modified
    call s:Stayed('has unsaved changes')
    return
  endif
  if page >= HexPairPagedTotalPages(b:hexpair_page_size,
        \ getfsize(b:hexpair_page_file))
    call s:Stayed(printf('has no page %d', page + 1))
    return
  endif
  let bound = &l:scrollbind
  setlocal noscrollbind
  try
    if s:LoadPageInView(page)
      if s:IsHexView()
        call s:PagedGotoOffset(a:offset)
        call s:PagedHighlight()
      else
        call s:TextGotoOffset(a:offset)
      endif
    endif
  finally
    let &l:scrollbind = bound
  endtry
endfunction

function! s:Stayed(why) abort
  echomsg printf('hexpair: %s %s, so that view stayed on page %d',
        \ s:PageLabel(), a:why, b:hexpair_page_index + 1)
endfunction

" Every byte-level marking this plugin draws, taken off the window. They
" are matchaddpos() matches, which belong to the WINDOW and not to what it
" is showing, so a view that stops being a hex dump has to say so: the
" columns of a dump are not the columns of anything else, and the marks
" would otherwise sit on the text view at the offsets the hex view put
" them (which is what they did).
" The positions of one marking layer over the given lines, in whichever
" view the buffer is in - 'modified', 'diff', 'find' or 'mark'. One entry
" point, so the four layers cannot drift apart about which view they are
" drawing in, and so the suite can ask for a range of lines that a
" headless window (one line tall) does not actually show.
function! HexPairPagedMarkingPositions(layer, first, last) abort
  let hex = s:IsHexView()
  if a:layer ==# 'modified'
    return hex ? HexPairPagedModifiedPositions(a:first, a:last)
          \ : s:TextComparePositions(a:first, a:last, 'page',
          \                          get(b:, 'hexpair_page_hex', ''))
  elseif a:layer ==# 'diff'
    return hex ? s:DiffPositions(a:first, a:last)
          \ : s:TextComparePositions(a:first, a:last, 'diff', s:DiffHex())
  elseif a:layer ==# 'find'
    return hex ? HexPairPagedFindPositions(a:first, a:last)
          \ : s:TextFindPositions(a:first, a:last)
  endif
  return hex ? HexPairPagedMarkPositions(a:first, a:last)
        \ : s:TextMarkPositions(a:first, a:last)
endfunction

function! s:ClearMarkings() abort
  call s:ClearModifiedHighlight()
  call s:ClearDiffHighlight()
  call s:ClearFindHighlight()
  call s:ClearMarkHighlight()
endfunction

function! s:PagedHighlight() abort
  call s:PagedClearHighlight()
  call s:ModifiedHighlight()
  call s:DiffHighlight()
  call s:FindHighlight()
  call s:MarkHighlight()
  call s:RefreshOtherWindows()
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
  " One read, two uses: the bytes are what the modified-byte highlight
  " compares against, and their hash is what a write checks the page
  " against (s:CheckFresh()).
  let b:hexpair_page_hex        = s:PageHex(base, len)
  let b:hexpair_page_digest     = b:hexpair_page_hex ==# '' || !exists('*sha256')
        \ ? '' : sha256(b:hexpair_page_hex)
  let b:hexpair_n               = g:hexpair_bytes_per_line
  " Where the page's FIRST line starts its hex column; later lines
  " derive their own (s:PagedLineLayout()), which differs only on a
  " page that straddles an offset-width change.
  let b:hexpair_page_hexstart   = s:HexStart(base)
  " Snapshotted like b:hexpair_n, and for the same reason: every mapping
  " between a line number and a byte offset counts on it.
  let b:hexpair_page_header     = g:hexpair_ruler ? 2 : 1

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
    if b:hexpair_page_header > 1
      call append(1, s:RulerLine(b:hexpair_page_hexstart, b:hexpair_n))
    endif
    call append(line('$'), b:hexpair_banner_bottom)
  finally
    let &l:undolevels = save_ul
  endtry

  " xxd runs through the shell, which can fail for reasons Vim never
  " reports - leaving an empty or short buffer presented as the page,
  " and a later :w patching that into the file. The dump's shape is
  " known exactly, so check it: one line per bytesperline bytes, plus the
  " header (banner, and the ruler when there is one) and the closing
  " banner.
  let expect = (len + b:hexpair_n - 1) / b:hexpair_n
        \ + b:hexpair_page_header + 1
  if line('$') != expect
    throw printf('hexpair: reading page %d of %s produced %d lines, '
          \ . 'expected %d - is xxd working?',
          \ a:pageidx + 1, b:hexpair_page_file, line('$'), expect)
  endif

  " The other file's bytes for THIS page, when there is one to compare
  " against; a page turn moves the window on both files at once.
  call s:LoadDiffHex()

  call cursor(1 + b:hexpair_page_header, b:hexpair_page_hexstart)
  call s:ClearModifiedHighlight()
  call s:ClearDiffHighlight()
  call s:ClearFindHighlight()
  call s:ClearMarkHighlight()
  " This window holds a view of its own - see s:WindowView().
  let w:hexpair_own_view = 1
  call s:Debug('page %d/%d loaded: bytes [%d, %d) of %d, %d lines',
        \ a:pageidx + 1, totalpages, base, base + len, total, line('$'))

  setlocal filetype=xxd
  call s:ApplyBannerSyntax()
  setlocal nomodified
  " A file this user cannot write is shown read-only, so :w says so at
  " once (E45) instead of at the end of an editing session, through a
  " failure from xxd naming a temp file. ':w!' still reaches the write
  " path and fails there the way the file system makes it fail - which
  " for a length-changing write is also where the recovery copy is kept.
  let &l:readonly = get(b:, 'hexpair_page_spill', '') ==# ''
        \ && !filewritable(b:hexpair_page_file)
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

" Name the scratch buffer a page lives in. The name is the file's, with a
" tag saying what it is - and a number on the tag when that name is
" already taken, which is what makes a SECOND view of the same file
" possible: two windows, two buffers, two pages, one file.
"
" The collision is detected by trying the name rather than by looking for
" it: Vim compares buffer names by rules of its own (a relative path and
" its absolute form can be the same buffer), and the only thing that
" knows all of them is the rename itself. E95 is the answer to "taken".
function! s:NamePageBuffer(file) abort
  let n = 1
  while n < 100
    let name = n == 1 ? a:file . ' [hexpair page]'
          \ : printf('%s [hexpair page #%d]', a:file, n)
    try
      silent execute 'file ' . fnameescape(name)
      return
    catch /E95/
      let n += 1
    endtry
  endwhile
  throw printf('hexpair: 99 views of %s are already open', a:file)
endfunction

function! s:Open(force, file, ...) abort
  " The page argument takes the same three forms |:HexPairPageGoto| does.
  " A step is counted from the first page, which is where opening starts:
  " "+2" is page 3, and "$" is the last one, without having to work out
  " how many there are.
  let parsed = HexPairPagedParsePageInput(a:0 > 0 ? a:1 : '')
  if has_key(parsed, 'msg')
    echohl ErrorMsg | echomsg parsed.msg | echohl None
    return
  endif
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
  let page = empty(parsed) ? 1 : HexPairPagedResolvePage(parsed, 1,
        \ HexPairPagedTotalPages(g:hexpair_page_size, getfsize(file)))
  if s:ResolvePage(file, g:hexpair_page_size, page - 1)[0] < 0
    return
  endif

  " Vim refuses to abandon a modified buffer, and ! is how that is
  " overridden everywhere else in Vim, so it is how it is overridden here.
  execute a:force ? 'enew!' : 'enew'
  call s:NamePageBuffer(a:file)
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
function! s:PagedByteIndexAt(lnum, col) abort
  let [n, hexstart, hexend, asciistart] = s:PagedLineLayout(a:lnum)
  let col = a:col
  if col <= hexend
    let idx = col < hexstart ? 0 : (col - hexstart) / 3
  else
    let idx = col < asciistart ? 0 : col - asciistart
    if idx >= n
      let idx = n - 1
    endif
  endif
  " Clamp to the bytes actually present on this (possibly short) line.
  let nbytes = strlen(getline(a:lnum)) - asciistart + 1
  if nbytes > n
    let nbytes = n
  endif
  if nbytes > 0 && idx >= nbytes
    let idx = nbytes - 1
  endif
  return idx
endfunction

function! s:PagedCursorByte() abort
  return s:PagedByteIndexAt(line('.'), col('.'))
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
function! s:PagedLineIndexAt(lnum, col) abort
  let line   = getline(a:lnum)
  let [n, hexstart, hexend, asciistart] = s:PagedLineLayout(a:lnum)
  " The offset column is not payload, and its digits are not bytes: a
  " cursor standing in it is on the line's FIRST byte, which is what the
  " column says. Without this the digits before the cursor get counted
  " like any others, so "00000200:" reads as four bytes of nothing.
  if a:col < hexstart
    return 0
  endif
  let prefix = strpart(line, 0, a:col - 1)
  if prefix =~# '  '
    return s:PagedByteIndexAt(a:lnum, a:col)
  endif
  let idx = s:PagedLineBytes(prefix)
  " Between the last hex digit and the ASCII column there is no double
  " space in the prefix yet, so the pairs counted there are the whole
  " line's - one past its last byte. Clamp to what the line holds, the
  " same way the layout branch above already does.
  let nbytes = s:PagedLineBytes(line)
  return nbytes > 0 && idx >= nbytes ? nbytes - 1 : idx
endfunction

" Complete bytes in the payload of one line (or of a prefix of one).
function! s:PagedLineBytes(text) abort
  return strlen(substitute(s:PagedPayload(a:text), '[^0-9a-fA-F]', '', 'g')) / 2
endfunction

function! s:PagedCursorLineIndex() abort
  return s:PagedLineIndexAt(line('.'), col('.'))
endfunction

" Absolute offset of the FIRST byte of a dump line.
"
" On a page nobody has edited, what is above the line needs no counting:
" the page is exactly what xxd produced, so dump line k holds bytes k * n
" and the walk can be skipped entirely. That is what keeps a write and
" |:HexPairPages| off a second pass over the page - the cursor byte is
" reported after every write, and on the default page size counting it
" costs as much as the write itself. Once the page has been edited, only
" the digits actually on the lines above say where a line starts.
function! s:PagedLineBase(lnum) abort
  return !&l:modified
        \ ? b:hexpair_page_base + (a:lnum - 1 - s:HeaderLines()) * b:hexpair_n
        \ : b:hexpair_page_base + s:PagedScan(a:lnum).bytes
endfunction

" Absolute offset of the byte at a position in the hex view. The
" WITHIN-line part goes through s:PagedLineIndexAt() whichever way the
" line base was found, so the two cannot drift apart in how they read a
" line - only in how they count the lines above it, which is arithmetic
" exactly while the page is canonical.
function! s:PagedOffsetAt(lnum, col) abort
  return s:PagedLineBase(a:lnum) + s:PagedLineIndexAt(a:lnum, a:col)
endfunction

function! s:PagedByteOffset() abort
  if s:IsBannerLine(getline('.'))
    return b:hexpair_page_base
  endif
  let off = s:PagedOffsetAt(line('.'), col('.'))
  call s:Debug('hex view line %d, column %d -> byte %d (page base %d%s)',
        \ line('.'), col('.'), off, b:hexpair_page_base,
        \ &l:modified ? ', counted' : ', unedited page')
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
  call cursor(rel / n + 1 + s:HeaderLines(), hexstart + (rel % n) * 3)
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

" A fingerprint of the bytes this page covers, as they are on disk right
" now. Size and mtime are what a portable Vim can see about a file, and
" mtime has a one-second resolution, so a change made within the same
" second as the read AND of exactly the same size is invisible to them -
" and a write would then patch this page over someone else's bytes. This
" reads the page's own bytes back and hashes them, which closes that for
" the range being written, at the cost of one page read (hundredths of a
" second, independent of the size of the file).
"
" Empty when the local Vim has no sha256() (a build without +cryptv) or
" when reading the page fails, in which case the size and mtime check
" stands alone - a weaker guard, never a wrong one.
" A byte range of any file, as one flat run of lowercase hex. Empty when
" the read fails or the range is empty - every caller treats that as
" "cannot tell", never as "no bytes". The range may run past the end of
" the file, in which case what comes back is what there was.
function! s:FileHex(file, off, len) abort
  if a:len <= 0
    return ''
  endif
  try
    let out = s:Run(printf('%s -p -s %d -l %d %s', s:xxd, a:off, a:len,
          \ shellescape(a:file)))
    " xxd -p prints hex and line breaks and nothing else, so the line
    " breaks are all there is to remove - the CR because a Windows xxd
    " ends its lines with one. Two passes over a single character each,
    " rather than one over a collection: measured on the 2 MB of hex a
    " 1 MiB block comes to, 16 ms against 51 ms, and a scan of a large
    " file is thousands of those.
    return substitute(substitute(out, '\n', '', 'g'), '\r', '', 'g')
  catch
    return ''
  endtry
endfunction

function! s:PageHex(base, len) abort
  return s:FileHex(b:hexpair_page_file, a:base, a:len)
endfunction

function! s:PageDigest(base, len) abort
  if !exists('*sha256')
    return ''
  endif
  let hex = s:PageHex(a:base, a:len)
  return hex ==# '' ? '' : sha256(hex)
endfunction

" Refuse to touch a file that changed underneath us.
"
" What matters is not that the FILE changed but that THIS PAGE did: a
" second view of the same file, patching a different page of it, changes
" the file's modification time without touching a byte this view holds -
" and that is a thing to allow, not to refuse, or two views of one file
" could not both be written (|hexpair-two-views|). So the size decides
" first, because a different length moves every page after the change;
" then the page's own bytes decide, by the hash taken when it was read.
"
" The modification time is only the fallback for a Vim without sha256():
" it is the weaker guard - it cannot see a change made within the same
" second - and it is also the one that cannot tell a change to this page
" from a change to the rest of the file.
function! s:CheckFresh() abort
  let total = getfsize(b:hexpair_page_file)
  if total != b:hexpair_page_total
    throw printf('hexpair: %s changed on disk since the page was read '
          \ . '(size %d -> %d); nothing was written - reload it with '
          \ . ':HexPairPageGoto! %d',
          \ b:hexpair_page_file, b:hexpair_page_total, total,
          \ b:hexpair_page_index + 1)
  endif

  let digest = get(b:, 'hexpair_page_digest', '')
  let now = digest ==# ''
        \ ? '' : s:PageDigest(b:hexpair_page_base, b:hexpair_page_len)
  if now ==# ''
    if getftime(b:hexpair_page_file) == b:hexpair_page_ftime
      return
    endif
    throw printf('hexpair: %s changed on disk since page %d was read; '
          \ . 'nothing was written - reload it with :HexPairPageGoto! %d',
          \ b:hexpair_page_file, b:hexpair_page_index + 1,
          \ b:hexpair_page_index + 1)
  endif
  if now !=# digest
    throw printf('hexpair: the bytes of page %d of %s are no longer the '
          \ . 'ones that were read, though the file is still %d bytes '
          \ . 'long - something else wrote to this page; nothing was '
          \ . 'written here - reload it with :HexPairPageGoto! %d',
          \ b:hexpair_page_index + 1, b:hexpair_page_file, total,
          \ b:hexpair_page_index + 1)
  endif
  " The page is intact; the file may still have changed elsewhere, so the
  " timestamp is adopted rather than left to look stale next time.
  let b:hexpair_page_ftime = getftime(b:hexpair_page_file)
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
  let b:hexpair_page_digest     = ''
  let b:hexpair_page_hex        = ''
  let b:hexpair_n               = g:hexpair_bytes_per_line
  let b:hexpair_page_hexstart   = s:HexStart(0)
  " No dump lines to number, so no ruler whatever the option says.
  let b:hexpair_page_header     = 1
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
  let w:hexpair_own_view = 1
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
  let idx = lnum - 1 - s:HeaderLines()
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
    let off = s:PosOffset(get(b:, 'hexpair_last_pos',
          \ [1 + s:HeaderLines(), 1]))
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
  if s:LoadPageInView(a:pageidx)
    call s:BindPageTurn(b:hexpair_page_base)
  endif
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
  if a:text ==# '$'
    return {'last': 1}
  endif
  if a:text =~# '^[+-]\d\+$'
    " str2nr() is not asked to make sense of a leading '+'.
    return {'delta': str2nr(a:text[1:]) * (a:text[0] ==# '-' ? -1 : 1)}
  endif
  if a:text !~# '^\d\+$'
    return {'msg': 'hexpair: not a page number: ' . a:text
          \ . ' (a page, +N or -N to step, $ for the last)'}
  endif
  return {'page': str2nr(a:text)}
endfunction

" The 1-based page a parsed input names, given where the view is now.
" Not range-checked here: s:LoadPage()'s HexPairPagedBounds() check
" already reports a page that does not exist, in the same words whether
" it was asked for as a number, a step or a $.
function! HexPairPagedResolvePage(parsed, current, totalpages) abort
  if has_key(a:parsed, 'last')
    return a:totalpages
  endif
  if has_key(a:parsed, 'delta')
    return a:current + a:parsed.delta
  endif
  return get(a:parsed, 'page', 0)
endfunction

" :HexPairPageGoto's argument, and the same text typed at the prompt.
function! s:PageGotoText(text, force) abort
  if !s:RequirePaged()
    return
  endif
  let parsed = HexPairPagedParsePageInput(a:text)
  if has_key(parsed, 'msg')
    echohl ErrorMsg
    echomsg parsed.msg
    echohl None
    return
  endif
  if empty(parsed)
    return
  endif
  call s:GotoPage(HexPairPagedResolvePage(parsed, b:hexpair_page_index + 1,
        \ b:hexpair_page_totalpages) - 1, a:force)
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
  let n = input(printf('hexpair: goto page (1-%d, +N/-N, $): ',
        \ b:hexpair_page_totalpages))
  redraw
  call s:PageGotoText(n, a:force)
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

" ---------------------------------------------------------------------------
" What a Visual selection covers
" ---------------------------------------------------------------------------

" The bytes a selection covers: {'first', 'last', 'count', 'lines',
" 'perline'} in absolute file offsets, or {} when it covers none (a
" selection of banner lines alone). 'perline' is 0 unless the selection is
" blockwise, where the bytes are not one run and the count is what matters.
"
" Global and parameterized by the two ends and the mode rather than
" reading them itself, for the reason |HexPairPagedSelectionPositions()|
" gives: Visual mode cannot be driven under this project's `vim -es`
" harness, so the geometry has to be callable without it.
function! HexPairPagedSelectionBytes(vpos, cpos, mode) abort
  let forward = a:vpos[1] < a:cpos[1]
        \ || (a:vpos[1] == a:cpos[1] && a:vpos[2] <= a:cpos[2])
  let [head, tail] = forward ? [a:vpos, a:cpos] : [a:cpos, a:vpos]
  let sel = s:IsHexView()
        \ ? s:HexSelectionBytes(head, tail, a:mode)
        \ : s:TextSelectionBytes(head, tail, a:mode)
  if empty(sel)
    return {}
  endif
  " Nothing may be reported outside the page: a linewise selection of the
  " last line takes in a line break the page may not have, and a blockwise
  " one can reach past the bytes a short line holds.
  let last = b:hexpair_page_base + b:hexpair_page_len - 1
  let sel.first = sel.first < b:hexpair_page_base ? b:hexpair_page_base : sel.first
  let sel.last  = sel.last > last ? last : sel.last
  return sel
endfunction

" Bytes on one dump line: the index of its first and last, or [] if it
" holds none (a banner line, or an empty one the user inserted).
function! s:HexLineBytes(lnum) abort
  if s:IsBannerLine(getline(a:lnum))
    return []
  endif
  let n = s:PagedLineBytes(getline(a:lnum))
  return n > 0 ? [0, n - 1] : []
endfunction

function! s:HexSelectionBytes(head, tail, mode) abort
  let block = a:mode ==# "\<C-V>"
  let [locol, hicol] = [min([a:head[2], a:tail[2]]), max([a:head[2], a:tail[2]])]
  let [first, last, nbytes, lines, perline] = [-1, -1, 0, 0, 0]
  for lnum in range(a:head[1], a:tail[1])
    let ends = s:HexLineBytes(lnum)
    if empty(ends)
      continue
    endif
    if block
      let lo = s:PagedByteIndexAt(lnum, locol)
      let hi = s:PagedByteIndexAt(lnum, hicol)
    elseif a:mode ==# 'V'
      let [lo, hi] = ends
    else
      let lo = lnum == a:head[1] ? s:PagedLineIndexAt(lnum, a:head[2]) : ends[0]
      let hi = lnum == a:tail[1] ? s:PagedLineIndexAt(lnum, a:tail[2]) : ends[1]
    endif
    let lo = lo < ends[0] ? ends[0] : lo
    let hi = hi > ends[1] ? ends[1] : hi
    if hi < lo
      continue
    endif
    let base = s:PagedLineBase(lnum)
    let first = first < 0 ? base + lo : first
    let last = base + hi
    let nbytes += hi - lo + 1
    let lines += 1
    let perline = hi - lo + 1
  endfor
  return lines == 0 ? {}
        \ : {'first': first, 'last': last, 'count': nbytes,
        \    'lines': lines, 'perline': block ? perline : 0}
endfunction

" The text view: a column IS a byte, so the ends map straight through -
" except blockwise, where the same column range is taken from every line.
function! s:TextSelectionBytes(head, tail, mode) abort
  let [firstline, lastline] = s:TextBodyRange()
  let head = a:head[1] < firstline ? firstline : a:head[1]
  let tail = a:tail[1] > lastline ? lastline : a:tail[1]
  if tail < head
    return {}
  endif
  if a:mode ==# "\<C-V>"
    let [locol, hicol] = [min([a:head[2], a:tail[2]]), max([a:head[2], a:tail[2]])]
    let [first, last, nbytes, lines] = [-1, -1, 0, 0]
    for lnum in range(head, tail)
      let len = strlen(getline(lnum))
      let hi = hicol > len ? len : hicol
      if len == 0 || locol > len
        continue
      endif
      let first = first < 0 ? s:TextOffsetAt(lnum, locol) : first
      let last = s:TextOffsetAt(lnum, hi)
      let nbytes += hi - locol + 1
      let lines += 1
    endfor
    return lines == 0 ? {}
          \ : {'first': first, 'last': last, 'count': nbytes,
          \    'lines': lines, 'perline': hicol - locol + 1}
  endif
  " Charwise and linewise are one run of bytes. A linewise selection
  " takes in the line break that ends each line, which in a page of raw
  " bytes is a byte like any other.
  let [locol, hicol] = a:mode ==# 'V'
        \ ? [1, strlen(getline(tail)) + 1]
        \ : [a:head[2], a:tail[2]]
  let first = s:TextOffsetAt(head, locol)
  let last  = s:TextOffsetAt(tail, hicol)
  return {'first': first, 'last': last, 'count': last - first + 1,
        \ 'lines': tail - head + 1, 'perline': 0}
endfunction

" What |:HexPairSelection| says. 1-based and inclusive like the banner and
" |:HexPairPages|, so the numbers can be typed straight into
" |:HexPairGoOffset|. Pure, so the wording is testable without Visual mode.
function! HexPairPagedSelectionText(sel, total) abort
  if empty(a:sel)
    return 'hexpair: the selection covers no bytes'
  endif
  let where = printf('%d-%d (0x%x-0x%x) of %d',
        \ a:sel.first + 1, a:sel.last + 1, a:sel.first + 1, a:sel.last + 1,
        \ a:total)
  if a:sel.perline > 0
    return printf('hexpair: %d bytes selected in %d lines (%d per line), %s',
          \ a:sel.count, a:sel.lines, a:sel.perline, where)
  endif
  return printf('hexpair: %d byte%s selected, %s',
        \ a:sel.count, a:sel.count == 1 ? '' : 's', where)
endfunction

" a:reselect puts the Visual selection back before saying anything about
" it: the report has to be asked for from the command line, which ends
" Visual mode, and losing the selection to look at it is not a trade
" worth making. The gv comes first and the message last, so the message
" is what stays on the screen rather than "-- VISUAL --".
function! s:Selection(...) abort
  if !s:RequirePaged()
    return
  endif
  let sel = b:hexpair_page_len > 0
        \ ? HexPairPagedSelectionBytes(getpos("'<"), getpos("'>"), visualmode())
        \ : {}
  let text = b:hexpair_page_len > 0
        \ ? HexPairPagedSelectionText(sel, b:hexpair_page_total)
        \ : 'hexpair: this page holds no bytes'
  if !(a:0 && a:1)
    echo text
    return
  endif
  " Back into Visual mode with the selection this reported on - and Vim
  " draws its own "-- VISUAL --" over the message line the moment it gets
  " there, which is why the report used to flash past and vanish. A
  " message of more than one line gets Vim's hit-enter prompt instead, so
  " it stays until it has been read; the selection is still there after
  " the Enter. (Checked in a real terminal - see CLAUDE.md; what the
  " message line ends up showing is not observable from inside Vim.)
  normal! gv
  echo text . "\n"
endfunction

" ---------------------------------------------------------------------------
" Data inspector
" ---------------------------------------------------------------------------
"
" The bytes at the cursor read as the numbers they could be: 8, 16, 32 and
" 64 bits wide, unsigned and signed, little- and big-endian, plus the two
" IEEE 754 floats. What every hex editor calls a data inspector, and what
" a hex dump on its own cannot tell you.
"
" The bytes come from THIS PAGE as the buffer holds it - edits included -
" and stop at its end, so near the boundary there may be fewer than eight
" and the wider rows say so rather than reaching into a page that is not
" on screen.

" Bytes from the cursor onward, at most a:count of them, as a list of
" values. In the hex view they are read out of the payload digits, line by
" line for as long as more are needed; in the text view they are the
" buffer's own bytes, taken through writefile(..., 'b'), which is the one
" way to get them out of a Vim string exactly (a NUL is held as a NL
" inside a line, and only that round trip puts it back).
function! s:InspectBytes(count) abort
  let out = []
  if s:IsHexView()
    if s:IsBannerLine(getline('.'))
      return []
    endif
    let lnum = line('.')
    let digits = strpart(s:PagedLineDigits(getline(lnum)),
          \ s:PagedLineIndexAt(lnum, col('.')) * 2)
    while strlen(digits) < a:count * 2 && lnum < line('$')
      let lnum += 1
      let digits .= s:PagedLineDigits(getline(lnum))
    endwhile
    let i = 0
    while i + 1 < strlen(digits) && len(out) < a:count
      call add(out, str2nr(strpart(digits, i, 2), 16))
      let i += 2
    endwhile
    return out
  endif

  " Text view: cut the lines the bytes fall on out of the buffer, write
  " just those, and let xxd say what they are.
  let [first, last] = s:TextBodyRange()
  let lnum = line('.') < first ? first : (line('.') > last ? last : line('.'))
  let lines = [strpart(getline(lnum), col('.') - 1)]
  " A line break is a byte too, so each further line adds one plus its
  " own length; a:count of them is always enough.
  let extra = lnum
  while extra < last && strlen(join(lines, ' ')) < a:count
    let extra += 1
    call add(lines, getline(extra))
  endwhile
  let raw = tempname()
  try
    call writefile(lines, raw, 'b')
    let hex = substitute(s:Run(printf('%s -p -l %d %s', s:xxd, a:count,
          \ shellescape(raw))), '[^0-9a-fA-F]', '', 'g')
  finally
    call delete(raw)
  endtry
  let i = 0
  while i + 1 < strlen(hex)
    call add(out, str2nr(strpart(hex, i, 2), 16))
    let i += 2
  endwhile
  return out
endfunction

" The hex digits of one dump line's payload, without the spaces.
function! s:PagedLineDigits(line) abort
  return substitute(s:PagedPayload(a:line), '[^0-9a-fA-F]', '', 'g')
endfunction

" The bit pattern of a:bytes, most significant first, as a Number. For
" eight bytes this is already the signed 64-bit value: the arithmetic
" wraps exactly as two's complement does, which is why the unsigned form
" of that width goes through HexPairPagedU64Text().
function! s:PatternOf(bytes) abort
  let v = 0
  for b in a:bytes
    let v = v * 256 + b
  endfor
  return v
endfunction

" a - b for two non-negative decimal strings with a >= b. Pure, and the
" only way to print the unsigned value of a 64-bit pattern whose top bit
" is set: Vim's Number is signed, so 2^64 + n has to be done in decimal.
function! HexPairPagedDecSub(a, b) abort
  let b = repeat('0', strlen(a:a) - strlen(a:b)) . a:b
  let out = ''
  let borrow = 0
  let i = strlen(a:a) - 1
  while i >= 0
    let d = str2nr(a:a[i]) - str2nr(b[i]) - borrow
    let borrow = d < 0 ? 1 : 0
    let out = (d < 0 ? d + 10 : d) . out
    let i -= 1
  endwhile
  return substitute(out, '^0\+\ze\d', '', '')
endfunction

" The unsigned decimal of a 64-bit pattern held in a signed Number.
function! HexPairPagedU64Text(n) abort
  return a:n >= 0 ? string(a:n)
        \ : HexPairPagedDecSub('18446744073709551616', string(a:n)[1:])
endfunction

" IEEE 754 from a:bytes, most significant first: four bytes are a
" binary32, eight a binary64. Done on the bytes rather than on a bit
" pattern in a Number so nothing depends on how wide a Number is, and
" with the mantissa carried as a Float, which holds 53 bits exactly - one
" more than a binary64 needs.
function! HexPairPagedIeeeText(bytes) abort
  let w = len(a:bytes)
  if w != 4 && w != 8
    return '-'
  endif
  if !has('float')
    return '(needs +float)'
  endif
  let expbits  = w == 4 ? 8 : 11
  let mantbits = w == 4 ? 23 : 52
  let bias     = w == 4 ? 127 : 1023
  let maxexp   = w == 4 ? 255 : 2047
  let sign     = a:bytes[0] >= 128 ? -1.0 : 1.0
  " The exponent straddles the first two bytes: seven bits are left in
  " byte 0 once the sign is off it, and the rest comes off the top of
  " byte 1.
  let inbyte1 = expbits - 7
  let exp = (a:bytes[0] % 128) * float2nr(pow(2, inbyte1))
        \ + a:bytes[1] / float2nr(pow(2, 8 - inbyte1))
  let mant = (a:bytes[1] % float2nr(pow(2, 8 - inbyte1))) * 1.0
  for b in a:bytes[2:]
    let mant = mant * 256.0 + b
  endfor
  if exp == maxexp
    return mant != 0.0 ? 'nan' : (sign < 0 ? '-inf' : 'inf')
  endif
  let frac = mant / pow(2, mantbits)
  let value = exp == 0
        \ ? sign * frac * pow(2, 1 - bias)
        \ : sign * (1.0 + frac) * pow(2, exp - bias)
  return printf('%g', value)
endfunction

" A code point, as the inspector prints one: the number, the character
" itself where it can be shown, and how many bytes it took.
"
" The glyph is left out for anything with none to show: below a space,
" the C1 range, and the private use areas, where whatever appears means
" nothing without the font that was meant to come with it - and on a Vim
" whose 'encoding' is not utf-8, for every code point, because there it
" cannot be built at all: nr2char(cp, 1) is documented to give the utf-8
" form, and on a latin1 Vim it hands back ONE byte - U+4241 comes out as
" "A", the low half of the number (measured). A wrong character is worse
" than none, and a Vim with a codepage 'encoding' - which is what Windows
" starts with - could not draw the right one anyway.
function! s:CodePointText(cp, used) abort
  let glyph = ''
  if &encoding ==# 'utf-8' && a:cp >= 0x20
        \ && !(a:cp >= 0x7f && a:cp <= 0xa0)
        \ && !(a:cp >= 0xe000 && a:cp <= 0xf8ff)
        \ && !(a:cp >= 0xf0000 && a:cp <= 0x10fffd)
    let glyph = " '" . nr2char(a:cp, 1) . "'"
  endif
  return a:used > 0
        \ ? printf('U+%04X%s (%d byte%s)', a:cp, glyph, a:used,
        \          a:used == 1 ? '' : 's')
        \ : printf('U+%04X%s', a:cp, glyph)
endfunction

function! s:NeedsBytes(want, have) abort
  return printf('needs %d bytes, %d left', a:want, a:have)
endfunction

" What the bytes at the cursor are as UTF-8. Every way the encoding can
" be wrong is a different answer, because a data inspector that reported
" a code point for an overlong sequence or a surrogate would be inventing
" one: those byte sequences are not characters at all.
function! HexPairPagedUtf8Text(bytes) abort
  if empty(a:bytes)
    return '-'
  endif
  let b0 = a:bytes[0]
  if b0 < 0x80
    return s:CodePointText(b0, 1)
  endif
  " 0x80-0xbf is a continuation byte with nothing in front of it, and
  " 0xc0/0xc1 could only ever start an overlong two-byte sequence.
  if b0 < 0xc2 || b0 > 0xf4
    return 'not utf-8 (byte ' . printf('%02x', b0) . ' cannot start one)'
  endif
  let want = b0 < 0xe0 ? 2 : (b0 < 0xf0 ? 3 : 4)
  if len(a:bytes) < want
    return s:NeedsBytes(want, len(a:bytes))
  endif
  let cp = b0 % (want == 2 ? 32 : (want == 3 ? 16 : 8))
  let i = 1
  while i < want
    let b = a:bytes[i]
    if b / 64 != 2
      return 'not utf-8 (byte ' . printf('%02x', b) . ' is not a continuation)'
    endif
    let cp = cp * 64 + b % 64
    let i += 1
  endwhile
  " An overlong sequence spells a code point that a shorter one already
  " spells, and is not that character however it looks.
  let least = want == 2 ? 0x80 : (want == 3 ? 0x800 : 0x10000)
  if cp < least
    return printf('not utf-8 (overlong: U+%04X in %d bytes)', cp, want)
  endif
  if cp >= 0xd800 && cp <= 0xdfff
    return printf('not utf-8 (U+%04X is a surrogate)', cp)
  endif
  if cp > 0x10ffff
    return printf('not utf-8 (U+%04X is past the last code point)', cp)
  endif
  return s:CodePointText(cp, want)
endfunction

" The same as UTF-16, in the byte order a:little asks for. A high
" surrogate takes the next unit with it; a lone one is not a character.
function! HexPairPagedUtf16Text(bytes, little) abort
  if len(a:bytes) < 2
    return s:NeedsBytes(2, len(a:bytes))
  endif
  let unit = a:little ? a:bytes[1] * 256 + a:bytes[0]
        \             : a:bytes[0] * 256 + a:bytes[1]
  if unit >= 0xdc00 && unit <= 0xdfff
    return printf('U+%04X - a low surrogate, nothing before it', unit)
  endif
  if unit < 0xd800 || unit > 0xdbff
    return s:CodePointText(unit, 2)
  endif
  if len(a:bytes) < 4
    return s:NeedsBytes(4, len(a:bytes))
  endif
  let low = a:little ? a:bytes[3] * 256 + a:bytes[2]
        \            : a:bytes[2] * 256 + a:bytes[3]
  if low < 0xdc00 || low > 0xdfff
    return printf('U+%04X - a high surrogate, U+%04X is not low',
          \ unit, low)
  endif
  return s:CodePointText(0x10000 + (unit - 0xd800) * 0x400 + (low - 0xdc00), 4)
endfunction

" And as UTF-32, where every four bytes are one code point - or are not a
" character at all, which is most of them.
function! HexPairPagedUtf32Text(bytes, little) abort
  if len(a:bytes) < 4
    return s:NeedsBytes(4, len(a:bytes))
  endif
  let b = a:little ? reverse(copy(a:bytes[0:3])) : a:bytes[0:3]
  let cp = ((b[0] * 256 + b[1]) * 256 + b[2]) * 256 + b[3]
  if cp > 0x10ffff
    return printf('U+%04X - past U+10FFFF', cp)
  endif
  if cp >= 0xd800 && cp <= 0xdfff
    return printf('U+%04X - a surrogate', cp)
  endif
  return s:CodePointText(cp, 0)
endfunction

" A byte as eight bits. printf() has no %b on the Vim this plugin
" supports, so the bits are spelled out.
function! HexPairPagedBinaryText(byte) abort
  let out = ''
  let bit = 128
  while bit > 0
    let out .= a:byte / bit % 2
    let bit = bit / 2
  endwhile
  return out
endfunction

" One cell of the table: the unsigned value, and the signed one after it
" when the two differ - which they do exactly when the top bit is set.
function! s:IntCell(bytes) abort
  let w = len(a:bytes)
  let pattern = s:PatternOf(a:bytes)
  if w >= 8
    let unsigned = HexPairPagedU64Text(pattern)
    let signed = string(pattern)
  else
    let half = float2nr(pow(2, w * 8 - 1))
    let unsigned = string(pattern)
    let signed = string(pattern >= half ? pattern - half * 2 : pattern)
  endif
  return unsigned ==# signed ? unsigned : unsigned . ' / ' . signed
endfunction

" The whole report, as lines. Pure: it is handed the bytes and where they
" are, so every conversion in it is testable without a buffer.
function! HexPairPagedInspectLines(bytes, at, total) abort
  if empty(a:bytes)
    return ['hexpair: no byte here to read']
  endif
  let hex = []
  for b in a:bytes
    call add(hex, printf('%02x', b))
  endfor
  let head = printf('hexpair: byte %d (0x%x) of %d: %s',
        \ a:at, a:at, a:total, join(hex, ' '))
  let byte = a:bytes[0]
  let out = [head]
  call add(out, printf('  8-bit    %-26s  char %s  bin %s  oct 0%o',
        \ s:IntCell(a:bytes[0:0]),
        \ byte >= 0x20 && byte < 0x7f ? "'" . nr2char(byte) . "'" : ' - ',
        \ HexPairPagedBinaryText(byte), byte))
  call add(out, printf('  %-8s %-26s  %s', '', 'little-endian', 'big-endian'))
  " Widths beyond 32 bits need a Vim whose Number is 64 bits wide; the
  " rows are left out rather than shown wrong where it is not.
  for w in has('num64') ? [2, 4, 8] : [2]
    let name = printf('%d-bit', w * 8)
    if len(a:bytes) < w
      call add(out, printf('  %-8s %-26s  %s', name,
            \ printf('(only %d byte%s left on this page)', len(a:bytes),
            \        len(a:bytes) == 1 ? '' : 's'), ''))
      continue
    endif
    let be = a:bytes[0 : w - 1]
    let le = reverse(copy(be))
    call add(out, printf('  %-8s %-26s  %s', name, s:IntCell(le), s:IntCell(be)))
  endfor
  for w in [4, 8]
    let name = w == 4 ? 'float32' : 'float64'
    if len(a:bytes) < w
      continue
    endif
    let be = a:bytes[0 : w - 1]
    let le = reverse(copy(be))
    call add(out, printf('  %-8s %-26s  %s', name,
          \ HexPairPagedIeeeText(le), HexPairPagedIeeeText(be)))
  endfor
  " What the bytes are as text. UTF-8 has no byte order to get wrong, so
  " it takes the width of both columns; the other two are read each way
  " round like the numbers above them.
  call add(out, printf('  %-8s %s', 'utf-8', HexPairPagedUtf8Text(a:bytes)))
  call add(out, printf('  %-8s %-26s  %s', 'utf-16',
        \ HexPairPagedUtf16Text(a:bytes, 1), HexPairPagedUtf16Text(a:bytes, 0)))
  call add(out, printf('  %-8s %-26s  %s', 'utf-32',
        \ HexPairPagedUtf32Text(a:bytes, 1), HexPairPagedUtf32Text(a:bytes, 0)))
  if !has('num64')
    call add(out, '  (32- and 64-bit values need a Vim with +num64)')
  endif
  " The columns are padded to line up; a row whose right-hand cell is
  " empty must not carry that padding into the message area.
  return map(out, "substitute(v:val, '\\s\\+$', '', '')")
endfunction

function! s:Inspect() abort
  if !s:RequirePaged()
    return
  endif
  if b:hexpair_page_len <= 0
    echo 'hexpair: this page holds no bytes'
    return
  endif
  let bytes = s:InspectBytes(8)
  let at = empty(bytes) ? 0 :
        \ (s:IsHexView() ? s:PagedByteOffset() : s:TextByteOffset()) + 1
  for line in HexPairPagedInspectLines(bytes, at, b:hexpair_page_total)
    echo line
  endfor
endfunction

" ---------------------------------------------------------------------------
" Statusline
" ---------------------------------------------------------------------------

" A compact summary for 'statusline', e.g. "hex 3/349 @0x50a01" - the
" view, the page, and the byte under the cursor in the form
" |:HexPairGoOffset| and vimhex's @BYTE both take. Empty for every buffer
" hexpair has not touched, so it can sit in the statusline unconditionally:
"
"     set statusline=%f\ %h%w%m%r\ %{HexPairStatus()}%=%l,%c%V\ %P
"
" The statusline is evaluated on every cursor movement, so this must never
" walk the page: the byte comes from the canonical layout in the hex view
" and from line2byte() in the text one, both constant-time. On a page with
" unwritten edits that is where the byte WAS - inserting or deleting hex
" digits above the cursor shifts what follows - so such a page is marked
" with a "+" and |:HexPairPages|, which counts the digits actually there,
" is the one to ask for the exact answer.
function! HexPairStatus() abort
  if !get(b:, 'hexpair_page_active', 0)
    return ''
  endif
  let view = s:IsHexView() ? 'hex' : 'txt'
  if b:hexpair_page_totalpages == 0
    return view . ' 0/0'
  endif
  let where = printf('%s %d/%d%s', view, b:hexpair_page_index + 1,
        \ b:hexpair_page_totalpages, &l:modified ? '+' : '')
  if s:IsHexView() && s:IsBannerLine(getline('.'))
    return where
  endif
  let at = s:IsHexView()
        \ ? b:hexpair_page_base
        \   + (line('.') - 1 - s:HeaderLines()) * b:hexpair_n
        \   + s:PagedCursorLineIndex()
        \ : s:TextByteOffset()
  " Both bases, as |:HexPairPages| and the inspector give them: hex is
  " what the dump's own offset column speaks, decimal is what everything
  " else does.
  return printf('%s @0x%x (%d)', where, at + 1, at + 1)
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
  let text = input(printf('hexpair: goto byte (1-%d, or +N/-N from here): ',
        \ b:hexpair_page_total))
  redraw
  if !empty(text)
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
  " A leading + or - makes it a step from the byte the cursor is on
  " rather than a position in the file, which is the only form where 0
  " means something ("stay here") and where the 1-based/0-based question
  " does not arise at all.
  let sign = a:text[0] ==# '+' ? 1 : (a:text[0] ==# '-' ? -1 : 0)
  let text = sign ? a:text[1:] : a:text
  " Decimal, or hex with the 0x on it: a bare "ff" is not read as either,
  " because str2nr() would take it for the decimal 0 and the complaint
  " ("byte positions start at 1") would be about the wrong thing.
  if text !~# '^\%(0[xX]\x\+\|\d\+\)$'
    return {'msg': printf('hexpair: not a byte position: %s (decimal, or '
          \ . '0x for hex; byte 1 is the first, +N and -N step from here)',
          \ string(a:text))}
  endif
  let n = text =~# '^0[xX]' ? str2nr(text[2:], 16) : str2nr(text)
  if sign
    return {'delta': sign * n}
  endif
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
    if has_key(parsed, 'delta')
      " A step is from the byte the cursor is on, so it needs no page
      " arithmetic of its own - it becomes a position and takes the same
      " road as one, including the check that it is inside the file.
      let here = s:IsHexView() ? s:PagedByteOffset() : s:TextByteOffset()
      let parsed = {'offset': here + parsed.delta}
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

" ---------------------------------------------------------------------------
" Finding bytes, and replacing them
" ---------------------------------------------------------------------------
"
" |/| searches the page on screen, which is a window on the file - so it
" cannot find what is on any other page, and searching a dump for a
" sequence of bytes means matching text that has spaces, line breaks and
" an ASCII column in the middle of it. |:HexPairFind| searches the FILE
" instead, a block at a time, and lands the cursor on the byte it found,
" turning the page on the way.
"
" What is searched is the file on disk. Unwritten edits are on the screen,
" where |/| and the eye can find them; everywhere else, the file is what
" there is to search.

let s:find = {'hex': '', 'bytes': 0, 'what': ''}

" A pattern is bytes, two hex digits each, and a '?' stands for any
" nibble: "de ad be ef", "deadbeef" and "de ?? be ef" are all patterns,
" and spaces between the bytes are decoration. What comes back is the
" regexp that matches it in a run of hex, which is the same string with
" the wildcards turned into '.'.
function! HexPairPagedParseFindPattern(text) abort
  let squashed = substitute(a:text, '\s\+', '', 'g')
  if squashed ==# ''
    return {'msg': 'hexpair: nothing to find'}
  endif
  if squashed =~# '[^0-9a-fA-F?]'
    return {'msg': printf('hexpair: %s is not a byte pattern (hex digits, '
          \ . '? for any nibble)', string(a:text))}
  endif
  if strlen(squashed) % 2
    return {'msg': printf('hexpair: %s is %d hex digits - a byte is two, '
          \ . 'so a pattern is an even number of them',
          \ string(a:text), strlen(squashed))}
  endif
  return {'hex': tolower(substitute(squashed, '?', '.', 'g')),
        \ 'bytes': strlen(squashed) / 2}
endfunction

" The bytes of a literal string, as hex - what |:HexPairFindText| searches
" for. The string is taken as the bytes Vim holds it as, so what it finds
" is what the same text would look like in the file.
function! HexPairPagedTextToHex(text) abort
  let out = ''
  let i = 0
  while i < strlen(a:text)
    let out .= printf('%02x', char2nr(strpart(a:text, i, 1)))
    let i += 1
  endwhile
  return out
endfunction

" Where a:pat matches in a run of hex, at or after a:from, on a BYTE
" boundary - an index into a hex string is a nibble, and half of them are
" the wrong half. Backwards, it is the last match that starts before
" a:from.
function! HexPairPagedFindInHex(hay, pat, from, forward) abort
  if a:forward
    let at = a:from
    while 1
      let idx = match(a:hay, a:pat, at)
      if idx < 0
        return -1
      endif
      if idx % 2 == 0
        return idx
      endif
      let at = idx + 1
    endwhile
  endif
  let best = -1
  let at = 0
  while 1
    let idx = match(a:hay, a:pat, at)
    if idx < 0 || idx >= a:from
      return best
    endif
    if idx % 2 == 0
      let best = idx
    endif
    let at = idx + 1
  endwhile
endfunction

" The file, a block at a time, for the next (or previous) match. Blocks
" overlap by the pattern's length less one byte, so a match lying across
" a seam is still whole in one of them.
function! s:FindScan(from, forward) abort
  let file = b:hexpair_page_file
  let total = b:hexpair_page_total
  let pat = s:find.hex
  let span = s:find.bytes - 1
  if a:forward
    let off = a:from
    while off < total
      call s:Progress('searching', off, total)
      let len = s:diffblock < total - off ? s:diffblock : total - off
      let idx = HexPairPagedFindInHex(s:FileHex(file, off, len), pat, 0, 1)
      if idx >= 0
        return off + idx / 2
      endif
      if len < s:diffblock
        return -1
      endif
      let off += len - span
    endwhile
    return -1
  endif
  let end = a:from
  while end > 0
    call s:Progress('searching back', total - end, total)
    let start = end - s:diffblock
    let start = start < 0 ? 0 : start
    " Read past the block's end by the pattern's span, so a match that
    " starts inside it and reaches beyond is found whole.
    let hex = s:FileHex(file, start, end - start + span)
    let idx = HexPairPagedFindInHex(hex, pat, (end - start) * 2, 0)
    if idx >= 0
      return start + idx / 2
    endif
    let end = start
  endwhile
  return -1
endfunction

" Matches of the current pattern, as matchaddpos() positions for the lines
" a:first to a:last. A match that runs over the end of a line is marked on
" each line it covers.
"
" Only the bytes THOSE LINES hold are searched, plus the pattern's length
" less one in front of them so a match reaching in from above is found
" whole. A pattern like "2?" matches every sixteenth byte, which on a
" 128 KiB page is eight thousand times: building that list took a second,
" and walking every visible line for each of its entries took another - to
" mark the forty matches that are on screen. What can be marked is what is
" on screen, and there is a window's worth of it.
"
" The bytes are the page's as it was READ, which is what keeps the marking
" about the FILE: an edit of yours shows up as a changed byte
" (HexPairModified), not as a match appearing or vanishing under the
" cursor.
function! HexPairPagedFindPositions(first, last) abort
  let out = []
  let n = b:hexpair_n
  let span = s:find.bytes
  let hex = get(b:, 'hexpair_page_hex', '')
  if span <= 0 || s:find.hex ==# '' || hex ==# ''
    return out
  endif
  let header = s:HeaderLines()
  let firstidx = a:first - 1 - header
  let lastidx  = a:last - 1 - header
  let bytes = strlen(hex) / 2
  let lo = firstidx < 0 ? 0 : firstidx * n
  let hi = (lastidx + 1) * n - 1
  if hi > bytes - 1
    let hi = bytes - 1
  endif
  if lastidx < 0 || lo > hi
    return out
  endif
  " Back up by the pattern's span so a match that starts above the window
  " and reaches into it is found; the slice still starts on a byte.
  let from = lo - (span - 1) < 0 ? 0 : lo - (span - 1)
  let slice = strpart(hex, from * 2, (hi - from + 1) * 2)
  let at = 0
  while 1
    let idx = HexPairPagedFindInHex(slice, s:find.hex, at, 1)
    if idx < 0
      break
    endif
    let at = idx + 2
    let byte = from + idx / 2
    let line = byte / n
    let last = (byte + span - 1) / n
    while line <= last
      let lnum = line + 1 + header
      if line >= firstidx && line <= lastidx && line * n < bytes
        let [n2, hexstart, hexend, asciistart] = s:PagedLineLayout(lnum)
        let s0 = byte - line * n
        let s0 = s0 < 0 ? 0 : s0
        let s1 = byte + span - 1 - line * n
        let s1 = s1 > n - 1 ? n - 1 : s1
        call add(out, [lnum, hexstart + s0 * 3, (s1 - s0 + 1) * 3 - 1])
        if strlen(getline(lnum)) >= asciistart
          call add(out, [lnum, asciistart + s0, s1 - s0 + 1])
        endif
      endif
      let line += 1
    endwhile
  endwhile
  return out
endfunction

function! s:ClearFindHighlight() abort
  if exists('w:hexpair_find_ids')
    for id in w:hexpair_find_ids
      silent! call matchdelete(id)
    endfor
  endif
  let w:hexpair_find_ids = []
  let w:hexpair_find_hlstate = []
endfunction

function! s:FindHighlight() abort
  if !get(b:, 'hexpair_page_active', 0)
    return
  endif
  let state = [s:find.hex, b:hexpair_page_base, line('w0'), line('w$')]
  if get(w:, 'hexpair_find_hlstate', []) ==# state
    return
  endif
  call s:ClearFindHighlight()
  let w:hexpair_find_hlstate = state
  if s:find.hex ==# ''
    return
  endif
  let positions = HexPairPagedMarkingPositions('find',
        \ line('w0'), line('w$'))
  for i in range(0, len(positions) - 1, 8)
    call add(w:hexpair_find_ids,
          \ matchaddpos('HexPairFind', positions[i : i + 7]))
  endfor
endfunction

" Jump to a:at, and say what was found there.
function! s:FindLand(at, wrapped) abort
  call s:GotoOffset(string(a:at + 1), 0)
  call s:FindHighlight()
  echo printf('hexpair: %s at byte %d (0x%x)%s', s:find.what,
        \ a:at + 1, a:at + 1, a:wrapped ? ' (wrapped)' : '')
endfunction

function! s:FindFrom(from, forward) abort
  if s:find.hex ==# ''
    echohl ErrorMsg
    echomsg 'hexpair: nothing to find yet - :HexPairFind {bytes} first'
    echohl None
    return
  endif
  let at = s:FindScan(a:from, a:forward)
  if at >= 0
    call s:FindLand(at, 0)
    return
  endif
  " |'wrapscan'|, the same option Vim's own searches obey.
  if &wrapscan
    let at = s:FindScan(a:forward ? 0 : b:hexpair_page_total, a:forward)
    if at >= 0
      call s:FindLand(at, 1)
      return
    endif
  endif
  echohl ErrorMsg
  echomsg printf('hexpair: %s not found%s', s:find.what,
        \ &wrapscan ? ' in this file' : ' after here (''nowrapscan'')')
  echohl None
endfunction

function! s:SetPattern(parsed, what) abort
  let s:find.hex = a:parsed.hex
  let s:find.bytes = a:parsed.bytes
  let s:find.what = a:what
  call s:ClearFindHighlight()
endfunction

function! s:Find(text, clear) abort
  if !s:RequirePaged()
    return
  endif
  if a:clear
    let s:find.hex = ''
    let s:find.bytes = 0
    call s:ClearFindHighlight()
    echo 'hexpair: no pattern'
    return
  endif
  if a:text ==# ''
    echo s:find.hex ==# '' ? 'hexpair: no pattern'
          \ : printf('hexpair: looking for %s', s:find.what)
    return
  endif
  let parsed = HexPairPagedParseFindPattern(a:text)
  if has_key(parsed, 'msg')
    echohl ErrorMsg | echomsg parsed.msg | echohl None
    return
  endif
  call s:SetPattern(parsed, printf('bytes %s', a:text))
  call s:FindFrom(s:Here() + 1, 1)
endfunction

function! s:FindText(text) abort
  if !s:RequirePaged()
    return
  endif
  let hex = HexPairPagedTextToHex(a:text)
  if hex ==# ''
    echohl ErrorMsg | echomsg 'hexpair: nothing to find' | echohl None
    return
  endif
  call s:SetPattern({'hex': hex, 'bytes': strlen(hex) / 2},
        \ printf('text %s', string(a:text)))
  call s:FindFrom(s:Here() + 1, 1)
endfunction

function! s:FindRepeat(forward) abort
  if !s:RequirePaged()
    return
  endif
  call s:FindFrom(a:forward ? s:Here() + 1 : s:Here(), a:forward)
endfunction

" The byte the cursor is on, in either view.
function! s:Here() abort
  return s:IsHexView() ? s:PagedByteOffset() : s:TextByteOffset()
endfunction

" ---------------------------------------------------------------------------
" Replacing what was found
" ---------------------------------------------------------------------------
"
" Both commands edit the PAGE, exactly as typing over the dump would:
" nothing is written until |:w| writes it, the changed bytes are marked
" like any other edit, and a replacement of a different length goes
" through the same length-changing write - which says what it will cost
" and asks - as any other insertion or deletion.

" Put a:hex in place of a:len bytes at page offset a:at, and rebuild the
" view from the result.
function! s:SpliceIntoPage(at, len, hex) abort
  let scan = s:PagedScan(0)
  if !empty(scan.err)
    throw 'hexpair: ' . scan.err.msg . '; nothing was replaced'
  endif
  let flat = substitute(join(scan.lines, ''), '[^0-9a-fA-F]', '', 'g')
  if a:at < 0 || (a:at + a:len) * 2 > strlen(flat)
    throw 'hexpair: that is not on this page any more; find it again'
  endif
  let new = strpart(flat, 0, a:at * 2) . a:hex
        \ . strpart(flat, (a:at + a:len) * 2)
  let hex = tempname()
  let raw = tempname()
  let dump = tempname()
  try
    call writefile([new], hex)
    call s:Run(printf('%s -r -p %s %s', s:xxd,
          \ shellescape(hex), shellescape(raw)))
    call s:CanonicalDump(raw, b:hexpair_page_base, dump)
    call s:SetLinesUndoable(s:HexViewLines(readfile(dump)))
  finally
    call delete(hex)
    call delete(raw)
    call delete(dump)
  endtry
  setlocal modified
  call s:PagedGotoOffset(b:hexpair_page_base + a:at)
  call s:PagedHighlight()
endfunction

function! s:Replace(text) abort
  if !s:RequirePaged()
    return
  endif
  try
    if !s:IsHexView()
      throw 'hexpair: replacing works in the hex view; :HexPairToggle first'
    endif
    if s:find.hex ==# ''
      throw 'hexpair: nothing has been found to replace'
    endif
    let parsed = HexPairPagedParseFindPattern(a:text)
    if has_key(parsed, 'msg')
      throw parsed.msg
    endif
    if parsed.hex =~# '\.'
      throw 'hexpair: a replacement cannot have wildcards in it'
    endif
    " What is under the cursor has to BE a match, or the command would
    " overwrite whatever the cursor happens to sit on - and the bytes that
    " decide are the ones in the BUFFER, not the ones the page was read
    " with. They part company as soon as anything is replaced: the file
    " still holds the pattern where this buffer no longer does, and a
    " second :HexPairReplace on the spot would then overwrite bytes that
    " are no longer a match.
    let at = s:Here() - b:hexpair_page_base
    let scan = s:PagedScan(0)
    if !empty(scan.err)
      throw 'hexpair: ' . scan.err.msg . '; nothing was replaced'
    endif
    let flat = substitute(join(scan.lines, ''), '[^0-9a-fA-F]', '', 'g')
    if strpart(flat, at * 2, s:find.bytes * 2) !~# '^' . s:find.hex . '$'
      throw 'hexpair: the cursor is not on a match - :HexPairFindNext first'
    endif
    call s:SpliceIntoPage(at, s:find.bytes, parsed.hex)
    echo printf('hexpair: %d byte%s replaced at %d (0x%x)', parsed.bytes,
          \ parsed.bytes == 1 ? '' : 's',
          \ b:hexpair_page_base + at + 1, b:hexpair_page_base + at + 1)
  catch /^hexpair:/
    echohl ErrorMsg
    echomsg v:exception
    echohl None
  endtry
endfunction

" {pattern} / {replacement} - the slash keeps the two apart without
" quoting rules of their own, since a pattern is hex digits, spaces and
" '?' and can never contain one.
function! HexPairPagedSplitReplaceArgs(text) abort
  let parts = split(a:text, '/', 1)
  if len(parts) != 2
    return {'msg': 'hexpair: :HexPairReplaceAllInPage takes {pattern} / {bytes}'}
  endif
  return {'pattern': parts[0], 'replacement': parts[1]}
endfunction

function! s:ReplaceAll(text) abort
  if !s:RequirePaged()
    return
  endif
  try
    if !s:IsHexView()
      throw 'hexpair: replacing works in the hex view; :HexPairToggle first'
    endif
    let args = HexPairPagedSplitReplaceArgs(a:text)
    if has_key(args, 'msg')
      throw args.msg
    endif
    let pattern = HexPairPagedParseFindPattern(args.pattern)
    if has_key(pattern, 'msg')
      throw pattern.msg
    endif
    let replacement = HexPairPagedParseFindPattern(args.replacement)
    if has_key(replacement, 'msg')
      throw replacement.msg
    endif
    if replacement.hex =~# '\.'
      throw 'hexpair: a replacement cannot have wildcards in it'
    endif
    call s:SetPattern(pattern, printf('bytes %s', args.pattern))
    " On the page's CURRENT bytes, so a replacement composes with edits
    " already made, and from the back, so replacing one does not move the
    " ones not yet replaced.
    let scan = s:PagedScan(0)
    if !empty(scan.err)
      throw 'hexpair: ' . scan.err.msg . '; nothing was replaced'
    endif
    let flat = substitute(join(scan.lines, ''), '[^0-9a-fA-F]', '', 'g')
    let at = 0
    let found = []
    while 1
      let idx = HexPairPagedFindInHex(flat, pattern.hex, at, 1)
      if idx < 0
        break
      endif
      call add(found, idx)
      let at = idx + pattern.bytes * 2
    endwhile
    if empty(found)
      echo printf('hexpair: %s is not on this page', s:find.what)
      return
    endif
    let new = flat
    for idx in reverse(copy(found))
      let new = strpart(new, 0, idx) . replacement.hex
            \ . strpart(new, idx + pattern.bytes * 2)
    endfor
    call s:SpliceIntoPage(0, strlen(flat) / 2, new)
    echo printf('hexpair: %d occurrence%s replaced on this page',
          \ len(found), len(found) == 1 ? '' : 's')
  catch /^hexpair:/
    echohl ErrorMsg
    echomsg v:exception
    echohl None
  endtry
endfunction

" ---------------------------------------------------------------------------
" Comparing this file with another
" ---------------------------------------------------------------------------
"
" |:HexPairDiff| {file} marks, in both columns, every byte of the page that
" differs from the same offset of {file} - and |:HexPairDiffNext| walks the
" whole file for the next offset where the two disagree, however far away
" that is. Two views side by side (|hexpair-two-views|), each diffing
" against the other's file, is what `vimhexdiff` sets up.
"
" What is compared is what is on SCREEN against the other file, so an edit
" shows up in the marking at once, the same way the modified-byte marking
" works.

" The first index at which two strings differ, or -1 when neither is
" longer and no character does. When one is a prefix of the other, that is
" where it ends: everything from there on is a difference.
"
" By halving rather than by walking: comparing two strings is one
" C-level operation and a block of a file is megabytes of hex, so the
" walk is what would cost - about twenty comparisons of shrinking
" substrings find the byte instead.
function! HexPairPagedFirstDifference(a, b) abort
  if a:a ==# a:b
    return -1
  endif
  let short = strlen(a:a) < strlen(a:b) ? strlen(a:a) : strlen(a:b)
  if strpart(a:a, 0, short) ==# strpart(a:b, 0, short)
    return short
  endif
  let [lo, hi] = [0, short]
  " Invariant: the two agree over [0, lo) and differ somewhere in [lo, hi).
  while hi - lo > 1
    let mid = (lo + hi) / 2
    if strpart(a:a, lo, mid - lo) ==# strpart(a:b, lo, mid - lo)
      let lo = mid
    else
      let hi = mid
    endif
  endwhile
  return lo
endfunction

" The same, from the other end: the LAST index at which they differ.
function! HexPairPagedLastDifference(a, b) abort
  if a:a ==# a:b
    return -1
  endif
  " A longer string has a character where the other has nothing, and that
  " is the last difference there is.
  if strlen(a:a) != strlen(a:b)
    return (strlen(a:a) > strlen(a:b) ? strlen(a:a) : strlen(a:b)) - 1
  endif
  " Invariant: they differ somewhere in [lo, hi) and agree over [hi, end).
  let [lo, hi] = [0, strlen(a:a)]
  while hi - lo > 1
    let mid = (lo + hi) / 2
    if strpart(a:a, mid) ==# strpart(a:b, mid)
      let hi = mid
    else
      let lo = mid
    endif
  endwhile
  return lo
endfunction

" Bytes of the other file for the page in view, and what the page's own
" bytes are held against.
function! s:DiffHex() abort
  return get(b:, 'hexpair_diff_hex', '')
endfunction

function! s:LoadDiffHex() abort
  if get(b:, 'hexpair_diff_file', '') ==# ''
    let b:hexpair_diff_hex = ''
    return
  endif
  let b:hexpair_diff_hex = s:FileHex(b:hexpair_diff_file,
        \ b:hexpair_page_base, b:hexpair_page_len)
endfunction

function! s:DiffPositions(first, last) abort
  return HexPairPagedComparePositions(a:first, a:last, s:DiffHex())
endfunction

function! s:ClearDiffHighlight() abort
  if exists('w:hexpair_diff_ids')
    for id in w:hexpair_diff_ids
      silent! call matchdelete(id)
    endfor
  endif
  let w:hexpair_diff_ids = []
  let w:hexpair_diff_state = []
endfunction

function! s:DiffHighlight() abort
  if !get(b:, 'hexpair_page_active', 0) || s:DiffHex() ==# ''
    return
  endif
  let state = [b:changedtick, line('w0'), line('w$'), b:hexpair_page_index]
  if get(w:, 'hexpair_diff_state', []) ==# state
    return
  endif
  call s:ClearDiffHighlight()
  let w:hexpair_diff_state = state
  let positions = HexPairPagedMarkingPositions('diff',
        \ line('w0'), line('w$'))
  for i in range(0, len(positions) - 1, 8)
    call add(w:hexpair_diff_ids,
          \ matchaddpos('HexPairDiff', positions[i : i + 7]))
  endfor
endfunction

" How the two files compare over the page in view, as one line.
function! HexPairPagedDiffText(theirs, base, len, differing, first) abort
  if a:differing < 0
    return printf('hexpair: %s cannot be read; nothing to compare against',
          \ a:theirs)
  endif
  if a:differing == 0
    return printf('hexpair: bytes %d-%d are the same in %s',
          \ a:base + 1, a:base + a:len, a:theirs)
  endif
  return printf('hexpair: %d of the %d bytes on this page differ from %s, '
        \ . 'first at byte %d (0x%x)',
        \ a:differing, a:len, a:theirs, a:first + 1, a:first + 1)
endfunction

" How many bytes of a:mine differ from a:theirs, and the index of the
" first that does - both runs being flat hex, as s:FileHex() gives them.
" Bytes a:theirs does not reach count as differing: that is what a file
" ending early is.
"
" A block that matches is ONE string comparison, so a page that is mostly
" the same costs almost nothing, and a block that differs is taken apart
" with split() and filter() rather than walked. Measured on a 128 KiB
" page: the walk this replaces took 4.9 s - which is what made vimhexdiff
" feel hung, twice over, since both windows count - against 0.6 ms for a
" page that matches, 8 ms for one with a handful of differences, and
" 260 ms in the worst case there is, every byte different and nothing to
" skip.
function! HexPairPagedCountDifferences(mine, theirs) abort
  " Two pages that match - the common case in a diff of two builds of one
  " file - are one comparison and nothing else.
  if a:mine ==# a:theirs
    return [0, -1]
  endif
  let bytes  = strlen(a:mine) / 2
  let theirs = strlen(a:theirs) / 2
  let common = theirs < bytes ? theirs : bytes
  let differing = 0
  let first = -1
  let at = 0
  while at < common
    let span = s:cmpblock < common - at ? s:cmpblock : common - at
    if strpart(a:mine, at * 2, span * 2) !=# strpart(a:theirs, at * 2, span * 2)
      let lhs = split(strpart(a:mine, at * 2, span * 2), '..\zs')
      let rhs = split(strpart(a:theirs, at * 2, span * 2), '..\zs')
      let differs = filter(range(span), 'lhs[v:val] !=# rhs[v:val]')
      let differing += len(differs)
      if first < 0 && !empty(differs)
        let first = at + differs[0]
      endif
    endif
    let at += span
  endwhile
  if bytes > common
    let differing += bytes - common
    if first < 0
      let first = common
    endif
  endif
  return [differing, first]
endfunction

" Bytes of the page that differ from a:hex, and the first one's offset.
" Against the page as it was READ, not as the buffer now holds it: this
" is the answer to "how do these two files compare", which unwritten
" edits of mine are no part of. The marking on screen is the live one.
function! s:DiffCount(hex) abort
  let mine = get(b:, 'hexpair_page_hex', '')
  if mine ==# '' || a:hex ==# ''
    return [-1, -1]
  endif
  let [differing, first] = HexPairPagedCountDifferences(mine, a:hex)
  return [differing, first < 0 ? -1 : b:hexpair_page_base + first]
endfunction

function! s:Diff(file, clear) abort
  if !s:RequirePaged()
    return
  endif
  if a:clear
    let b:hexpair_diff_file = ''
    let b:hexpair_diff_hex = ''
    call s:ClearDiffHighlight()
    echo 'hexpair: no longer comparing'
    return
  endif
  if a:file ==# ''
    echo get(b:, 'hexpair_diff_file', '') ==# ''
          \ ? 'hexpair: not comparing with anything'
          \ : 'hexpair: comparing with ' . b:hexpair_diff_file
    return
  endif
  let file = fnamemodify(a:file, ':p')
  if !filereadable(file)
    echohl ErrorMsg
    echomsg 'hexpair: cannot read ' . a:file
    echohl None
    return
  endif
  if s:SamePath(file, b:hexpair_page_file)
    echohl ErrorMsg
    echomsg 'hexpair: that is this view''s own file'
    echohl None
    return
  endif
  let b:hexpair_diff_file = file
  call s:LoadDiffHex()
  call s:ClearDiffHighlight()
  call s:DiffHighlight()
  let [differing, first] = s:DiffCount(s:DiffHex())
  echo HexPairPagedDiffText(file, b:hexpair_page_base,
        \ b:hexpair_page_len, differing, first)
endfunction

" Function form, for the same reason HexPairOpenFile() has one: a name
" with a space or a literal '$' does not survive <f-args>.
function! HexPairDiffWith(file) abort
  call s:Diff(a:file, 0)
endfunction

" The next (or previous) offset at which the two files differ, from a:from
" exclusive. Reads both a block at a time, so memory does not follow the
" size of either, and finds the byte within a block by halving.
" The first byte at which two runs of hex AGREE, or -1 if they never do.
" Bytes the shorter run does not reach are differences, not agreements -
" a file that has ended does not agree with one that has not.
"
" Same shape as HexPairPagedCountDifferences(): a chunk that is identical
" between the two is one string comparison and agreement at its first
" byte, and only a chunk that is not gets taken apart.
function! HexPairPagedFirstAgreement(mine, theirs) abort
  let bytes  = strlen(a:mine) / 2
  let theirs = strlen(a:theirs) / 2
  let common = theirs < bytes ? theirs : bytes
  let at = 0
  while at < common
    let span = s:cmpblock < common - at ? s:cmpblock : common - at
    let lhs = strpart(a:mine, at * 2, span * 2)
    let rhs = strpart(a:theirs, at * 2, span * 2)
    if lhs ==# rhs
      return at
    endif
    let l = split(lhs, '..\zs')
    let r = split(rhs, '..\zs')
    let same = filter(range(span), 'l[v:val] ==# r[v:val]')
    if !empty(same)
      return at + same[0]
    endif
    let at += span
  endwhile
  return -1
endfunction

" The same from the other end: the LAST byte at which they agree, or -1.
function! HexPairPagedLastAgreement(mine, theirs) abort
  let bytes  = strlen(a:mine) / 2
  let theirs = strlen(a:theirs) / 2
  let common = theirs < bytes ? theirs : bytes
  let at = common
  while at > 0
    let span = s:cmpblock < at ? s:cmpblock : at
    let from = at - span
    let lhs = strpart(a:mine, from * 2, span * 2)
    let rhs = strpart(a:theirs, from * 2, span * 2)
    if lhs ==# rhs
      return at - 1
    endif
    let l = split(lhs, '..\zs')
    let r = split(rhs, '..\zs')
    let same = filter(range(span), 'l[v:val] ==# r[v:val]')
    if !empty(same)
      return from + same[-1]
    endif
    let at = from
  endwhile
  return -1
endfunction

" Where the change that covers a:from ends: the first byte at or after it
" at which the two files agree. If they already agree at a:from - the
" cursor is not in a change - that is a:from itself, and nothing is read
" beyond the first block. If they never agree again, the end of the
" longer file.
function! s:AgreementAfter(other, from, total) abort
  let off = a:from
  while off < a:total
    let len = s:diffblock < a:total - off ? s:diffblock : a:total - off
    let mine   = s:FileHex(b:hexpair_page_file, off, len)
    let theirs = s:FileHex(a:other, off, len)
    if mine ==# theirs
      return off
    endif
    let at = HexPairPagedFirstAgreement(mine, theirs)
    if at >= 0
      return off + at
    endif
    let off += len
    call s:Progress('following the change', off, a:total)
  endwhile
  return a:total
endfunction

" And backwards: the last byte BEFORE a:before at which they agree, or -1
" when the change reaches the start of the file.
function! s:AgreementBefore(other, before, total) abort
  let end = a:before
  while end > 0
    let len = s:diffblock < end ? s:diffblock : end
    let start = end - len
    let mine   = s:FileHex(b:hexpair_page_file, start, len)
    let theirs = s:FileHex(a:other, start, len)
    if mine ==# theirs
      return end - 1
    endif
    let at = HexPairPagedLastAgreement(mine, theirs)
    if at >= 0
      return start + at
    endif
    let end = start
    call s:Progress('following the change back', a:total - end, a:total)
  endwhile
  return -1
endfunction

" The next byte at or after a:from at which the two files differ, or -1.
function! s:DifferenceAfter(other, from, total) abort
  let off = a:from
  while off < a:total
    call s:Progress('comparing', off, a:total)
    let len = s:diffblock < a:total - off ? s:diffblock : a:total - off
    let idx = HexPairPagedFirstDifference(
          \ s:FileHex(b:hexpair_page_file, off, len),
          \ s:FileHex(a:other, off, len))
    if idx >= 0
      return off + idx / 2
    endif
    let off += len
  endwhile
  return -1
endfunction

" The last byte before a:before at which they differ, or -1.
function! s:DifferenceBefore(other, before, total) abort
  let off = a:before
  while off > 0
    call s:Progress('comparing back', a:total - off, a:total)
    let len = s:diffblock < off ? s:diffblock : off
    let start = off - len
    let idx = HexPairPagedLastDifference(
          \ s:FileHex(b:hexpair_page_file, start, len),
          \ s:FileHex(a:other, start, len))
    if idx >= 0
      return start + idx / 2
    endif
    let off = start
  endwhile
  return -1
endfunction

" The next (or previous) CHANGE, as the offset of its first byte.
"
" A change is a run of bytes that differ, and what these jumps are for is
" moving between changes - not through the bytes of one. Two files that
" part company at byte 2 and agree again at byte 6 have one change there,
" however many bytes it covers, so the jump from inside it goes to the
" next one.
"
" Forward, that is: find where the change under the cursor ends (nothing
" is read past the first block when the cursor is not in one), then the
" first difference from there - which is a change's first byte by
" construction, since everything between the agreement and it agrees.
" Backwards: the last difference before the cursor is somewhere inside a
" change, and what is wanted is that change's first byte, so walk back to
" the agreement in front of it. From the middle of a change that lands on
" the change's own start, which is what |[c| does in a diff.
function! s:DiffSearch(from, forward) abort
  let other = get(b:, 'hexpair_diff_file', '')
  if other ==# ''
    throw 'hexpair: not comparing with anything - :HexPairDiff {file} first'
  endif
  let mysize = getfsize(b:hexpair_page_file)
  let theirsize = getfsize(other)
  let total = mysize > theirsize ? mysize : theirsize
  if a:forward
    return s:DifferenceAfter(other,
          \ s:AgreementAfter(other, a:from, total), total)
  endif
  let at = s:DifferenceBefore(other, a:from, total)
  return at < 0 ? -1 : s:AgreementBefore(other, at, total) + 1
endfunction

function! s:DiffJump(forward) abort
  if !s:RequirePaged()
    return
  endif
  try
    let here = s:IsHexView() ? s:PagedByteOffset() : s:TextByteOffset()
    let at = s:DiffSearch(here, a:forward)
    if at < 0
      echo printf('hexpair: no change %s byte %d',
            \ a:forward ? 'after' : 'before', here + 1)
      return
    endif
    " The difference can be past the end of THIS file - the other one is
    " longer, and every byte it has beyond ours is one. There is nowhere
    " to put the cursor for that, so say it rather than jump.
    if at >= b:hexpair_page_total
      echo printf('hexpair: %s is longer: its bytes from %d (0x%x) on have '
            \ . 'nothing here to differ from', b:hexpair_diff_file,
            \ at + 1, at + 1)
      return
    endif
    call s:GotoOffset(string(at + 1), 0)
    " The file is named short here (:~:.), unlike everywhere else in this
    " plugin: this message is printed on every press of the jump key, and
    " one that does not fit on the command line costs a hit-enter prompt
    " each time.
    echo printf('hexpair: %s change at byte %d (0x%x) against %s',
          \ a:forward ? 'next' : 'previous', at + 1, at + 1,
          \ fnamemodify(b:hexpair_diff_file, ':~:.'))
  catch /^hexpair:/
    echohl ErrorMsg
    echomsg v:exception
    echohl None
  endtry
endfunction

" ---------------------------------------------------------------------------
" Marks
" ---------------------------------------------------------------------------
"
" Vim's own marks are positions in a BUFFER, and a paged buffer holds a
" different part of the file from one moment to the next, so a mark set in
" one page means something else in the next. These are positions in the
" FILE: absolute byte offsets, kept per file rather than per buffer, so
" every view of that file shares them (|hexpair-two-views|) and a page
" turn cannot disturb them.
"
" They live for as long as the Vim session does. Writing them somewhere
" would make them outlive it, and that is a decision about the user's
" filesystem this plugin does not get to make on its own.
let s:marks = {}

" Bumped whenever a mark is set or dropped, so the marking on screen knows
" it has to be worked out again - the same job b:changedtick does for the
" page's own bytes.
let s:marks_tick = 0

function! s:MarksFor(file) abort
  if !has_key(s:marks, a:file)
    let s:marks[a:file] = {}
  endif
  return s:marks[a:file]
endfunction

" The same, for a caller that only wants to look: the marking runs on
" every page and must not leave an empty dict behind for each file it saw.
function! s:MarksOf(file) abort
  return get(s:marks, a:file, {})
endfunction

" Where the marks of this page are, as matchaddpos() positions for both
" columns. By the canonical layout, like everything else that marks bytes
" here: on a page nobody has edited that is exactly where the byte is,
" and on one that has been, it is where the byte WAS - which is the same
" answer the modified-byte marking gives.
function! HexPairPagedMarkPositions(first, last) abort
  let out = []
  let marks = s:MarksOf(b:hexpair_page_file)
  if empty(marks) || b:hexpair_page_len <= 0
    return out
  endif
  let n = b:hexpair_n
  for name in keys(marks)
    let off = marks[name] - b:hexpair_page_base
    if off < 0 || off >= b:hexpair_page_len
      continue
    endif
    let lnum = off / n + 1 + s:HeaderLines()
    if lnum < a:first || lnum > a:last
      continue
    endif
    let [n, hexstart, hexend, asciistart] = s:PagedLineLayout(lnum)
    let idx = off % n
    call add(out, [lnum, hexstart + idx * 3, 2])
    if strlen(getline(lnum)) >= asciistart
      call add(out, [lnum, asciistart + idx, 1])
    endif
  endfor
  return out
endfunction

function! s:ClearMarkHighlight() abort
  if exists('w:hexpair_mark_ids')
    for id in w:hexpair_mark_ids
      silent! call matchdelete(id)
    endfor
  endif
  let w:hexpair_mark_ids = []
  let w:hexpair_mark_state = []
endfunction

function! s:MarkHighlight() abort
  if !g:hexpair_show_marks || !get(b:, 'hexpair_page_active', 0)
    return
  endif
  let state = [s:marks_tick, b:hexpair_page_base, line('w0'), line('w$')]
  if get(w:, 'hexpair_mark_state', []) ==# state
    return
  endif
  call s:ClearMarkHighlight()
  let w:hexpair_mark_state = state
  " Priority 5, below the 10 the other markings take: where a mark sits on
  " a byte that is also edited, differing or found, what is true of the
  " BYTE wins - the mark is about the place, and the place is still findable
  " through |:HexPairMarks|.
  let positions = HexPairPagedMarkingPositions('mark',
        \ line('w0'), line('w$'))
  for i in range(0, len(positions) - 1, 8)
    call add(w:hexpair_mark_ids,
          \ matchaddpos('HexPairMark', positions[i : i + 7], 5))
  endfor
endfunction

" Mark names are words, so that a listing can be read and a name can be
" completed without quoting rules of its own.
function! HexPairPagedMarkNameError(name) abort
  if a:name ==# ''
    return 'hexpair: a mark needs a name'
  endif
  if a:name !~# '^\w\+$'
    return printf('hexpair: %s is not a mark name (letters, digits and '
          \ . 'underscores)', string(a:name))
  endif
  return ''
endfunction

function! s:SetMark(name) abort
  if !s:RequirePaged()
    return
  endif
  let err = HexPairPagedMarkNameError(a:name)
  if !empty(err)
    echohl ErrorMsg | echomsg err | echohl None
    return
  endif
  if b:hexpair_page_len <= 0
    echohl ErrorMsg
    echomsg 'hexpair: this page holds no bytes to mark'
    echohl None
    return
  endif
  let off = s:IsHexView() ? s:PagedByteOffset() : s:TextByteOffset()
  let marks = s:MarksFor(b:hexpair_page_file)
  let marks[a:name] = off
  let s:marks_tick += 1
  call s:MarkHighlight()
  echo printf('hexpair: mark %s at byte %d (0x%x)', a:name, off + 1, off + 1)
endfunction

function! s:DeleteMark(name) abort
  if !s:RequirePaged()
    return
  endif
  let marks = s:MarksFor(b:hexpair_page_file)
  if !has_key(marks, a:name)
    echohl ErrorMsg
    echomsg printf('hexpair: no mark named %s here', string(a:name))
    echohl None
    return
  endif
  call remove(marks, a:name)
  let s:marks_tick += 1
  call s:MarkHighlight()
  echo printf('hexpair: mark %s dropped', a:name)
endfunction

function! s:GoMark(name, force) abort
  if !s:RequirePaged()
    return
  endif
  let marks = s:MarksFor(b:hexpair_page_file)
  if !has_key(marks, a:name)
    echohl ErrorMsg
    echomsg printf('hexpair: no mark named %s here%s', string(a:name),
          \ empty(marks) ? '' : ' (have: ' . join(sort(keys(marks)), ', ') . ')')
    echohl None
    return
  endif
  " Through the same road a typed position takes, so a mark on a byte the
  " file no longer has is refused in the same words.
  call s:GotoOffset(string(marks[a:name] + 1), a:force)
endfunction

" The listing, as lines. Pure, so its wording is testable without a file:
" a:marks is the dict, a:size the page size, a:total the file's length.
function! HexPairPagedMarkLines(marks, size, total) abort
  if empty(a:marks)
    return ['hexpair: no marks in this file']
  endif
  let byoffset = []
  for name in keys(a:marks)
    call add(byoffset, printf('%020d %s', a:marks[name], name))
  endfor
  let out = []
  for entry in sort(byoffset)
    let name = entry[21:]
    let off = a:marks[name]
    call add(out, printf('  %-16s byte %d (0x%x)%s of %d, page %d',
          \ name, off + 1, off + 1,
          \ off >= a:total ? ' - past the end' : '', a:total,
          \ off / a:size + 1))
  endfor
  return ['hexpair: marks in this file:'] + out
endfunction

" Prompt for a mark to go to, completing the names as they are typed -
" the <Plug> equivalent of |:HexPairGoMark|, which needs a typed name a
" bare <Plug> target cannot carry. Deliberately untested, for the reason
" given at s:PageGotoPrompt(): input() does not behave usably under this
" project's `vim -es` harness. Everything it decides is one line.
function! s:GoMarkPrompt(force) abort
  if !s:RequirePaged()
    return
  endif
  if empty(s:MarksOf(b:hexpair_page_file))
    echo 'hexpair: no marks in this file'
    return
  endif
  let name = input('hexpair: go to mark: ', '',
        \ 'customlist,HexPairPagedMarkComplete')
  redraw
  if !empty(name)
    call s:GoMark(name, a:force)
  endif
endfunction

" The same for the two searches: |:HexPairFind| and |:HexPairFindText|
" take what they look for as an argument, so their <Plug> targets ask.
function! s:FindPrompt() abort
  if !s:RequirePaged()
    return
  endif
  let text = input('hexpair: find bytes (? = any nibble): ')
  redraw
  if !empty(text)
    call s:Find(text, 0)
  endif
endfunction

function! s:FindTextPrompt() abort
  if !s:RequirePaged()
    return
  endif
  let text = input('hexpair: find text: ')
  redraw
  if !empty(text)
    call s:FindText(text)
  endif
endfunction

function! s:Marks() abort
  if !s:RequirePaged()
    return
  endif
  for line in HexPairPagedMarkLines(s:MarksFor(b:hexpair_page_file),
        \ b:hexpair_page_size, b:hexpair_page_total)
    echo line
  endfor
endfunction

" Completion for the commands that take a mark name.
function! HexPairPagedMarkComplete(lead, cmdline, pos) abort
  if !get(b:, 'hexpair_page_active', 0)
    return []
  endif
  return sort(filter(keys(s:MarksFor(b:hexpair_page_file)),
        \ 'v:val[0 : strlen(a:lead) - 1] ==# a:lead'))
endfunction

" ---------------------------------------------------------------------------
" A second view of the same file
" ---------------------------------------------------------------------------

" |:HexPairSplit| / |:HexPairVSplit|: another window onto the same file,
" showing another page of it - for reading one region while editing
" another, or copying bytes from one to the other.
"
" Nothing about a page is shared between the two: each view is its own
" buffer with its own page state, and the write path patches only the page
" its own view holds. What used to make this impossible was the buffer's
" NAME, which is now numbered when it is taken (s:NamePageBuffer()), and
" the freshness check, which refused a write whenever the file's timestamp
" had moved - which is exactly what the other view writing does. It now
" asks whether THIS PAGE changed (s:CheckFresh()).
"
" [page] is resolved in THIS view's terms - a number, +N or -N from the
" page on screen, or $ - and then handed to the new view as the byte it
" starts at, so the two agree even if g:hexpair_page_size was changed in
" between and the new view therefore slices the file differently.
function! s:SplitView(vertical, ...) abort
  if !s:RequirePaged()
    return
  endif
  if get(b:, 'hexpair_page_spill', '') !=# ''
    echohl ErrorMsg
    echomsg 'hexpair: this view is paged from a private copy of piped '
          \ . 'input, which belongs to it alone; save it with :w {file} '
          \ . 'first, and split that'
    echohl None
    return
  endif
  let parsed = HexPairPagedParsePageInput(a:0 ? a:1 : '')
  if has_key(parsed, 'msg')
    echohl ErrorMsg | echomsg parsed.msg | echohl None
    return
  endif
  let page = empty(parsed) ? b:hexpair_page_index + 1
        \ : HexPairPagedResolvePage(parsed, b:hexpair_page_index + 1,
        \                          b:hexpair_page_totalpages)
  let file = b:hexpair_page_file
  " Everything that can be refused is refused BEFORE the window is split,
  " so a page that does not exist leaves no half-made view behind.
  let [base, len] = HexPairPagedBounds(page - 1, b:hexpair_page_size,
        \ b:hexpair_page_total)
  if base < 0
    echohl ErrorMsg
    echomsg printf('hexpair: page %d does not exist (file has %d page%s)',
          \ page, b:hexpair_page_totalpages,
          \ b:hexpair_page_totalpages == 1 ? '' : 's')
    echohl None
    return
  endif

  let wastext = !s:IsHexView()
  execute a:vertical ? 'vsplit' : 'split'
  call s:NewViewHere(file, base / g:hexpair_page_size + 1, base, wastext)
endfunction

" Turn the CURRENT window into a fresh view of a:file, showing the page
" a:page holds, with the cursor on the absolute offset a:off and in the
" same view the window it came from was in - a split of the text view
" that came back as a dump would be a surprise.
function! s:NewViewHere(file, page, off, wastext) abort
  " Whatever this window was, it is a view of its own from here on, and
  " saying so first is what keeps s:WindowView() from acting on the
  " window events this very call produces.
  let w:hexpair_own_view = 1
  call s:Open(0, a:file, string(a:page))
  if !get(b:, 'hexpair_page_active', 0)
    return 0
  endif
  if a:wastext
    call s:ToText()
    call s:TextGotoOffset(a:off)
  else
    call s:PagedGotoOffset(a:off)
    call s:PagedHighlight()
  endif
  return 1
endfunction

" How many windows, across every tab, are showing a:buf.
function! s:WindowsShowing(buf) abort
  let n = 0
  for tab in range(1, tabpagenr('$'))
    for buf in tabpagebuflist(tab)
      if buf == a:buf
        let n += 1
      endif
    endfor
  endfor
  return n
endfunction

" WinEnter on a paged buffer: with g:hexpair_split_views set, a window
" that has just become the SECOND one showing this page turns into a view
" of its own instead. That covers :split and :vsplit, :tab split, and any
" other way a buffer ends up in a second window - none of which the
" plugin has to know about, because what it looks at is the result.
"
" Every window that holds a view of its own is marked (w:hexpair_own_view,
" set here and when a page is loaded), so this runs once per window rather
" than on every window switch. Window-local variables are not copied to
" the window a :split creates, which is what makes the mark mean "this
" window was here before the split".
function! s:WindowView() abort
  if !get(b:, 'hexpair_page_active', 0) || get(w:, 'hexpair_own_view', 0)
    return
  endif
  " A view paged from piped input has nothing another view could page:
  " its temp belongs to this buffer and goes when the buffer does.
  if !g:hexpair_split_views || get(b:, 'hexpair_page_spill', '') !=# ''
        \ || s:WindowsShowing(bufnr('%')) < 2
    let w:hexpair_own_view = 1
    return
  endif
  let file = b:hexpair_page_file
  let page = b:hexpair_page_index + 1
  let wastext = !s:IsHexView()
  let off = wastext ? s:TextByteOffset() : s:PagedByteOffset()
  try
    call s:NewViewHere(file, page, off, wastext)
  catch /^hexpair:/
    echohl ErrorMsg
    echomsg v:exception
    echohl None
  endtry
endfunction

function! HexPairOpenFile(file, ...) abort
  call call('s:Open', [0, a:file] + a:000)
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
  " 'fileformat' unix: the buffer is a window onto bytes and Vim never
  " writes it itself (BufWriteCmd), but line2byte() - which is how a
  " position in the text view becomes a byte offset - counts the line
  " break the way 'fileformat' says. One byte per break is the same
  " convention writefile(..., 'b') uses on the way out.
  setlocal buftype=acwrite bufhidden=hide noswapfile fileformat=unix
  let b:hexpair_page_size = g:hexpair_page_size
  let b:hexpair_page_bufname = bufname('%') ==# ''
        \ ? '' : fnamemodify(bufname('%'), ':p')

  augroup HexPairPagedBuffer
    autocmd! * <buffer>
    autocmd CursorMoved,CursorMovedI <buffer> call s:PagedHighlight()
    autocmd BufWinLeave              <buffer> call s:PagedClearHighlight()
    autocmd BufWinLeave              <buffer> call s:ClearModifiedHighlight()
    autocmd BufWinLeave              <buffer> call s:ClearDiffHighlight()
    autocmd BufWinLeave              <buffer> call s:ClearFindHighlight()
    autocmd BufWinLeave              <buffer> call s:ClearMarkHighlight()
    " An edit that does not move the cursor - r, x on the last column -
    " raises no CursorMoved, and it is exactly the edit whose byte wants
    " marking.
    autocmd TextChanged,TextChangedI <buffer> call s:ModifiedHighlight()
    autocmd BufWriteCmd              <buffer> call s:Write()
    autocmd BufReadCmd               <buffer> call s:Reread()
    autocmd WinEnter                 <buffer> call s:WindowView()
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

" Byte offset within the page of a position, and the reverse.
"
" line2byte() rather than a walk adding up line lengths: it is what Vim
" already tracks, so this stays constant-time however many lines a page
" of raw bytes turns into - which matters because the statusline asks for
" it on every cursor movement. It counts one byte per line break because
" the buffer is forced to 'fileformat' unix (s:SetupPagedBuffer()), which
" is the same convention the write path's writefile(..., 'b') uses.
function! s:TextOffsetAt(lnum, col) abort
  let [first, last] = s:TextBodyRange()
  let lnum = a:lnum < first ? first : (a:lnum > last ? last : a:lnum)
  let off = line2byte(lnum) - line2byte(first)
  call s:Debug('text view line %d, column %d -> byte %d',
        \ lnum, a:col, b:hexpair_page_base + off + a:col - 1)
  return b:hexpair_page_base + off + a:col - 1
endfunction

function! s:TextByteOffset() abort
  return s:TextOffsetAt(line('.'), col('.'))
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

" ---------------------------------------------------------------------------
" The same markings, in the windowed text view
" ---------------------------------------------------------------------------
"
" A dump has three columns per byte in one place and one per byte in
" another, and the marking arithmetic that goes with it; a page of text has
" one column per byte and lines as long as the bytes between two 0x0a make
" them. So the markings are built here out of byte RUNS - [offset, length]
" pairs, page-relative - which every layer can say without knowing anything
" about columns, and one mapper puts them on the lines.
"
" The two comparing layers work in the text view's OWN representation,
" string against string, rather than turning the buffer back into hex: a
" Vim string cannot hold a NUL, and both sides spell one the same way (as
" a line break) because both come from readfile(..., 'b'). That has one
" consequence, and only one: a NUL replaced by a line break at the same
" offset, or the other way round, is not marked. Every other edit is,
" including one that changes the length.

" The visible body lines, as [lnum, offset in the page, length]. Empty
" when the banner has been edited away, since then which lines are content
" is exactly what cannot be told - a redraw is no place to throw about it.
function! s:TextSpans(first, last) abort
  let out = []
  try
    let [bfirst, blast] = s:TextBodyRange()
  catch
    return out
  endtry
  let base = line2byte(bfirst)
  let lnum = a:first < bfirst ? bfirst : a:first
  let last = a:last > blast ? blast : a:last
  while lnum <= last
    call add(out, [lnum, line2byte(lnum) - base, strlen(getline(lnum))])
    let lnum += 1
  endwhile
  return out
endfunction

" Byte runs put on the lines that hold them. A run may cover more than one
" line, and the line break that ends a line is a byte of the page with no
" column to mark, so it is simply left out.
function! HexPairPagedTextPositions(spans, runs) abort
  let out = []
  for span in a:spans
    let [lnum, start, len] = span
    if len <= 0
      continue
    endif
    for run in a:runs
      let lo = run[0] > start ? run[0] : start
      let hi = run[0] + run[1] < start + len ? run[0] + run[1] : start + len
      if hi > lo
        call add(out, [lnum, lo - start + 1, hi - lo])
      endif
    endfor
  endfor
  return out
endfunction

" Where two strings of the same bytes part company, as [offset, length]
" runs counted from a:base. Chunked, so an unedited line costs one
" comparison per kilobyte rather than one per byte - a page with no 0x0a
" in it is a single line as long as the page.
function! HexPairPagedTextRuns(mine, theirs, base) abort
  let out = []
  if a:mine ==# a:theirs
    return out
  endif
  let len = strlen(a:mine)
  let at = 0
  let from = -1
  while at < len
    let span = s:cmpblock < len - at ? s:cmpblock : len - at
    if strpart(a:mine, at, span) ==# strpart(a:theirs, at, span)
      if from >= 0
        call add(out, [a:base + from, at - from])
        let from = -1
      endif
      let at += span
      continue
    endif
    let i = at
    while i < at + span
      if strpart(a:mine, i, 1) !=# strpart(a:theirs, i, 1)
        if from < 0
          let from = i
        endif
      elseif from >= 0
        call add(out, [a:base + from, i - from])
        let from = -1
      endif
      let i += 1
    endwhile
    let at += span
  endwhile
  if from >= 0
    call add(out, [a:base + from, len - from])
  endif
  return out
endfunction

" A run of hex as the text view would hold it, with the line breaks back
" in, so a piece of it can be taken by byte offset and compared against
" what a line of the buffer holds. One xxd for it, kept against the hex it
" was made from: the page as it was read and the file being compared with
" are each converted once per page, not once per redraw.
function! s:BytesAsText(label, hex) abort
  let cache = get(b:, 'hexpair_text_bytes', {})
  let hit = get(cache, a:label, ['', ''])
  if hit[0] ==# a:hex
    return hit[1]
  endif
  let text = ''
  if a:hex !=# ''
    let hexfile = tempname()
    let raw = tempname()
    try
      call writefile([a:hex], hexfile)
      call s:Run(printf('%s -r -p %s %s', s:xxd,
            \ shellescape(hexfile), shellescape(raw)))
      let text = join(readfile(raw, 'b'), "\n")
    catch
      let text = ''
    finally
      call delete(hexfile)
      call delete(raw)
    endtry
  endif
  let cache[a:label] = [a:hex, text]
  let b:hexpair_text_bytes = cache
  return text
endfunction

" What the buffer holds against a:hex, over the visible lines only.
function! s:TextComparePositions(first, last, label, hex) abort
  if a:hex ==# ''
    return []
  endif
  let theirs = s:BytesAsText(a:label, a:hex)
  if theirs ==# ''
    return []
  endif
  let spans = s:TextSpans(a:first, a:last)
  let runs = []
  for span in spans
    if span[2] <= 0
      continue
    endif
    call extend(runs, HexPairPagedTextRuns(getline(span[0]),
          \ strpart(theirs, span[1], span[2]), span[1]))
  endfor
  return HexPairPagedTextPositions(spans, runs)
endfunction

" The matches of the current pattern, and the marks, over the visible
" lines. Both are about the FILE - the page as it was read - so neither
" looks at the buffer at all; see HexPairPagedFindPositions() for why the
" search is a slice of the page and not the whole of it.
function! s:TextFindPositions(first, last) abort
  let hex = get(b:, 'hexpair_page_hex', '')
  let span = s:find.bytes
  if span <= 0 || s:find.hex ==# '' || hex ==# ''
    return []
  endif
  let spans = s:TextSpans(a:first, a:last)
  if empty(spans)
    return []
  endif
  let bytes = strlen(hex) / 2
  let to = spans[-1][1] + spans[-1][2] + 1
  let to = to > bytes ? bytes : to
  let from = spans[0][1] - (span - 1)
  let from = from < 0 ? 0 : from
  if from >= to
    return []
  endif
  let slice = strpart(hex, from * 2, (to - from) * 2)
  let runs = []
  let at = 0
  while 1
    let idx = HexPairPagedFindInHex(slice, s:find.hex, at, 1)
    if idx < 0
      break
    endif
    let at = idx + 2
    call add(runs, [from + idx / 2, span])
  endwhile
  return HexPairPagedTextPositions(spans, runs)
endfunction

function! s:TextMarkPositions(first, last) abort
  let marks = s:MarksOf(b:hexpair_page_file)
  if empty(marks) || b:hexpair_page_len <= 0
    return []
  endif
  let runs = []
  for name in keys(marks)
    let off = marks[name] - b:hexpair_page_base
    if off >= 0 && off < b:hexpair_page_len
      call add(runs, [off, 1])
    endif
  endfor
  return HexPairPagedTextPositions(s:TextSpans(a:first, a:last), runs)
endfunction

" Replace the buffer with exactly a:lines, without making it an undoable
" edit (see s:LoadPage() for why).
function! s:SetLines(lines) abort
  let save_ul = &l:undolevels
  setlocal noreadonly modifiable
  try
    setlocal undolevels=-1
    silent %delete _
    call setline(1, a:lines)
  finally
    let &l:undolevels = save_ul
  endtry
endfunction

" The same lines, as an ORDINARY edit: one undo step, and the history
" before it kept. s:SetLines() clears that history on purpose, because it
" is how a page is REPLACED (s:LoadPage() says why) - but a replacement
" is an edit like any other and has to be undoable like one.
"
" The delete and the setline are joined into one undo block, or a single
" u would put back an empty buffer. undojoin refuses right after an undo,
" which is not an error worth stopping for.
function! s:SetLinesUndoable(lines) abort
  setlocal noreadonly modifiable
  silent %delete _
  try
    undojoin
  catch /E790/
  endtry
  call setline(1, a:lines)
endfunction

" The text view: the page's bytes between the two banner lines. No ruler
" here - there are no columns to number in a page of raw text, and the
" banner is matched by its exact text (s:TextBodyRange()), so the view
" has to hold those two lines and nothing else around the body.
function! s:SetViewLines(lines) abort
  call s:SetLines([b:hexpair_banner_top] + a:lines + [b:hexpair_banner_bottom])
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
    call s:ClearMarkings()
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
    call s:ClearMarkings()
    call s:SetLines(s:HexViewLines(readfile(dump)))
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

command! -bar -bang -nargs=+ -complete=file HexPairOpen
      \ call s:Open('<bang>' ==# '!', <f-args>)
command! -bar -bang HexPairPageNext call s:PageNext('<bang>' ==# '!')
command! -bar -bang HexPairPagePrev call s:PagePrev('<bang>' ==# '!')
command! -bar -bang -nargs=1 HexPairPageGoto
      \ call s:PageGotoText(<q-args>, '<bang>' ==# '!')
command! -bar -bang -nargs=1 HexPairGoOffset
      \ call s:GotoOffset(<q-args>, '<bang>' ==# '!')
command! -bar HexPairPages call s:Pages()
command! -bar HexPairSelection call s:Selection()
command! -bar HexPairInspect call s:Inspect()
command! -bar -nargs=1 HexPairMark call s:SetMark(<q-args>)
command! -bar -nargs=1 -complete=customlist,HexPairPagedMarkComplete
      \ HexPairMarkDelete call s:DeleteMark(<q-args>)
command! -bar -bang -nargs=1 -complete=customlist,HexPairPagedMarkComplete
      \ HexPairGoMark call s:GoMark(<q-args>, '<bang>' ==# '!')
command! -bar HexPairMarks call s:Marks()
command! -bar -bang -nargs=? -complete=file HexPairDiff
      \ call s:Diff(<q-args>, '<bang>' ==# '!')
command! -bar -bang -nargs=* HexPairFind call s:Find(<q-args>, '<bang>' ==# '!')
command! -bar -nargs=+ HexPairFindText call s:FindText(<q-args>)
command! -bar HexPairFindNext call s:FindRepeat(1)
command! -bar HexPairFindPrev call s:FindRepeat(0)
command! -bar -nargs=+ HexPairReplace call s:Replace(<q-args>)
command! -bar -nargs=+ HexPairReplaceAllInPage call s:ReplaceAll(<q-args>)
command! -bar HexPairDiffNext call s:DiffJump(1)
command! -bar HexPairDiffPrev call s:DiffJump(0)
command! -bar -nargs=? HexPairSplit  call s:SplitView(0, <f-args>)
command! -bar -nargs=? HexPairVSplit call s:SplitView(1, <f-args>)

" ---------------------------------------------------------------------------
" The same commands under a shorter name
" ---------------------------------------------------------------------------
"
" ":HexPairReplaceAllInPage" is a lot to type at a : prompt, and the long
" names are the documented ones precisely because they say what they do -
" so every command gets an "HP" alias as well, with the same arguments,
" the same bang and the same completion. Each alias is a one-line command
" that runs the long one, so there is one implementation and no way for
" the two to drift.
"
" g:hexpair_short_commands = 0 leaves the namespace alone, for anyone
" whose own commands start with HP.
if g:hexpair_short_commands
  for [s:flags, s:short, s:long] in [
        \ ['-bar', 'HPToggle', 'HexPairToggle'],
        \ ['-bar', 'HPGoHex', 'HexPairGoHex'],
        \ ['-bar', 'HPGoAscii', 'HexPairGoAscii'],
        \ ['-bar', 'HPSwap', 'HexPairSwap'],
        \ ['-bar', 'HPRefresh', 'HexPairRefresh'],
        \ ['-bar -bang -nargs=+ -complete=file', 'HPOpen', 'HexPairOpen'],
        \ ['-bar -bang', 'HPPageNext', 'HexPairPageNext'],
        \ ['-bar -bang', 'HPPagePrev', 'HexPairPagePrev'],
        \ ['-bar -bang -nargs=1', 'HPPageGoto', 'HexPairPageGoto'],
        \ ['-bar -bang -nargs=1', 'HPGoOffset', 'HexPairGoOffset'],
        \ ['-bar', 'HPPages', 'HexPairPages'],
        \ ['-bar', 'HPSelection', 'HexPairSelection'],
        \ ['-bar', 'HPInspect', 'HexPairInspect'],
        \ ['-bar -nargs=1', 'HPMark', 'HexPairMark'],
        \ ['-bar -nargs=1 -complete=customlist,HexPairPagedMarkComplete',
        \  'HPMarkDelete', 'HexPairMarkDelete'],
        \ ['-bar -bang -nargs=1 -complete=customlist,HexPairPagedMarkComplete',
        \  'HPGoMark', 'HexPairGoMark'],
        \ ['-bar', 'HPMarks', 'HexPairMarks'],
        \ ['-bar -bang -nargs=? -complete=file', 'HPDiff', 'HexPairDiff'],
        \ ['-bar', 'HPDiffNext', 'HexPairDiffNext'],
        \ ['-bar', 'HPDiffPrev', 'HexPairDiffPrev'],
        \ ['-bar -bang -nargs=*', 'HPFind', 'HexPairFind'],
        \ ['-bar -nargs=+', 'HPFindText', 'HexPairFindText'],
        \ ['-bar', 'HPFindNext', 'HexPairFindNext'],
        \ ['-bar', 'HPFindPrev', 'HexPairFindPrev'],
        \ ['-bar -nargs=+', 'HPReplace', 'HexPairReplace'],
        \ ['-bar -nargs=+', 'HPReplaceAllInPage', 'HexPairReplaceAllInPage'],
        \ ['-bar -nargs=?', 'HPSplit', 'HexPairSplit'],
        \ ['-bar -nargs=?', 'HPVSplit', 'HexPairVSplit'],
        \ ]
    " <bang> and <args> are only substituted where the flags allow them,
    " so the body is built to match what this command takes.
    let s:body = s:long
          \ . (s:flags =~# '-bang' ? '<bang>' : '')
          \ . (s:flags =~# '-nargs' ? ' <args>' : '')
    execute printf('command! %s %s %s', s:flags, s:short, s:body)
  endfor
  unlet! s:flags s:short s:long s:body
endif


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
" Both modes: from Visual mode it reports the selection being made (the
" :<C-U> leaves Visual mode, which is what sets '< and '>), from Normal
" mode the one made last.
" The Visual one puts the selection back; the Normal one reports the
" selection made last.
xnoremap <silent> <Plug>(HexPairSelection) :<C-U>call <SID>Selection(1)<CR>
nnoremap <silent> <Plug>(HexPairSelection) :<C-U>HexPairSelection<CR>
nnoremap <silent> <Plug>(HexPairInspect) :<C-U>HexPairInspect<CR>
nnoremap <silent> <Plug>(HexPairMarks) :<C-U>HexPairMarks<CR>
" The prompting counterparts of the commands that need an argument.
nnoremap <silent> <Plug>(HexPairGoMark) :<C-U>call <SID>GoMarkPrompt(0)<CR>
nnoremap <silent> <Plug>(HexPairGoMarkForce) :<C-U>call <SID>GoMarkPrompt(1)<CR>
nnoremap <silent> <Plug>(HexPairFind) :<C-U>call <SID>FindPrompt()<CR>
nnoremap <silent> <Plug>(HexPairFindText) :<C-U>call <SID>FindTextPrompt()<CR>
nnoremap <silent> <Plug>(HexPairFindNext) :<C-U>HexPairFindNext<CR>
nnoremap <silent> <Plug>(HexPairFindPrev) :<C-U>HexPairFindPrev<CR>
nnoremap <silent> <Plug>(HexPairDiffNext) :<C-U>HexPairDiffNext<CR>
nnoremap <silent> <Plug>(HexPairDiffPrev) :<C-U>HexPairDiffPrev<CR>
" Turning the markings off is what the bang on either command does, and
" both are worth a key: they are how a page stops being covered in
" matches once the thing has been found.
nnoremap <silent> <Plug>(HexPairFindClear) :<C-U>HexPairFind!<CR>
nnoremap <silent> <Plug>(HexPairDiffClear) :<C-U>HexPairDiff!<CR>

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
