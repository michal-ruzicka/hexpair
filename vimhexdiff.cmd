@echo off
REM ===========================================================================
REM vimhexdiff.cmd - two files side by side, each marking what differs
REM
REM Maintainer:  Michal Ruzicka <ruzicka.mich@gmail.com>
REM URL:         https://github.com/michal-ruzicka/hexpair
REM License:     Vim License - same terms as Vim itself (see LICENSE.md
REM              or :help license); SPDX-License-Identifier: Vim
REM
REM The Windows counterpart of the `vimhexdiff` function in hexpair.bashrc:
REM
REM     vimhexdiff FILE1 FILE2   the two files side by side, each marking the
REM                              bytes that differ from the other, cursors on
REM                              the first difference
REM
REM The two windows are scroll-bound and both cursors land on the first
REM difference. Afterwards they keep showing the same bytes: scrolling keeps
REM them level, and a JUMP in either one - a diff jump, a search landing,
REM :HexPairGoOffset, or a page turn made directly - takes the other to the
REM same byte. Moving the cursor by hand does not, since that is about this
REM window and not about the file; :HexPairSyncViews is the way back from it.
REM
REM Only the page on screen is read, so the size of the files does not matter.
REM
REM Two files, one at a time
REM ------------------------
REM Explorer runs a context-menu command once per selected file, each with
REM its own path, so a verb cannot be handed two of them at once without a
REM COM handler. The same two steps every diff tool solves this with:
REM
REM     vimhexdiff /pick FILE    remember FILE as the left-hand side
REM     vimhexdiff /with FILE    diff it against the remembered one
REM
REM /with forgets the remembered file afterwards, so the next /with needs a
REM new /pick rather than silently reusing a stale one. The name is kept in
REM %LOCALAPPDATA%\hexpair\diff-left.txt - a path and nothing else.
REM
REM Set VIMHEX_VIM to use a particular Vim - "gvim" for the GUI, or a full
REM path such as "C:\Program Files\Vim\vim91\gvim.exe". The default is the
REM console `vim`, which is what running this from a cmd window asks for.
REM
REM Put this file's directory on PATH; see README.md, "Windows: vimhex and
REM vimhexdiff outside Vim", which also has the context-menu entries.
REM ===========================================================================

setlocal

if defined LOCALAPPDATA (set "HEXPAIR_STATE_DIR=%LOCALAPPDATA%\hexpair") else (set "HEXPAIR_STATE_DIR=%TEMP%\hexpair")
set "HEXPAIR_STATE=%HEXPAIR_STATE_DIR%\diff-left.txt"

if /i "%~1"=="/pick" goto pick
if /i "%~1"=="/with" goto with
if "%~1"=="" goto usage
if "%~2"=="" goto usage
if not "%~3"=="" goto usage

REM Both names go through the ENVIRONMENT rather than into the Ex command
REM line, for the reason hexpair.bashrc gives: a name holding a space, a
REM quote or a literal '$' does not survive :execute's own argument parsing,
REM while $NAME inside a Vim expression needs no escaping at all.
set "HEXPAIR_DIFF_A=%~1"
set "HEXPAIR_DIFF_B=%~2"
goto run

REM Remember the left-hand side. Written QUOTED, so that a name holding an &
REM comes back out of the file intact; /with takes the quotes off again.
:pick
if "%~2"=="" goto usage
if not "%~3"=="" goto usage
if not exist "%HEXPAIR_STATE_DIR%" mkdir "%HEXPAIR_STATE_DIR%"
> "%HEXPAIR_STATE%" echo "%~f2"
echo vimhexdiff: left side remembered: "%~f2"
echo vimhexdiff: now pick the other file with  vimhexdiff /with FILE
goto :eof

:with
if "%~2"=="" goto usage
if not "%~3"=="" goto usage
if not exist "%HEXPAIR_STATE%" goto nopick
set "HEXPAIR_DIFF_A="
set /p HEXPAIR_DIFF_A=<"%HEXPAIR_STATE%"
if not defined HEXPAIR_DIFF_A goto nopick
set "HEXPAIR_DIFF_A=%HEXPAIR_DIFF_A:~1,-1%"
set "HEXPAIR_DIFF_B=%~f2"
REM Forgotten as soon as it is used: a remembered path left lying about is
REM one a later /with would silently diff against, long after the file it
REM names has moved or gone.
del "%HEXPAIR_STATE%"
if not exist "%HEXPAIR_DIFF_A%" goto gone
goto run

