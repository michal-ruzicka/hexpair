" hexpair_paged.vim - Paged hex viewing for large files
" Maintainer:  Michal Růžička <ruzicka.mich@gmail.com>
" URL:         https://github.com/michal-ruzicka/hexpair
" License:     Vim License - same terms as Vim itself (see LICENSE.md
"              or :help license); SPDX-License-Identifier: Vim
"
" Views one configurable-size PAGE of an arbitrarily large file as a
" hex dump with absolute file offsets, without ever loading the whole
" file into a Vim buffer. A separate file from plugin/hexpair.vim (see
" "Vim version gate" below) - not sourced by it and not sourcing it;
" the buffer-local state and script-local functions of the two modes
" are entirely independent, deliberately, and a buffer is in exactly
" one mode or the other, never both.
"
" Stage 1 of the planned feature: read-only paging and navigation.
" Writing (:w) is intentionally refused for now with a clear message;
" it will be implemented in a later stage (see CLAUDE.md).
"
" Command:          :HexPairOpen <file> [page]
" Mapping:          none by default; map <Plug>(HexPairPage...) in your vimrc
"
" Configuration (set in your vimrc before the plugin loads):
"   g:hexpair_page_size   bytes per page (default 1 MiB); must be a
"                         positive multiple of g:hexpair_bytes_per_line
"
" ---------------------------------------------------------------------------
" Vim version gate
" ---------------------------------------------------------------------------
"
" The write path planned for a later stage requires readblob(),
" available since patch 8.2.4906; large absolute offsets require a
" 64-bit Number (+num64, standard on modern builds). Gating the WHOLE
" paged feature behind both avoids partial functionality that would
" depend on the Vim version in confusing ways. This check is factored
" into a function of an explicit boolean (rather than calling has()
" internally) so its failure branch - which cannot be produced by an
" actual old Vim in this project's test environment - can be tested
" directly by passing 0.

if exists('g:loaded_hexpair_paged')
  finish
endif

" 'cpoptions' must be normalized BEFORE any function using a backslash
" line continuation is defined below: under 'compatible' (the default
" with no vimrc, e.g. this project's own headless test harness),
" 'cpoptions' includes 'C', which disables line continuations
" entirely. Vim honours the CURRENT 'cpoptions' as it reads each line
" while sourcing, so resetting it here - before the version-gate
" function a few lines down - is what makes that function's (and every
" later one's) continuations parse correctly, regardless of the
" 'cpoptions' the caller had. Restored at the end of the file, and
" also before every early `finish` below, so a failed load cannot
" leave it altered for the rest of the session.
let s:cpo_save = &cpo
set cpo&vim

" Global (not script-local) so test/run-tests.sh can call it directly
" with both true and false without needing an actual unsupported Vim.
function! HexPairPagedGateMessage(supported) abort
  if a:supported
    return ''
  endif
  return 'hexpair: paged mode requires Vim patch 8.2.4906 or later with '
        \ . '+num64 (readblob(), 64-bit Numbers for large file offsets); '
        \ . 'this Vim does not qualify, paged commands are unavailable'
endfunction

let s:gate_msg = HexPairPagedGateMessage(has('patch-8.2.4906') && has('num64'))
if !empty(s:gate_msg)
  echohl ErrorMsg
  echomsg s:gate_msg
  echohl None
  let &cpo = s:cpo_save
  unlet s:cpo_save
  finish
endif
unlet s:gate_msg

let g:loaded_hexpair_paged = 1

" ---------------------------------------------------------------------------
" Configuration defaults
" ---------------------------------------------------------------------------

if !exists('g:hexpair_page_size')
  let g:hexpair_page_size = 1024 * 1024
endif

" Highlight group for the page banner (leading/trailing comment lines).
" xxd.vim's bundled syntax file defines no comment group to link to
" (only xxdAddress/xxdSep/xxdAscii, all tied to real dump lines), so
" this is the plugin's own, following the HexPairActive/HexPairMirror
" precedent in plugin/hexpair.vim.
highlight default link HexPairPageBanner Comment

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

" ---------------------------------------------------------------------------
" xxd resolution
" ---------------------------------------------------------------------------

" Duplicated from plugin/hexpair.vim's s:ResolveXxd(): identical logic,
" but VimScript gives each sourced file its own script-local scope, so
" a function defined there cannot be called from here. This is the
" only genuinely shared low-level helper between the two modes -
" everything else (layout, stripping, validation) has different
" semantics in paged mode (banner lines, absolute offsets, page base
" arithmetic), so is not worth sharing via an autoload/ layer.
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
" Page boundary arithmetic
" ---------------------------------------------------------------------------

