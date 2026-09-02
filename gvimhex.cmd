@echo off
REM ===========================================================================
REM gvimhex.cmd - vimhex.cmd, but opens gVim instead of console Vim
REM
REM Maintainer:  Michal Ruzicka <ruzicka.mich@gmail.com>
REM URL:         https://github.com/michal-ruzicka/hexpair
REM License:     Vim License - same terms as Vim itself (see LICENSE.md
REM              or :help license); SPDX-License-Identifier: Vim
REM
REM The same command, the same arguments, as vimhex.cmd - see that file for
REM the full usage. The only difference is the default: VIMHEX_VIM defaults
REM to "gvim" here instead of the console "vim", which is what you want
REM double-clicked from Explorer or run from a context-menu verb, where
REM there is no console window to run "vim" in in the first place. A
REM VIMHEX_VIM already set in the environment - a full gvim.exe path, say -
REM is left alone.
REM
REM     gvimhex disk.img
REM     gvimhex disk.img 37
REM     gvimhex disk.img $
REM     gvimhex disk.img @0x4a2000
REM     type disk.img | gvimhex -
REM
REM Delegates to vimhex.cmd, in this SAME directory, rather than duplicating
REM its argument parsing - the argument grammar keeps ONE source of truth.
REM Keep the two files together: copy both, or neither, wherever this goes.
REM See README.md, "Windows: vimhex and vimhexdiff outside Vim".
REM ===========================================================================

setlocal
if not defined VIMHEX_VIM set "VIMHEX_VIM=gvim"
call "%~dp0vimhex.cmd" %*
