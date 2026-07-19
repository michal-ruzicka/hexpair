" hexpair.vim - Hex viewing with hex<->ASCII pair highlighting
" Maintainer:  Michal Růžička <ruzicka.mich@gmail.com>
" URL:         https://github.com/michal-ruzicka/hexpair
" Version:     1.0.0
" Date:        2026-07-19
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
" Command:          :HexPairToggle
" Mapping:          none by default; map <Plug>(HexPairToggle) in your vimrc
"
" Configuration (set in your vimrc before the plugin loads):
"   g:hexpair_bytes_per_line   bytes per dump line (default 16)
"   g:hexpair_debug            set to 1 to echo position-mapping traces
"                              (inspect with :messages)
"   HexPairActive, HexPairMirror  highlight groups (cursor side / counterpart)

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

" Highlight groups for the byte-pair highlight:
"   HexPairActive - the byte in the column the cursor is in (subtle)
"   HexPairMirror - its counterpart in the other column (prominent)
" Users may redefine either group, e.g.:
"   highlight HexPairMirror ctermbg=52 guibg=#5f0000
highlight default HexPairActive cterm=underline gui=underline
highlight default link HexPairMirror IncSearch

" ---------------------------------------------------------------------------
" Layout helpers
" ---------------------------------------------------------------------------

" The dump is always produced with 'xxd -g 1 -c N', which yields a fixed
" layout (1-based columns):
"
"   00000000: 48 65 6c 6c 6f 20 57 6f 72 6c 64 21 0a 0a 0a 0a  Hello World!....
"   |offset |^ hex area (3 chars per byte, last byte has no    ^ ASCII area
"            |trailing space)                                  |
"            hexstart                                          asciistart
"
" Returns [bytes_per_line, hexstart, hexend, asciistart].
function! s:Layout() abort
  " Use the per-buffer value captured when the dump was generated, so that
  " changing g:hexpair_bytes_per_line while a dump is open (or using
  " different values in different buffers) cannot desynchronize the layout
  " arithmetic from the actual dump geometry.
  let n = get(b:, 'hexpair_n', g:hexpair_bytes_per_line)
  let hexstart   = 11                      " 8 hex digits + ': '
  let hexend     = hexstart + 3 * n - 2    " last hex digit of the last byte
  let asciistart = hexend + 3              " two spaces after the hex area
  return [n, hexstart, hexend, asciistart]
endfunction

" ---------------------------------------------------------------------------
" Pair highlighting
" ---------------------------------------------------------------------------

function! s:ClearHighlight() abort
  if exists('w:hexpair_ids')
    for id in w:hexpair_ids
      silent! call matchdelete(id)
    endfor
  endif
  let w:hexpair_ids = []
endfunction

function! s:Highlight() abort
  call s:ClearHighlight()
  if !get(b:, 'hexpair_active', 0)
    return
  endif

  let [n, hexstart, hexend, asciistart] = s:Layout()
  let lnum    = line('.')
  let col     = col('.')
  let linelen = strlen(getline('.'))

  " Determine the byte index (0 .. n-1) from the cursor column and remember
  " which column the cursor is in - the counterpart gets the prominent
  " highlight, the cursor side only the subtle one.
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

  " Skip padding on a short last line (fewer than n bytes): if there is no
  " ASCII character at the computed position, the byte does not exist.
  if asciistart + idx > linelen
    return
  endif

  " Highlight both representations of the byte: two hex digits + one
  " ASCII character, with the group chosen by cursor side.
  let hexgrp   = in_hex ? 'HexPairActive' : 'HexPairMirror'
  let asciigrp = in_hex ? 'HexPairMirror' : 'HexPairActive'
  call add(w:hexpair_ids,
        \ matchaddpos(hexgrp,   [[lnum, hexstart + idx * 3, 2]]))
  call add(w:hexpair_ids,
        \ matchaddpos(asciigrp, [[lnum, asciistart + idx, 1]]))
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

" Strip one dump line down to its hex payload.  Steps (formerly a sed/tr
" pipeline, rewritten in VimScript so the plugin also works on Windows,
" where sed and tr are not available):
"   1. strip leading whitespace (so bare hex lines may be indented for
"      alignment without being eaten by the double-space rule below),
"   2. strip everything up to the first ':' (the offset column; lines
"      without a colon are left intact, so bare inserted hex lines work),
"   3. strip everything from the first run of two spaces (the ASCII
"      column, including the padding of a short last line),
"   4. drop any remaining non-hex characters as a safety net.
function! s:StripDumpLine(line) abort
  let l = substitute(a:line, '^\s*', '', '')
  let l = substitute(l, '^[^:]*:', '', '')
  let l = substitute(l, '  .*$', '', '')
  return substitute(l, '[^0-9a-fA-F ]', '', 'g')
endfunction

" Convert the dump back to binary while ignoring the offset and ASCII
" columns entirely, so that lines inserted or reordered by the user do not
" need correct offsets (plain 'xxd -r' seeks according to them and breaks
" on edited dumps).  The stripped buffer is fed to 'xxd -r -p', which reads
" free-form hex pairs and is whitespace-insensitive.
" Consequence: within the hex area keep bytes separated by at most ONE
" space - a double space is interpreted as the start of the ASCII column.
function! s:ReverseDump() abort
  let lines = map(getline(1, '$'), {_, l -> s:StripDumpLine(l)})
  silent! undojoin
  call setline(1, lines)
  silent execute '%!' . s:xxd . ' -r -p'
endfunction

" ---------------------------------------------------------------------------
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

" 0-based byte offset of the byte under the cursor in the DUMP buffer.
" Bytes on preceding lines are counted from their actual (stripped) hex
" content, so the result stays exact even after lines were inserted,
" deleted or reordered.  On the current line the byte index is likewise
" derived from content: the number of complete hex pairs actually present
" before the cursor - which stays correct on edited lines (bare inserted
" lines, extra bytes appended into a line) where layout coordinates would
" be wrong.  Only when the cursor sits in the ASCII column (detected by a
" double space before it) is the index mapped by layout.
function! s:DumpOffset() abort
  let [n, hexstart, hexend, asciistart] = s:Layout()
  let prefix = strpart(getline('.'), 0, col('.') - 1)
  if prefix =~# '  '
    " A double space before the cursor means the hex payload of this line
    " ended (same rule as the reverse conversion): the cursor is in the
    " ASCII column - map it by layout.
    let [idx, l:unused] = s:CursorByte()
  else
    let stripped = substitute(prefix, '^\s*', '', '')
    let stripped = substitute(stripped, '^[^:]*:', '', '')
    let idx = strlen(substitute(stripped, '[^0-9a-fA-F]', '', 'g')) / 2
  endif
  let off = idx
  for line in getline(1, line('.') - 1)
    let off += strlen(substitute(s:StripDumpLine(line), ' ', '', 'g')) / 2
  endfor
  return off
endfunction

" [lnum, col] of the given 0-based byte offset in a canonical dump; the
" column points at the first hex digit of the byte (HEX column).
function! s:DumpPos(off) abort
  let [n, hexstart, hexend, asciistart] = s:Layout()
  return [a:off / n + 1, hexstart + (a:off % n) * 3]
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
  return line2byte(lnum) - 1 + a:pos.wcol + (lnum == 1 ? a:pos.bom : 0)
endfunction

" ---------------------------------------------------------------------------
" Safe writing while in hex mode
" ---------------------------------------------------------------------------

" Before a write: convert the dump back to binary so the file on disk gets
" the real content, not the textual dump.
function! s:PreWrite() abort
  if !get(b:, 'hexpair_active', 0)
    return
  endif
  let b:hexpair_off = s:DumpOffset()
  call s:ReverseDump()
endfunction

" After the write: re-create the dump so the user keeps working in hex
" mode, with the cursor back on the SAME BYTE (not the same screen
" coordinates - offsets of all lines may have shifted if bytes were
" inserted or deleted).
function! s:PostWrite() abort
  if !get(b:, 'hexpair_active', 0)
    return
  endif
  silent execute '%!' . s:xxd . ' -g 1 -c ' . b:hexpair_n
  if exists('b:hexpair_off')
    call cursor(s:DumpPos(b:hexpair_off))
    unlet b:hexpair_off
  endif
  setlocal nomodified
  call s:Highlight()
  redraw!
endfunction