" xxd widens its offset column past 8 hex digits once the offset
" reaches 4 GiB (16^8), and again at 64 GiB (16^9), and so on -
" verified empirically: a single dump can show "fffffffc:" immediately
" followed by "100000000:". s:Layout()-style column arithmetic in
" s:PagedLayout() assumes a FIXED width for the whole page, so a page
" must never straddle such a boundary. HexPairPagedBounds()/
" HexPairPagedTotalPages() below account for this by treating the byte
" range (0, total] as a sequence of width-uniform SEGMENTS, split at
" every boundary that falls inside it; within a segment, pages are
" plain fixed-size slices, so only the segment holding a boundary ever
" produces a page shorter than g:hexpair_page_size.
"
" Global (not script-local) and pure (no I/O, no buffer/window state):
" directly testable with a fabricated `total` far larger than any real
" test fixture, without needing an actual multi-GiB file.
function! HexPairPagedWidthBoundaries(total) abort
  let boundaries = []
  let b = 0x100000000
  while b < a:total
    call add(boundaries, b)
    let b = b * 16
  endwhile
  return boundaries
endfunction

" [base, len] (0-based byte offset, byte count) of page `idx` (0-based)
" for a file of `total` bytes with page size `size`. Returns [-1, -1]
" for an out-of-range index.
function! HexPairPagedBounds(idx, size, total) abort
  let segstart = 0
  let remaining = a:idx
  for boundary in HexPairPagedWidthBoundaries(a:total) + [a:total]
    let seglen = boundary - segstart
    let segpages = seglen > 0 ? (seglen + a:size - 1) / a:size : 0
    if remaining < segpages
      let base = segstart + remaining * a:size
      return [base, min([a:size, boundary - base])]
    endif
    let remaining -= segpages
    let segstart = boundary
  endfor
  return [-1, -1]
endfunction

" Total number of pages for a file of `total` bytes at page size
" `size` (0 for an empty file).
function! HexPairPagedTotalPages(size, total) abort
  let segstart = 0
  let n = 0
  for boundary in HexPairPagedWidthBoundaries(a:total) + [a:total]
    let seglen = boundary - segstart
    if seglen > 0
      let n += (seglen + a:size - 1) / a:size
    endif
    let segstart = boundary
  endfor
  return n
endfunction

" Hex digit width xxd uses for offsets in the same width-segment as
" `base` (constant across a whole page by construction - see above).
function! s:HexDigitWidth(base) abort
  return max([8, strlen(printf('%x', a:base))])
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

" Analogous to plugin/hexpair.vim's s:Layout(), but hexstart is
" DISCOVERED per page (from the buffer-local snapshot taken when the
" page was generated) rather than a hardcoded 11, because the offset
" column width is not fixed once absolute offsets are involved (see
" above). Returns [bytes_per_line, hexstart, hexend, asciistart].
function! s:PagedLayout() abort
  let n = b:hexpair_n
  let hexstart   = b:hexpair_page_hexstart
  let hexend     = hexstart + 3 * n - 2
  let asciistart = hexend + 3
  return [n, hexstart, hexend, asciistart]
endfunction

" ---------------------------------------------------------------------------
" Reverse conversion (stripping and validation only - Stage 1 has no
" write path yet; kept in sync now so a later stage's :w reuses this
" unchanged)
" ---------------------------------------------------------------------------

" Banner-aware counterpart of plugin/hexpair.vim's s:StripDumpLine():
" a banner line strips to nothing (zero bytes contributed); otherwise
" identical logic (offset up to the first ':', then the ASCII column,
" then a non-hex-character safety net).
function! s:PagedStripDumpLine(line) abort
  if s:IsBannerLine(a:line)
    return ''
  endif
  let l = substitute(a:line, '^\s*', '', '')
  let l = substitute(l, '^[^:]*:', '', '')
  let l = substitute(l, '  .*$', '', '')
  return substitute(l, '[^0-9a-fA-F ]', '', 'g')
endfunction

" Banner-aware counterpart of plugin/hexpair.vim's s:ValidateDump():
" skips banner lines entirely (their decorative text, e.g. decimal
" page/byte counts, must never be scanned as hex payload), otherwise
" identical rules. Mirrors s:PagedStripDumpLine() - keep them in sync.
function! s:PagedValidateDump() abort
  let digits = 0
  for lnum in range(1, line('$'))
    let line = getline(lnum)
    if s:IsBannerLine(line)
      continue
    endif
    let start = matchend(line, '^\s*')
    let colon = stridx(line, ':')
    if colon >= 0
      let start = colon + 1
    endif
    let end = match(line, '  ', start)
    if end < 0
      let end = strlen(line)
    endif
    let bad = match(line, '[^0-9a-fA-F ]', start)
    if bad >= 0 && bad < end
      return {'lnum': lnum, 'col': bad + 1,
            \ 'msg': printf('invalid character %s in the hex area (line %d, column %d)',
            \               string(matchstr(line, '.', bad)), lnum, bad + 1)}
    endif
    let digits += strlen(substitute(strpart(line, start, end - start),
          \                         '[^0-9a-fA-F]', '', 'g'))
  endfor
  if digits % 2
    return {'msg': 'odd number of hex digits - the last nibble would be dropped'}
  endif
  return {}
