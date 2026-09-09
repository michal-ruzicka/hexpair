@echo off
REM ===========================================================================
REM vimhex-gvim.cmd - vimhex-vim.cmd, but opens gVim instead of console Vim
REM
REM Maintainer:  Michal Ruzicka <ruzicka.mich@gmail.com>
REM URL:         https://github.com/michal-ruzicka/hexpair
REM License:     Vim License - same terms as Vim itself (see LICENSE.md
REM              or :help license); SPDX-License-Identifier: Vim
REM
REM The same command, the same argument, as vimhex-vim.cmd - see that file
REM for the whole story, including why neither of them is called vim.cmd or
REM gvim.cmd. The only difference is the default: VIMHEX_PLAIN_VIM defaults
REM to "gvim" here instead of the console "vim". One already set in the
REM environment is left alone, so it points both commands at the Vim it
REM names - the same way VIMHEX_VIM behaves for vimhex.cmd and gvimhex.cmd.
REM
REM     vimhex-gvim FILE
REM
REM Delegates to vimhex-vim.cmd, in this SAME directory, rather than
REM duplicating its argument checking and the message it gives for a Vim it
REM could not start - one source of truth for both. Keep the two files
REM together: copy both, or neither, wherever this goes.
REM See README.md, "vimhex and vimhexdiff on Windows".
REM ===========================================================================

setlocal
if not defined VIMHEX_PLAIN_VIM set "VIMHEX_PLAIN_VIM=gvim"
call "%~dp0vimhex-vim.cmd" %*
