@echo off
REM ===========================================================================
REM Windows wrapper for the hexpair release packaging.
REM
REM All packaging logic lives in pack-release.py: every platform
REM produces the tarball with the same implementation, so the output is
REM byte-identical by construction (see CONTRIBUTING.md, "Reproducible
REM Builds"). pack-release is the POSIX counterpart.
REM
REM A Python 3 interpreter is located by actually running the
REM candidates: the Microsoft Store "python.exe" alias stub fails with
REM exit code 9009, so testing for mere presence on PATH is not enough.
REM ===========================================================================
setlocal

cd /d "%~dp0"

set PY=
py -3 -c "import sys" >nul 2>nul
if not errorlevel 1 set PY=py -3
if not defined PY (
    python -c "import sys" >nul 2>nul
    if not errorlevel 1 set PY=python
)
if not defined PY (
    echo pack-release: no Python 3 interpreter found 1>&2
    echo install one ^(e.g. "winget install Python.Python.3.13"^) or run ./pack-release in WSL 1>&2
    exit /b 1
)

%PY% pack-release.py
exit /b
