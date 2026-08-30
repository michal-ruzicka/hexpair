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
REM COM handler. Each side is therefore selected on its own:
REM
REM     vimhexdiff /left FILE    select FILE as the left-hand side
REM     vimhexdiff /right FILE   select FILE as the right-hand side
REM
REM THE ORDER DOES NOT MATTER. Each one records its side and stops there;
REM whichever of the two completes the pair opens the comparison and forgets
REM both selections again, so the next diff starts from a clean slate. That
REM symmetry is the point: there is no "you have to pick the left one first"
REM rule to get wrong, and therefore no error to report for breaking it.
REM
REM Selecting the same side twice just overwrites it - changing your mind
REM about one half of a comparison is not a failure, and says nothing about
REM whether the other half is selected.
REM
REM The two names are kept in %LOCALAPPDATA%\hexpair\diff-left.txt and
REM diff-right.txt - a path each and nothing else.
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

if /i "%~1"=="/left" goto side
if /i "%~1"=="/right" goto side
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

REM One side of a comparison. Symmetric: this records the side it was given
REM and, if that completes the pair, runs the diff. Which side arrived first
REM is never asked.
:side
if "%~2"=="" goto usage
if not "%~3"=="" goto usage

REM Plain "if" lines rather than a parenthesised if/else: a set inside
REM parentheses is expanded when the whole block is PARSED, so a name
REM holding a ) or a & would be read as syntax rather than as text.
set "HEXPAIR_THIS=right"
set "HEXPAIR_OTHER=left"
if /i "%~1"=="/left" set "HEXPAIR_THIS=left"
if /i "%~1"=="/left" set "HEXPAIR_OTHER=right"

REM Written QUOTED, so that a name holding an & comes back out of the file
REM intact; the read below takes the quotes off again. Overwrites whatever
REM this side held before - changing your mind is not an error.
if not exist "%HEXPAIR_STATE_DIR%" mkdir "%HEXPAIR_STATE_DIR%"
> "%HEXPAIR_STATE_DIR%\diff-%HEXPAIR_THIS%.txt" echo "%~f2"

REM Nothing on the other side yet: this selection is all there is to do.
REM Silence is deliberate - selecting a side is half of one gesture, and the
REM comparison opening IS the acknowledgement that both halves arrived.
set "HEXPAIR_OTHER_STATE=%HEXPAIR_STATE_DIR%\diff-%HEXPAIR_OTHER%.txt"
if not exist "%HEXPAIR_OTHER_STATE%" goto :eof
set "HEXPAIR_OTHER_FILE="
set /p HEXPAIR_OTHER_FILE=<"%HEXPAIR_OTHER_STATE%"
if not defined HEXPAIR_OTHER_FILE goto :eof
set "HEXPAIR_OTHER_FILE=%HEXPAIR_OTHER_FILE:~1,-1%"

REM Both sides are in. Forget them before doing anything that can fail: a
REM selection left lying about is one a later pick would silently compare
REM against, long after the file it names has moved or gone.
del "%HEXPAIR_STATE_DIR%\diff-left.txt" 2>nul
del "%HEXPAIR_STATE_DIR%\diff-right.txt" 2>nul

if "%HEXPAIR_THIS%"=="left" set "HEXPAIR_DIFF_A=%~f2"
if "%HEXPAIR_THIS%"=="left" set "HEXPAIR_DIFF_B=%HEXPAIR_OTHER_FILE%"
if "%HEXPAIR_THIS%"=="right" set "HEXPAIR_DIFF_A=%HEXPAIR_OTHER_FILE%"
if "%HEXPAIR_THIS%"=="right" set "HEXPAIR_DIFF_B=%~f2"

if not exist "%HEXPAIR_OTHER_FILE%" goto gone
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

REM The other side named a file that is not there any more. Both selections
REM have already been cleared above, so saying "select it again" is honest:
REM there is nothing stale left to trip over on the next attempt.
:gone
>&2 echo vimhexdiff: the file selected as the %HEXPAIR_OTHER% side is no longer there:
>&2 echo     "%HEXPAIR_OTHER_FILE%"
>&2 echo.
>&2 echo It was moved, renamed or deleted since it was selected.
>&2 echo Both selections have been cleared - select the two files again.
call :holdopen
exit /b 1

REM Stop so the message above can be read: run from a context-menu verb,
REM "cmd.exe /c" closes its console the instant the batch ends, which is far
REM too fast. HEXPAIR_NO_PAUSE skips the pause, for a caller that shows the
REM message its own way - nothing sets it by default.
:holdopen
if not defined HEXPAIR_NO_PAUSE pause
goto :eof

:usage
>&2 echo usage: vimhexdiff FILE1 FILE2
>&2 echo        vimhexdiff /left FILE    select FILE as the left-hand side
>&2 echo        vimhexdiff /right FILE   select FILE as the right-hand side
>&2 echo.
>&2 echo /left and /right may be given in either order. Whichever completes
>&2 echo the pair opens the comparison and clears both selections.
call :holdopen
exit /b 1
