" hexpair - a ready-made set of mappings, to source from your own vimrc
" Maintainer:  Michal Růžička <ruzicka.mich@gmail.com>
" URL:         https://github.com/michal-ruzicka/hexpair
" License:     Vim License - same terms as Vim itself (see LICENSE.md
"              or :help license); SPDX-License-Identifier: Vim
"
" The plugin defines NO key mappings of its own - it provides commands and
" <Plug> targets, and which keys those go on is yours to decide. This file
" is one answer to that question, the one the maintainer uses, kept here so
" it can be sourced rather than copied.
"
" Add ONE line to your vimrc, after 'mapleader' is set:
"
"     runtime pack/*/start/hexpair/hexpair.vimrc
"
" That works on Linux, Windows and WSL alike, and needs no path of yours in
" it: 'runtimepath' already points at the per-user Vim directory of the
" platform - ~/.vim on Unix, ~/vimfiles on Windows - and :runtime searches
" it. An absolute `source ~/.vim/pack/...` would be wrong on Windows for
" exactly that reason, even though Vim does expand `~` there.
"
" If hexpair is installed by a plugin manager rather than as a package, its
" directory is already on 'runtimepath' by the time your vimrc gets that
" far, so the shorter form finds it:
"
"     runtime hexpair.vimrc
"
" Nothing here overwrites a mapping you already have: every key is checked
" first, and one that is taken is left alone. To use a different key for
" something, map it yourself BEFORE this line - or drop this line and copy
" what you want out of the file.

" The maintainer's name above is not ASCII; see plugin/hexpair.vim.
scriptencoding utf-8

if exists('g:loaded_hexpair_vimrc')
  finish
endif
let g:loaded_hexpair_vimrc = 1

" Line continuations below need the Vim default; a user's 'cpoptions' may
" have C in it, which turns every one of them into a truncated statement.
let s:save_cpo = &cpoptions
set cpoptions&vim

" One mapping, unless the keys are spoken for. <Leader> is expanded by the
" :map command itself, so it is expanded here as well to ask maparg() about
" the keys that will actually be used.
function! s:Map(mode, keys, target) abort
  let lead = exists('g:mapleader') ? g:mapleader : '\'
  let keys = substitute(a:keys, '<Leader>', escape(lead, '\&~'), 'g')
  if !empty(maparg(keys, a:mode))
    return
  endif
  " A <Plug> target has to stay remappable; an Ex command must not.
  let cmd = a:target =~# '^<Plug>' ? 'map' : 'noremap'
  execute a:mode . cmd . ' <silent> ' . a:keys . ' ' . a:target
endfunction

" --- The two views -------------------------------------------------------
" Toggle between the hex page view and the windowed text view of the same
" page.
call s:Map('n', '<Leader>h', '<Plug>(HexPairToggle)')
" The way back out: a plain buffer of a whole file toggled to hex comes
" back to its ordinary, unpaged, non-binary text view with the options it
" had before. A view opened as hex (vimhex, :HexPairOpen) has no such text
" view, so this refuses it and says why.
call s:Map('n', '<Leader>U', '<Plug>(HexPairUnhex)')

" Move between the columns of a dump: to the hex one, to the ASCII one, or
" to whichever one the cursor is not in - staying on the same byte.
call s:Map('n', '<Leader><', '<Plug>(HexPairGoHex)')
call s:Map('n', '<Leader>>', '<Plug>(HexPairGoAscii)')
call s:Map('n', '<Leader>-', '<Plug>(HexPairSwap)')

" Regenerate the offset and ASCII columns from the hex payload, without
" writing anything to disk.
call s:Map('n', '<Leader>r', '<Plug>(HexPairRefresh)')

" --- Pages and positions -------------------------------------------------
call s:Map('n', '<Leader>j', '<Plug>(HexPairPageNext)')
call s:Map('n', '<Leader>k', '<Plug>(HexPairPagePrev)')
" The same, discarding unwritten changes without asking - for reading
" through a file rather than editing it.
call s:Map('n', '<Leader>J', ':HexPairPageNext!<CR>')
call s:Map('n', '<Leader>K', ':HexPairPagePrev!<CR>')

" Ask which page to go to ($ for the last, +N / -N to step), and the same
" discarding unwritten changes.
call s:Map('n', '<Leader>g', '<Plug>(HexPairPageGoto)')
call s:Map('n', '<Leader>G', '<Plug>(HexPairPageGotoForce)')

" Ask which byte to go to (decimal, or 0x-prefixed; 1-based, the way
" <Leader>? reports it, and +N / -N steps from where the cursor is), and
" the same discarding unwritten changes.
call s:Map('n', '<Leader>b', '<Plug>(HexPairGoOffset)')
call s:Map('n', '<Leader>B', '<Plug>(HexPairGoOffsetForce)')

" Where we are: page X of Y, the byte range shown, the file size, and the
" byte under the cursor in the form <Leader>b and vimhex's @BYTE take.
call s:Map('n', '<Leader>?', '<Plug>(HexPairPages)')

" Bring the other scroll-bound view onto the byte this one is on. A jump does
" that by itself; moving the cursor by hand does not, because that is about
" this window and not about the file - and 'scrollbind' promises that windows
" move together, not that they are on the same byte. So after a while they are
" looking at the same lines and different bytes. This is the way back.
call s:Map('n', '<Leader>=', '<Plug>(HexPairSyncViews)')

" --- Reading the bytes ---------------------------------------------------
" The bytes at the cursor as the numbers they could be - 8/16/32/64-bit,
" signed and unsigned, both endiannesses, both IEEE 754 floats - and as
" text: UTF-8, UTF-16, UTF-32, with the character's name and Unicode block.
"
" Mapped globally on purpose. It works in an ORDINARY buffer as well as in a
" hex view - what is this character, is that a NBSP, does this file start
" with a BOM - and there it says so when the bytes it is showing are Vim's
" rather than the file's. See |hexpair-inspect-anywhere|.
call s:Map('n', '<Leader>i', '<Plug>(HexPairInspect)')
" ... and the same reading the other way round: ask for a character and put
" its bytes in, in g:hexpair_insert_encoding (utf-8 unless you say
" otherwise; what you type may begin with ++enc=NAME for one insert).
" The capital of the key that reads them, because it writes what that
" reads.
call s:Map('n', '<Leader>I', '<Plug>(HexPairInsertChar)')

" How many bytes the selection covers, and which. Worth having in Visual
" mode as well as Normal: there it reports the selection being made and
" keeps it, here the one made last.
call s:Map('n', '<Leader>s', '<Plug>(HexPairSelection)')
call s:Map('x', '<Leader>s', '<Plug>(HexPairSelection)')

" --- Marks ---------------------------------------------------------------
" Positions in the FILE, not lines in a buffer, so a page turn does not
" disturb them and both views of one file share them. All four are under
" <Leader>m: list, set, delete, go - the last two ask for the name and
" complete the ones that exist.
call s:Map('n', '<Leader>ml', '<Plug>(HexPairMarks)')
call s:Map('n', '<Leader>ms', '<Plug>(HexPairMark)')
call s:Map('n', '<Leader>md', '<Plug>(HexPairMarkDelete)')
call s:Map('n', '<Leader>mg', '<Plug>(HexPairGoMark)')
" ... and going there discarding unwritten changes, as :HexPairGoMark! does.
call s:Map('n', '<Leader>mG', '<Plug>(HexPairGoMarkForce)')

" --- Searching -----------------------------------------------------------
" Ask for the bytes to find ('?' matches any nibble), or for a string to
" find as its bytes; then next and previous match. f rather than n, which
" is Vim's own.
call s:Map('n', '<Leader>/', '<Plug>(HexPairFind)')
call s:Map('n', '<Leader>t', '<Plug>(HexPairFindText)')
call s:Map('n', '<Leader>f', '<Plug>(HexPairFindNext)')
call s:Map('n', '<Leader>F', '<Plug>(HexPairFindPrev)')
" Stop marking the matches.
call s:Map('n', '<Leader>c', '<Plug>(HexPairFindClear)')

" --- Walking your own edits ----------------------------------------------
" Next and previous run of bytes edited and not yet written, on this page -
" the same idea as ] and [ below, applied to what you have changed rather
" than to what another file has.
call s:Map('n', '<Leader>e', '<Plug>(HexPairModifiedNext)')
call s:Map('n', '<Leader>E', '<Plug>(HexPairModifiedPrev)')
" What the file on disk has here - the byte under the cursor, or a whole
" Visual selection - beside what the buffer now holds. The marking says
" which bytes you changed; the byte it covers is the new one, and this is
" what the old one was. The lowercase of <Leader>D, which asks the same
" question of another file.
call s:Map('n', '<Leader>d', '<Plug>(HexPairModifiedShow)')
call s:Map('x', '<Leader>d', '<Plug>(HexPairModifiedShow)')

" --- Comparing with another file -----------------------------------------
" Next and previous CHANGE against the file :HexPairDiff compares with - a
" run of differing bytes is one change however long it is - and ] and [ as
" Vim's own ]c and [c do in a diff. Then: stop comparing.
call s:Map('n', '<Leader>]', '<Plug>(HexPairDiffNext)')
call s:Map('n', '<Leader>[', '<Plug>(HexPairDiffPrev)')
call s:Map('n', '<Leader>C', '<Plug>(HexPairDiffClear)')
" What the other file actually holds here - the byte under the cursor, or a
" whole Visual selection. The marking says which bytes differ and stops
" there; on a page past the end of the other file every byte is marked and
" this is what says why.
call s:Map('n', '<Leader>D', '<Plug>(HexPairDiffShow)')
call s:Map('x', '<Leader>D', '<Plug>(HexPairDiffShow)')

