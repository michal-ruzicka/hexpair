@echo off
REM ===========================================================================
REM vimhex.cmd - open a file, or piped input, straight in hexpair's hex view
REM
REM Maintainer:  Michal Ruzicka <ruzicka.mich@gmail.com>
REM URL:         https://github.com/michal-ruzicka/hexpair
REM License:     Vim License - same terms as Vim itself (see LICENSE.md
REM              or :help license); SPDX-License-Identifier: Vim
REM
REM The Windows counterpart of the `vimhex` function in hexpair.bashrc, and
REM deliberately the same command taking the same arguments - a hex view is
REM opened the same way whichever shell you happen to be standing in:
REM
REM     vimhex FILE          the first page
REM     vimhex FILE PAGE     that page, 1-based; also $ for the last one
REM                          and +N / -N to step from the first
REM     vimhex FILE @BYTE    the page holding that byte, cursor on it;
REM                          decimal or 0x-prefixed, and 1-based, so a
REM                          position :HexPairPages reported can be typed
REM                          straight back in
REM     vimhex - [...]       read from standard input instead of a file
REM
REM     vimhex disk.img
REM     vimhex disk.img 37
REM     vimhex disk.img $
REM     vimhex disk.img @0x4a2000
REM     type disk.img | vimhex -
REM
REM Only the page on screen is read, so the size of the file does not matter.
REM
REM Set VIMHEX_VIM to use a particular Vim - "gvim" for the GUI, or a full
REM path such as "C:\Program Files\Vim\vim91\gvim.exe". The default is the
REM console `vim`, which is what running this from a cmd window asks for.
REM
REM Put this file's directory on PATH. The plugin's own directory is the
REM obvious one, since an update of the plugin then updates the command too.
REM See README.md, "Windows: vimhex and vimhexdiff outside Vim".
REM ===========================================================================

setlocal

if "%~1"=="" goto usage
if not "%~3"=="" goto usage

REM The path and the position go through the ENVIRONMENT rather than into the
REM Ex command line, for the reason hexpair.bashrc gives: a name holding a
REM space, a quote or a literal '$' does not survive :execute's own argument
REM parsing, while $NAME inside a Vim expression needs no escaping at all.
REM `set "VAR=%~1"` is also the form that survives an & or a ^ in the name.
REM Delayed expansion stays OFF here - it would eat a ! in one.
set "HEXPAIR_OPEN_FILE=%~1"
set "HEXPAIR_OPEN_WHERE=%~2"
if not defined HEXPAIR_OPEN_WHERE set "HEXPAIR_OPEN_WHERE=1"
if not defined VIMHEX_VIM set "VIMHEX_VIM=vim"

REM A byte rather than a page number. hexpair works out which page holds it -
REM pages are plain fixed-size slices, so that is a division, and it follows
REM g:hexpair_page_size even if the vimrc changes it.
if "%HEXPAIR_OPEN_WHERE:~0,1%"=="@" goto byte

REM A page number, $ for the last page, or +N / -N: :HexPairPageGoto parses
REM all three. Single quotes inside the Ex command on purpose: the whole -c
REM argument is already inside the double quotes cmd needs.
set "HEXPAIR_JUMP=execute 'HexPairPageGoto' $HEXPAIR_OPEN_WHERE"
goto run

:byte
set "HEXPAIR_OPEN_WHERE=%HEXPAIR_OPEN_WHERE:~1%"
set "HEXPAIR_JUMP=execute 'HexPairGoOffset' $HEXPAIR_OPEN_WHERE"

REM Both steps run from VimEnter, the only point that is after the content has
REM arrived in BOTH cases below: a plain -c runs after a named file has been
REM read, but BEFORE standard input has.
:run
if "%~1"=="-" goto stdin
"%VIMHEX_VIM%" -c "autocmd VimEnter * call HexPairOpenFile($HEXPAIR_OPEN_FILE)" -c "autocmd VimEnter * %HEXPAIR_JUMP%"
goto :eof

REM Reading from standard input: there is no file for :HexPairOpen to page, so
REM Vim reads it all and hexpair pages the buffer it produced. The -b matters -
REM without it Vim may transcode the input on the way in, and unlike a named
REM file there is nothing to re-read with ++bin afterwards. Save it with
REM ':w FILE'; a plain ':w' has no file to write back to.
:stdin
"%VIMHEX_VIM%" -b -c "autocmd VimEnter * HexPairToggle" -c "autocmd VimEnter * %HEXPAIR_JUMP%" -
goto :eof

:usage
>&2 echo usage: vimhex FILE^|- [PAGE^|@BYTE]
exit /b 1
