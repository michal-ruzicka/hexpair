" hexpair - the Vim configuration the README demo is recorded with
"
" Maintainer:  Michal Růžička <ruzicka.mich@gmail.com>
" URL:         https://github.com/michal-ruzicka/hexpair
" License:     Vim License - same terms as Vim itself (see LICENSE.md
"              or :help license); SPDX-License-Identifier: Vim
"
" Not a recommended configuration and not an example of one. It exists so that
" the recording shows the PLUGIN rather than whatever the machine it was made on
" happens to have in ~/.vimrc - which is also why it is not simply that file,
" tempting as that is: a demo nobody else can reproduce is a screenshot.
"
" What it does take from the maintainer's own vimrc is the four settings the
" recording is actually about: the same <Leader>, the same 'showcmd' (which is
" what puts a half-typed mapping on the screen for a viewer to read), the same
" generous 'timeoutlen' (which is what leaves it there long enough), and a
" statusline carrying HexPairStatus().
"
" Used by docs/hexpair-demo.sh; see docs/hexpair-demo.tape.

set nocompatible
scriptencoding utf-8

" The plugin comes from the repository this file lives in, so the recording
" shows the working tree and not whatever is installed.
let s:repo = fnamemodify(resolve(expand('<sfile>:p')), ':h:h')
execute 'set runtimepath^=' . fnamemodify(s:repo, ':p')

filetype plugin indent on
syntax on

" 'background' has to be said out loud - a terminal cannot be asked - and then
" Vim's own default colours are left alone on purpose: a colour scheme paints a
" Normal background of its own over the terminal's, and what the recording is
" for is showing what hexpair's markings look like against a normal one.
set background=dark

" Vim asks the terminal what its background colour is, and under vhs the answer
" comes back late enough to be echoed by the shell after Vim has exited - a line
" of escape-sequence rubbish in the middle of the recording. Nothing here needs
" the answer: 'background' is set by hand two lines down.
set t_RB=

" No files left beside the fixtures, and no prompts that are not the plugin's.
set noswapfile
set nobackup
set noundofile
set shortmess+=I
set belloff=all

" `,` as <Leader>, and NOT the maintainer's own `§` - which is the one thing in
" here that is about the recorder rather than about the recording.
"
" vhs cannot type a non-ASCII character reliably: it sends those through a
" different path from ordinary keys, and they arrive out of order. `§` followed
" by `>` reaches Vim as `>` followed by `§`, so the mapping never matches and
" what the recording shows is Vim's `>` operator waiting for a motion. Checked,
" and the wrong order is visible in 'showcmd' itself.
"
" It costs the demo nothing: hexpair.vimrc hangs its mappings off whatever
" <Leader> is, and what the recording is showing is that there ARE mappings.
let mapleader = ','

" --- making a key press visible ------------------------------------------
"
" Three settings and a pile of decoys, and all of it is about one problem: a
" mapping that Vim can complete is executed the instant its last key arrives,
" so the key never appears anywhere. 'showcmd' shows a mapping Vim is still
" WAITING on, and nothing else.
"
" 'showcmdloc' puts that where it can be seen. Its default is the bottom right
" of the last line, ten columns wide, next to the ruler - which in a recording
" is the one place nobody is looking. In the statusline it can go where the eye
" already is, beside the file name, in a colour of its own.
set showcmd
set showcmdloc=statusline

" How long Vim waits for the rest of a mapping before giving up. Long enough to
" read the keys off the statusline, short enough that the recording does not
" stall on every one of them.
set timeoutlen=1500

" The decoys. `,i` is a complete mapping and nothing begins with it, so Vim runs
" it the moment the `i` lands and the statusline never shows more than the `,`.
" Mapping `,ix` as well makes `,i` ambiguous: Vim has to wait out 'timeoutlen'
" to find out which was meant, and for that second and a half the whole
" mapping is on the screen to be read. Then the timeout expires and `,i` runs
" after all.
"
" They do nothing, they exist only for the recording, and they are the reason
" this file is not something to copy into a real vimrc.
for s:key in ['h', '>', '<', 'i', 'I', 'e', ']', '[', '=', '?', 'j', 'k', '/']
  execute 'nnoremap <silent> <Leader>' . s:key . 'x <Nop>'
endfor
unlet! s:key

" The statusline, through a wrapper: 'statusline' is evaluated on every redraw,
" and a call to a function that does not exist raises E117 - which Vim answers
" by clearing the option altogether, taking the whole line with it.
function! StatuslineHexPair() abort
  return exists('*HexPairStatus') ? HexPairStatus() : ''
endfunction
" %S is where 'showcmdloc=statusline' puts the half-typed mapping. It sits
" second, right after the file name, because that is where somebody watching is
" already looking - and in a highlight of its own so that a key press is not
" one more grey thing on a grey line.
highlight DemoKey ctermfg=16 ctermbg=226 cterm=bold guifg=#101010 guibg=#ffd700 gui=bold
set laststatus=2
set ruler
set statusline=\ %f\ %m%r\ \ %#DemoKey#%S%*\ %{StatuslineHexPair()}%=%-14.(%l,%c%V%)\ %P\ 

" --- the narration --------------------------------------------------------
"
" A caption line above everything, so that a viewer knows what is about to
" happen rather than working it out afterwards. The tabline, because it is the
" one full-width line that is not the message area, not the statusline and not
" the buffer - nothing the demo does can paint over it.
"
" `:Say` with no argument clears it. The tape types it at a reading pace and
" leaves it standing for three seconds afterwards - a caption is the one thing
" on the screen that has to be READ rather than watched, and it is what most of
" the recording's running time goes on.
let g:demo_caption = ''
function! DemoCaption() abort
  return empty(g:demo_caption) ? '' : '  ' . g:demo_caption
endfunction
" redraw! and not redraw: setting a variable does not make Vim think the
" tabline changed, so a plain redraw repaints everything except the one line
" this command exists to change. The forcing one costs the message area, which
" is empty here anyway - a caption is written before a beat, not after one.
command! -nargs=* Say let g:demo_caption = <q-args> | redraw!
highlight DemoCaption ctermfg=51 ctermbg=17 cterm=bold guifg=#7fdfff guibg=#00005f gui=bold
set showtabline=2
set tabline=%#DemoCaption#%{DemoCaption()}%=

" The mappings the plugin ships - the ones the recording presses. The plugin
" itself defines none, which is why they have to come from somewhere.
runtime hexpair.vimrc

" vim:set fileencoding=utf-8 filetype=vim:
