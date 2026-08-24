" hexpair - filetype plugin with editing defaults for xxd hex dumps
" Maintainer:  Michal Růžička <ruzicka.mich@gmail.com>
" URL:         https://github.com/michal-ruzicka/hexpair
" License:     Vim License - same terms as Vim itself (see LICENSE.md
"              or :help license); SPDX-License-Identifier: Vim
"
" Applied to every buffer with filetype=xxd - hexpair sets that
" filetype whenever the hex view is active, so these defaults cover
" every hexpair buffer as well as hand-made xxd dumps.
"
" Overruling (:help ftplugin-overrule): a personal
" ~/.vim/ftplugin/xxd.vim runs BEFORE this file, so its settings alone
" would be overwritten here.  Either set b:did_ftplugin = 1 there to
" skip this file entirely, or put overrides into
" ~/.vim/after/ftplugin/xxd.vim, which runs after it and always wins.
"
" Note: the global 'paste' option is intentionally NOT touched here -
" it is managed by the main plugin (g:hexpair_paste), which can
" restore it when the cursor leaves the hex buffer.

" The maintainer's name above is not ASCII; see plugin/hexpair.vim.
scriptencoding utf-8

if exists('b:did_ftplugin')
  finish
endif
let b:did_ftplugin = 1

" A <Tab> aligns to the width of the offset column prefix ('00000000: ').
setlocal tabstop=10

" Indent with spaces - literal tabs do not belong in a dump.
setlocal expandtab

" One shift indents by one hex byte (two digits plus the separating space).
setlocal shiftwidth=3

" No automatic formatting, wrapping or indenting - dump lines are edited
" exactly as typed.
setlocal formatoptions= textwidth=0 noautoindent

" Revert everything when the filetype changes, e.g. when hexpair toggles
" the hex view off.  Kept on one line: this file may be sourced with a
" user 'cpoptions' that disables line continuations.
let b:undo_ftplugin = 'setlocal tabstop< expandtab< shiftwidth< formatoptions< textwidth< autoindent<'
