@echo off
REM ===========================================================================
REM gvimhexdiff.cmd - vimhexdiff.cmd, but opens gVim instead of console Vim
REM
REM Maintainer:  Michal Ruzicka <ruzicka.mich@gmail.com>
REM URL:         https://github.com/michal-ruzicka/hexpair
REM License:     Vim License - same terms as Vim itself (see LICENSE.md
REM              or :help license); SPDX-License-Identifier: Vim
REM
REM The same command, the same arguments, as vimhexdiff.cmd - see that file
REM for the full usage, including the /pick and /with two-click form a
REM context-menu verb needs. The only difference is the default: VIMHEX_VIM
REM defaults to "gvim" here instead of the console "vim", which is what you
REM want double-clicked from Explorer or run from a context-menu verb, where
REM there is no console window to run "vim" in in the first place. A
REM VIMHEX_VIM already set in the environment - a full gvim.exe path, say -
REM is left alone.
REM
REM     gvimhexdiff old.img new.img
REM     gvimhexdiff /pick old.img
REM     gvimhexdiff /with new.img
REM
REM Delegates to vimhexdiff.cmd, in this SAME directory, rather than
REM duplicating its argument parsing and its pick/with state handling - that
REM keeps ONE source of truth for both. Keep the two files together: copy
REM both, or neither, wherever this goes.
REM See README.md, "Windows: vimhex and vimhexdiff outside Vim".
REM ===========================================================================

setlocal
if not defined VIMHEX_VIM set "VIMHEX_VIM=gvim"
call "%~dp0vimhexdiff.cmd" %*