endfunction

" Thin global wrappers so test/run-tests.sh can exercise the banner-
" aware stripping/validation directly: Stage 1 has no write path yet
" (see s:WriteNotYetImplemented()), so nothing in the command surface
" currently calls these, and untested code has no place in this
" project (see CLAUDE.md, "every change ships with a test").
function! HexPairPagedStripLine(line) abort
  return s:PagedStripDumpLine(a:line)
endfunction

function! HexPairPagedValidate() abort
  return s:PagedValidateDump()
endfunction

" ---------------------------------------------------------------------------
" Pair highlighting (duplicated from plugin/hexpair.vim's
" s:Highlight()/s:ClearHighlight(): same visual behaviour, but keyed
" off b:hexpair_page_active and s:PagedLayout(), and skips the banner
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

function! s:PagedHighlight() abort
  call s:PagedClearHighlight()
  if !get(b:, 'hexpair_page_active', 0)
    return
  endif

  let lnum = line('.')
  if s:IsBannerLine(getline(lnum))
    return
  endif

  let [n, hexstart, hexend, asciistart] = s:PagedLayout()
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
  let b:hexpair_page_hexstart   = s:HexDigitWidth(base) + 2

  setlocal noreadonly modifiable
  silent %delete _
  silent execute '%!' . s:xxd . printf(' -s %d -l %d -g 1 -c %d %s',
        \ base, len, b:hexpair_n, shellescape(b:hexpair_page_file))
  call append(0, s:BannerTop(a:pageidx, totalpages, base, len, total,
        \ b:hexpair_page_file))
  call append(line('$'), s:BannerBottom(a:pageidx, totalpages))
  call cursor(2, b:hexpair_page_hexstart)

  setlocal filetype=xxd
  call s:ApplyBannerSyntax()
  setlocal nomodified
  let b:hexpair_page_active = 1
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
  " that a later :w might be attempted against that made-up path once
  " a real write path exists (Stage 1 happens to block this today only
  " because s:WriteNotYetImplemented() throws unconditionally).
  let file = fnamemodify(a:file, ':p')
  if s:ResolvePage(file, g:hexpair_page_size, page - 1)[0] < 0
    return
  endif

  enew
  setlocal buftype=acwrite bufhidden=hide noswapfile
  silent execute 'file ' . fnameescape(a:file . ' [hexpair page]')

  let b:hexpair_page_file = file
  let b:hexpair_page_size = g:hexpair_page_size

  augroup HexPairPagedBuffer
    autocmd! * <buffer>
    autocmd CursorMoved,CursorMovedI <buffer> call s:PagedHighlight()
    autocmd BufWinLeave              <buffer> call s:PagedClearHighlight()
    autocmd BufWriteCmd              <buffer> call s:WriteNotYetImplemented()
  augroup END

  call s:LoadPage(page - 1)
endfunction

" Stage 1 has no write path yet (planned for a later stage - see
" CLAUDE.md); buftype=acwrite without this would either silently do
" nothing or, worse, let Vim's default write logic run against the
" buffer's cosmetic display name, which is not the real file. A throw
" here - the same pattern plugin/hexpair.vim's s:PreWrite() uses to
" refuse an invalid dump - aborts :write as a genuine Vim error rather
" than an easily-missed message: confirmed 'modified' is never cleared
" by Vim just because a BufWriteCmd ran, but an actual error is harder
" to miss than an echomsg that scrolls past, and matches how a real
" write failure (e.g. disk full) would surface.
function! s:WriteNotYetImplemented() abort
  throw 'hexpair: writing a paged buffer is not implemented yet'
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
  call s:LoadPage(a:pageidx)
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
function! s:Pages() abort
  if !s:RequirePaged()
    return
  endif
  echo printf('hexpair: page %d of %d, offsets %d-%d of total %d bytes (%s)',
        \ b:hexpair_page_index + 1, b:hexpair_page_totalpages,
        \ b:hexpair_page_base + 1, b:hexpair_page_base + b:hexpair_page_len,
        \ b:hexpair_page_total, b:hexpair_page_file)
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
function! HexPairOpenFile(file, ...) abort
  call call('s:Open', [a:file] + a:000)
endfunction

" ---------------------------------------------------------------------------
" Command and mappings
" ---------------------------------------------------------------------------

command! -bar -nargs=+ -complete=file HexPairOpen call s:Open(<f-args>)
command! -bar -bang HexPairPageNext call s:PageNext('<bang>' ==# '!')
command! -bar -bang HexPairPagePrev call s:PagePrev('<bang>' ==# '!')
command! -bar -bang -nargs=1 HexPairPageGoto call s:PageGoto(str2nr(<q-args>), '<bang>' ==# '!')
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

let &cpo = s:cpo_save
unlet s:cpo_save