" ---------------------------------------------------------------------------
" Mode switching
" ---------------------------------------------------------------------------

function! s:ToHex() abort
  let s:xxd = s:ResolveXxd()
  if s:xxd ==# ''
    echohl ErrorMsg
    echomsg 'hexpair: xxd not found in PATH nor in $VIMRUNTIME'
    echohl None
    return
  endif

  " If the buffer was NOT loaded in binary mode (plain 'vim file' instead of
  " 'vim -b file'), Vim has already applied read-time conversions: CR
  " stripping for fileformat=dos, possible fileencoding transcoding, etc.
  " Setting 'binary' now cannot undo those, so re-read the file with ++bin
  " to get the exact on-disk bytes.  This is only possible for an unmodified
  " buffer backed by a readable file; otherwise fall back to dumping the
  " in-memory content and warn the user.
  let off = -1
  if !&l:binary
    if !&l:modified && filereadable(expand('%'))
      " Capture the cursor byte offset BEFORE the reload, in file-byte
      " terms: the reload changes the buffer content (BOM bytes and CRs
      " materialize, fileencoding transcoding is undone) while the cursor
      " keeps its old line/column coordinates, which would then point at
      " a different byte.
      let pos = s:PreReloadPos()
      silent edit ++bin
      let off = s:PostReloadOffset(pos)
    else
      setlocal binary
      echohl WarningMsg
      echomsg 'hexpair: buffer not loaded in binary mode and cannot be'
            \ 'reloaded; the dump shows buffer content, not on-disk bytes'
      echohl None
    endif
  endif

  " Remember buffer-local settings so they can be restored on toggle-off.
  " Taken AFTER the possible ++bin reload so that toggling off keeps the
  " buffer in a state consistent with its (binary) content.
  let b:hexpair_saved = {
        \ 'binary':   &l:binary,
        \ 'eol':      &l:eol,
        \ 'filetype': &l:filetype,
        \ 'modified': &l:modified,
        \ }

  " Note: 'eol' is deliberately left as detected by the binary read - it
  " controls whether the final newline byte is passed to the filter, so
  " forcing 'noeol' here would hide a genuine trailing 0a from the dump.

  " Snapshot the line width for this buffer: the dump about to be
  " generated is laid out with this value, and all later position and
  " highlight arithmetic must keep using it even if the global setting
  " changes meanwhile.
  let b:hexpair_n = g:hexpair_bytes_per_line

  " Convert, then place the cursor on the SAME BYTE it was on in the
  " normal view - in the HEX column of the dump.  If the offset was not
  " already captured before a ++bin reload, compute it now from the
  " (binary) buffer.
  if off < 0
    let off = s:BufOffset()
  endif
  if get(g:, 'hexpair_debug', 0)
    echomsg printf('hexpair ToHex: pos=%d,%d off=%d -> dump target %s',
          \ line('.'), col('.'), off, string(s:DumpPos(off)))
  endif
  silent execute '%!' . s:xxd . ' -g 1 -c ' . b:hexpair_n
  call cursor(s:DumpPos(off))
  if get(g:, 'hexpair_debug', 0)
    echomsg printf('hexpair ToHex: landed %d,%d', line('.'), col('.'))
  endif

  setlocal filetype=xxd
  let b:hexpair_active = 1

  " Only mark the buffer modified if it really was before the conversion;
  " the dump itself is just a different view of the same content.
  if !b:hexpair_saved.modified
    setlocal nomodified
  endif

  " Buffer-local autocommands: pair highlighting + write safety.
  augroup HexPairBuffer
    autocmd! * <buffer>
    autocmd CursorMoved,CursorMovedI <buffer> call s:Highlight()
    autocmd BufWinLeave              <buffer> call s:ClearHighlight()
    autocmd BufWritePre              <buffer> call s:PreWrite()
    autocmd BufWritePost             <buffer> call s:PostWrite()
  augroup END

  call s:Highlight()
  redraw!
endfunction

function! s:FromHex() abort
  " Remove the buffer-local autocommands first.
  augroup HexPairBuffer
    autocmd! * <buffer>
  augroup END
  call s:ClearHighlight()

  " Convert back, then place the cursor on the SAME BYTE it was on in the
  " dump; :goto positions by byte offset and lands on the character that
  " contains the byte, which handles multibyte encodings correctly.
  let off = s:DumpOffset()
  if get(g:, 'hexpair_debug', 0)
    echomsg printf('hexpair FromHex: dumppos=%d,%d off=%d goto=%d',
          \ line('.'), col('.'), off, off + 1)
  endif
  call s:ReverseDump()
  silent execute 'goto ' . (off + 1)
  if get(g:, 'hexpair_debug', 0)
    echomsg printf('hexpair FromHex: landed %d,%d line2byte-check=%d',
          \ line('.'), col('.'), line2byte(line('.')) + col('.') - 2)
  endif

  " The silent filter plus :goto can leave the display stale (the cursor
  " cell is drawn at its pre-conversion position until the next movement),
  " so force a full redraw.
  redraw!

  let b:hexpair_active = 0
  if exists('b:hexpair_n')
    unlet b:hexpair_n
  endif

  " Restore the settings saved by s:ToHex().
  if exists('b:hexpair_saved')
    let &l:binary   = b:hexpair_saved.binary
    let &l:eol      = b:hexpair_saved.eol
    let &l:filetype = b:hexpair_saved.filetype
    if !b:hexpair_saved.modified
      setlocal nomodified
    endif
    unlet b:hexpair_saved
  else
    setlocal filetype=
  endif
endfunction

function! s:Toggle() abort
  if get(b:, 'hexpair_active', 0)
    call s:FromHex()
  else
    call s:ToHex()
  endif
endfunction

" ---------------------------------------------------------------------------
" Column navigation
" ---------------------------------------------------------------------------

" Returns [idx, in_hex] for the byte the cursor is on or nearest to.
" Unlike s:Highlight(), this clamps: the offset column maps to byte 0, the
" area right of the ASCII column maps to the last byte, and a short last
" line clamps to its actual byte count - so the jump commands always have
" a sensible target.
function! s:CursorByte() abort
  let [n, hexstart, hexend, asciistart] = s:Layout()
  let col = col('.')
  if col <= hexend
    let in_hex = 1
    let idx = col < hexstart ? 0 : (col - hexstart) / 3
  else
    let in_hex = 0
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
  return [idx, in_hex]
endfunction

" Move the cursor to the given column ('hex', 'ascii', or 'swap' for the
" opposite one) while staying on the same byte, and refresh the pair
" highlight immediately.
function! s:JumpTo(target) abort
  if !get(b:, 'hexpair_active', 0)
    echohl WarningMsg | echomsg 'hexpair: hex mode is not active' | echohl None
    return
  endif
  let [n, hexstart, hexend, asciistart] = s:Layout()
  let [idx, in_hex] = s:CursorByte()
  let target = a:target ==# 'swap' ? (in_hex ? 'ascii' : 'hex') : a:target
  if target ==# 'hex'
    call cursor(line('.'), hexstart + idx * 3)
  else
    call cursor(line('.'), asciistart + idx)
  endif
  call s:Highlight()
endfunction

" ---------------------------------------------------------------------------
" Command and mappings
" ---------------------------------------------------------------------------

command! -bar HexPairToggle call s:Toggle()
command! -bar HexPairGoHex   call s:JumpTo('hex')
command! -bar HexPairGoAscii call s:JumpTo('ascii')
command! -bar HexPairSwap    call s:JumpTo('swap')

" No default key mappings are defined; map the <Plug> mappings (or the
" commands directly) in your vimrc, e.g.:
"   nmap §h <Plug>(HexPairToggle)
"   nmap §< <Plug>(HexPairGoHex)
"   nmap §> <Plug>(HexPairGoAscii)
"   nmap §- <Plug>(HexPairSwap)
nnoremap <silent> <Plug>(HexPairToggle)  :<C-U>HexPairToggle<CR>
nnoremap <silent> <Plug>(HexPairGoHex)   :<C-U>HexPairGoHex<CR>
nnoremap <silent> <Plug>(HexPairGoAscii) :<C-U>HexPairGoAscii<CR>
nnoremap <silent> <Plug>(HexPairSwap)    :<C-U>HexPairSwap<CR>

let &cpo = s:cpo_save
unlet s:cpo_save
