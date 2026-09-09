@echo off
REM ===========================================================================
REM vimhex-vim.cmd - open a file in a PLAIN console Vim: no hex view, no
REM                  paging, no plugin
REM
REM Maintainer:  Michal Ruzicka <ruzicka.mich@gmail.com>
REM URL:         https://github.com/michal-ruzicka/hexpair
REM License:     Vim License - same terms as Vim itself (see LICENSE.md
REM              or :help license); SPDX-License-Identifier: Vim
REM
REM Not a hexpair command, and that is the point. The Explorer context menu
REM vimhex-contex-entry.add.reg installs offers "vim this" and "gvim this"
REM beside its hex entries, because Vim's own installer contributes exactly
REM one entry - "Edit with gVim" - and none for the console, so a stock
REM Windows has no way to right-click a file into console Vim. These two
REM commands are what those two entries run.
REM
REM     vimhex-vim FILE
REM
REM WHY THE NAME. This sits on PATH beside vimhex.cmd, and a file called
REM vim.cmd there would shadow the real vim.exe for everything else that
REM looks Vim up on PATH - hexpair's own commands included, since that is
REM exactly how they find it. The prefix keeps this out of that namespace.
REM
REM WHY A WRAPPER rather than `vim` straight from the registry: a verb that
REM cannot start its program leaves the user with a console that closes
REM before cmd.exe's own "not recognized" line can be read. This says what
REM is wrong and what to do about it, then pauses so it can be read - the
REM same treatment vimhex.cmd gives a Vim it cannot start.
REM
REM Runs whatever `vim` is on PATH. VIMHEX_VIM is deliberately NOT
REM consulted: that names the Vim HEXPAIR's commands open, and set to
REM "gvim" - which is a perfectly ordinary thing to set it to - it would
REM make "vim this" open the GUI. Set VIMHEX_PLAIN_VIM for a Vim that is
REM not on PATH, e.g. "C:\Program Files\Vim\vim91\vim.exe"; vimhex-gvim.cmd
REM defaults the same variable to `gvim` instead, so one already set in the
REM environment points both of them at it, the way VIMHEX_VIM does for
REM vimhex.cmd and gvimhex.cmd.
REM
REM Put this file's directory on PATH - the plugin's own is the obvious
REM one. See README.md, "vimhex and vimhexdiff on Windows".
REM ===========================================================================

setlocal

if "%~1"=="" goto usage
if not "%~2"=="" goto usage

if not defined VIMHEX_PLAIN_VIM set "VIMHEX_PLAIN_VIM=vim"

REM On the command line rather than through the environment, unlike
REM vimhex.cmd: there is no Ex command here for a file name to be parsed
REM out of, so cmd.exe's own quoting is the whole of what has to be right.
REM "--" ends the options, so a file whose name begins with "-" is a file.
"%VIMHEX_PLAIN_VIM%" -- "%~1"
if errorlevel 1 goto launchfailed
goto :eof

REM Reached when Vim could not be started - the case this wrapper exists
REM for - and also when a Vim that ran fine exited nonzero of its own
REM accord, which is what ":cq" is. That is why the message asks rather
REM than asserts; the same trade vimhex.cmd makes, for the same reason,
REM and telling the two apart from a batch file is not worth the guessing
REM (cmd.exe reports a name it could not find and a path that is not there
REM with different codes on different Windows versions).
:launchfailed
>&2 echo vimhex-vim: could not start "%VIMHEX_PLAIN_VIM%" - is it on PATH?
>&2 echo vimhex-vim: set VIMHEX_PLAIN_VIM to its full path instead, e.g. "C:\Program Files\Vim\vim91\vim.exe"
REM Stop so the message can be read - but only when there is somebody to
REM read it. HEXPAIR_NO_PAUSE skips the pause, for a caller that has its
REM own way of showing the message.
if not defined HEXPAIR_NO_PAUSE pause
exit /b 1

:usage
>&2 echo usage: vimhex-vim FILE
>&2 echo        opens FILE in a plain console Vim - no hex view, no paging
exit /b 1