REM Everything runs from VimEnter - a plain -c would run before hexpair has
REM anything to work on - and in order: open the left file, tell it what it
REM is compared against, split and open the right one in the new window, tell
REM it the same the other way round, bind the two windows' scrolling, and
REM land on the first difference. That last step is :HexPairSyncViews, and it
REM is not decoration: 'scrollbind' syncs movement made from the moment a
REM window was bound, and all of this happens inside VimEnter - before the
REM loop that would have done the syncing has run even once.
REM
REM Four -c options rather than nine: Vim takes at most ten, and an
REM :autocmd swallows the bars after it, so each step is one autocommand made
REM of several commands. The split is "rightbelow" so that the left-hand file
REM stays on the left whatever 'splitright' says.
REM
REM The first one is about the WINDOW rather than the files. Two views side
REM by side want the full width, and a narrow window is also what made Vim
REM stop for a hit-enter prompt on every file it opened: a long path plus
REM the size makes the file message longer than one line, which is exactly
REM what triggers the prompt. 'shortmess+=F' drops that message outright and
REM "simalt ~x" is the Win32 GUI's own maximize. Both are guarded rather
REM than assumed: :simalt exists only in the GUI build, and it has to run
REM once the GUI is actually up, hence VimEnter rather than a plain -c.
:run
if not defined VIMHEX_VIM set "VIMHEX_VIM=vim"
"%VIMHEX_VIM%" -c "autocmd VimEnter * set shortmess+=F | if has('gui_running') | simalt ~x | endif" -c "autocmd VimEnter * call HexPairOpenFile($HEXPAIR_DIFF_A) | call HexPairDiffWith($HEXPAIR_DIFF_B)" -c "autocmd VimEnter * rightbelow vsplit | call HexPairOpenFile($HEXPAIR_DIFF_B) | call HexPairDiffWith($HEXPAIR_DIFF_A) | setlocal scrollbind" -c "autocmd VimEnter * wincmd t | setlocal scrollbind | HexPairDiffNext | HexPairSyncViews"
if errorlevel 1 goto launchfailed
goto :eof

REM See vimhex.cmd for why this pauses only on failure: run from the
REM Explorer context menu, "cmd.exe /c" closes its console the instant the
REM batch finishes - too fast to read the one-line "not recognized" cmd.exe
REM prints when VIMHEX_VIM is not on PATH - while a normal launch returns (0)
REM long before this line would ever run.
:launchfailed
>&2 echo vimhexdiff: could not start "%VIMHEX_VIM%" - is it on PATH?
>&2 echo vimhexdiff: set VIMHEX_VIM to its full path instead, e.g. "C:\Program Files\Vim\vim91\gvim.exe"
call :holdopen
exit /b 1

:nopick
>&2 echo vimhexdiff: there is no left-hand file to compare against yet.
>&2 echo.
>&2 echo Pick one first: right-click the LEFT file and choose
>&2 echo     vimhex  ^>  gvimhexdiff left
>&2 echo then right-click the other one and choose
>&2 echo     vimhex  ^>  gvimhexdiff right
>&2 echo.
>&2 echo From a command prompt the same two steps are
>&2 echo     vimhexdiff /pick FILE
>&2 echo     vimhexdiff /with FILE
call :holdopen
exit /b 1

:gone
>&2 echo vimhexdiff: the file picked as the left-hand side is no longer there:
>&2 echo     "%HEXPAIR_DIFF_A%"
>&2 echo.
>&2 echo It was moved, renamed or deleted since it was picked. Pick it again.
call :holdopen
exit /b 1

REM Stop so the message above can be read - but ONLY when there is somebody
REM to read it. Launched through vimhex-launch.vbs the console is hidden, so
REM a pause would wait forever where it cannot be seen or dismissed; the
REM launcher sets HEXPAIR_NO_PAUSE and puts this output in a message box
REM instead. Run from a real console, nothing sets it and the pause happens.
:holdopen
if not defined HEXPAIR_NO_PAUSE pause
goto :eof

:usage
>&2 echo usage: vimhexdiff FILE1 FILE2
>&2 echo        vimhexdiff /pick FILE   remember FILE as the left-hand side
>&2 echo        vimhexdiff /with FILE   diff it against the remembered one
exit /b 1
