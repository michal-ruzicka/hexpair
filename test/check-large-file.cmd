@echo off
REM ===========================================================================
REM check-large-file.cmd - Windows DRIVER for the large-file checks
REM
REM Maintainer:  Michal Ruzicka <ruzicka.mich@gmail.com>
REM URL:         https://github.com/michal-ruzicka/hexpair
REM License:     Vim License - same terms as Vim itself (see LICENSE.md
REM              or :help license); SPDX-License-Identifier: Vim
REM
REM     test\check-large-file.cmd [SIZE_IN_GIB]      (default 3, minimum 3)
REM
REM Needs SIZE_IN_GIB of free disk for the fixture, and the same again while
REM the ':w {file}' check runs - six free gigabytes at the default.
REM
REM Set HEXPAIR_LARGE_FILE to a fixture a previous run left behind and it
REM is used as it stands, not rebuilt and not deleted - which saves three
REM gigabytes of writing per attempt, and removes the one difference no
REM probe has been able to reproduce: that in a real run the file was
REM written seconds earlier and the system is still flushing it.
REM
REM Set HEXPAIR_NO_TRACE to anything and the per-statement markers are
REM left out of the edit scripts. Adding them is the only difference
REM between a run that hung on the first edit and one that passed every
REM check, so this switch is how that is measured rather than assumed.
REM
REM Set HEXPAIR_DEBUG to anything and every edit script turns on
REM g:hexpair_debug, whose trace goes to this console - so a run that
REM stops shows its last step rather than only that it stopped.
REM
REM Set HEXPAIR_VIM (and HEXPAIR_XXD) to name the Vim under test. The point
REM of running it here is that this is a NATIVE Windows Vim with no Git Bash
REM anywhere in the picture.
REM
REM THIS FILE RUNS VIM. check-large-file.ps1 never does, and that division
REM is the whole design rather than a detail. Every arrangement in which
REM PowerShell started Vim - Start-Process with redirected handles,
REM `& cmd /c` with the path as an argument, `start /wait`, with and without
REM capturing stdout - hung on a read of eight bytes from a 256-byte file,
REM while plain `vim -es -u NONE -S file <nul` from a batch never did.
REM Five explanations for that were argued and all five were wrong, and
REM the hang later stopped happening on its own. What survives is the
REM shape that never failed, which costs nothing to keep.
REM
REM The .ps1 is still where the arithmetic lives - the offsets are around
REM 2.7 billion and cmd's `set /a` is 32-bit - so it computes, builds the
REM fixture and checks the bytes, in PHASES. Between two phases it leaves
REM an edit.vim behind and this file runs Vim on it. The checks have to
REM interleave with the edits, because "the file grew by two bytes" cannot
REM be asked after the shrink has undone it.
REM ===========================================================================
setlocal

cd /d "%~dp0"

if "%HEXPAIR_VIM%"=="" set HEXPAIR_VIM=vim
set SIZE=%1
if "%SIZE%"=="" set SIZE=3
set HANDOFF=%TEMP%\hexpair-check-large.cmd
set PS=powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File check-large-file.ps1

echo check-large-file: vim under test: %HEXPAIR_VIM%

%PS% -Phase setup -SizeGiB %SIZE%
if errorlevel 1 goto :failed
if not exist "%HANDOFF%" (
    echo check-large-file: setup wrote no handoff file
    goto :failed
)
call "%HANDOFF%"
del "%HANDOFF%" 2>nul

REM The preflight read, then the fixture and the first edit, then the
REM three that follow. Each :vim is the proven shape and nothing else.
call :vim
%PS% -Phase fixture -Work "%WORK%"
if errorlevel 1 goto :failed
call :vim
%PS% -Phase check1 -Work "%WORK%"
if errorlevel 1 goto :failed
call :vim
%PS% -Phase check2 -Work "%WORK%"
if errorlevel 1 goto :failed
call :vim
%PS% -Phase check3 -Work "%WORK%"
if errorlevel 1 goto :failed
call :vim
%PS% -Phase check4 -Work "%WORK%"
if errorlevel 1 goto :failed
exit /b 0

:failed
echo.
echo check-large-file: stopping here.
if defined WORK echo   the work directory is left behind for inspection: %WORK%
exit /b 1

:vim
REM Batch runs Vim. Directly, with cmd's own <nul, no redirection of its
REM output, and no path crossing any interpreter boundary but this one.
"%HEXPAIR_VIM%" -es -u NONE -S "%WORK%\edit.vim" <nul
goto :eof