" --- What has no <Plug> target -------------------------------------------
" Commands that take an argument cannot have one, so they are typed - or
" wrapped in a mapping of your own:
"
"     :HexPairOpen bigfile.bin        page a file WITHOUT loading it
"     :HexPairFind de ad be ef        find those bytes anywhere in the file
"     :HexPairFindText PK             the bytes of a string
"     :HexPairReplace 11 22 33 44     over the match under the cursor
"     :HexPairReplaceAllInPage de ad be ef / 00 00 00 00
"     :HexPairDiff other.bin          mark what differs from that file
"     :HexPairMark hdr                remember this byte as "hdr"
"     :HexPairSplit +1                a second view, one page on
"     :HexPairGoOffset +0x100         step from where the cursor is
"     :HexPairPageGoto $              the last page
"
" Every one of them also answers to a short "HP" name - :HPFind, :HPToggle,
" :HPReplaceAllInPage - with the same arguments, bang and completion.
" And from the shell, `vimhex FILE [PAGE|@BYTE]` and `vimhexdiff A B` open
" a file, or two side by side (hexpair.bashrc, next to this file).

" --- Statusline ----------------------------------------------------------
" HexPairStatus() reports the view, the page and the byte under the cursor
" ("hex 3/349 @0x50a01 (330241)"), and an empty string in every buffer
" hexpair has not touched, so one statusline serves both. Add it to yours:
"
"     set statusline=%f\ %h%w%m%r\ %{HexPairStatus()}%=%l,%c%V\ %P
"
" Called on every redraw, so on a Vim where the plugin is not installed the
" call would raise E117 - and Vim answers that by clearing 'statusline'
" altogether. A wrapper keeps the rest of the line safe:
"
"     function! StatuslineHexPair() abort
"       return exists('*HexPairStatus') ? HexPairStatus() : ''
"     endfunction

" --- Options -------------------------------------------------------------
" Every line below is the NON-default value: uncomment it to get the other
" behaviour, and note that options are read when the plugin loads, so they
" have to be set before it does - which a vimrc does by definition.
"
" Wider dump lines for a wide terminal (default 16). g:hexpair_page_size
" must stay a positive multiple of this; the default 128 KiB is a multiple
" of 32, while a width such as 24 would need the page size set to match.
"let g:hexpair_bytes_per_line = 32
"
" More of the file on screen at once (default 128 KiB = 8192 dump lines). A
" page is an ordinary Vim buffer, so everything costs what that many lines
" cost; :HexPairGoOffset reaches any byte directly, so a bigger page mostly
" buys a longer wait.
"let g:hexpair_page_size = 1024 * 1024
"
" Do NOT ask before a write that changes the page's length (default 1, ask).
"let g:hexpair_page_confirm = 0
"
" Leave the global 'paste' option alone (default 1: keep it on while the
" cursor is in a hex buffer, and restore it when the cursor leaves).
"let g:hexpair_paste = 0
"
" Number the byte columns on a ruler line between the banner and the dump
" (default 0, no ruler).
"let g:hexpair_ruler = 1
"
" Do NOT mark the bytes edited and not yet written (default 1, mark them).
"let g:hexpair_show_modified = 0
"
" Do NOT underline the byte a mark stands on (default 1, underline it).
"let g:hexpair_show_marks = 0
"
" Make a plain :split of a hex page an independent view of the same file,
" with its own page and cursor (default 0: :split means what it means
" everywhere else in Vim, two windows onto one buffer).
"let g:hexpair_split_views = 1
"
" Do NOT pass a page turn on to the windows scroll-bound to this one
" (default 1, pass it on - which is what keeps `vimhexdiff` showing the
" same bytes on both sides).
"let g:hexpair_bind_pages = 0
"
" Do NOT define the short HP names (default 1, define them) - for when
" commands of your own start with HP.
"let g:hexpair_short_commands = 0
"
" Trace every mapping between a cursor position and a byte offset to
" :messages, for diagnosing a cursor that landed on the wrong byte.
"let g:hexpair_debug = 1

" --- Colours -------------------------------------------------------------
" The cursor's byte and its counterpart in the other column:
"highlight HexPairActive cterm=bold,underline gui=bold,underline
"highlight HexPairMirror ctermbg=224 ctermfg=88 guibg=#ffd7d7 guifg=#870000
"
" The page banner (and ruler) lines:
"highlight HexPairPageBanner ctermfg=244 guifg=#808080
"
" The bytes edited and not yet written, the bytes that differ from the file
" being compared with, and the matches of a search. Their defaults LINK to
" the colour scheme's diff and search groups, which is what makes them look
" like the rest of the editor - stock Vim and every scheme shipped with it
" resolve to something readable, so this is taste rather than repair. If
" you do override, set a foreground AND a background: giving one and
" leaving the other to the scheme is how the two land on top of each other.
" Note that these are light-background pastels and the cterm numbers want a
" 256-colour terminal:
"highlight HexPairModified ctermbg=224 ctermfg=88  guibg=#ffd7d7 guifg=#870000
"highlight HexPairDiff     ctermbg=194 ctermfg=22  guibg=#d7ffd7 guifg=#005f00
"highlight HexPairFind     ctermbg=229 ctermfg=94  guibg=#ffffaf guifg=#875f00
"
" The byte a mark stands on (default: bold underline and no colour at all,
" so that it coexists with the three above instead of competing with them):
"highlight HexPairMark ctermbg=195 ctermfg=23 guibg=#d7ffff guifg=#005f5f

let &cpoptions = s:save_cpo
unlet s:save_cpo
