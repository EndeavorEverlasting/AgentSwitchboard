@echo off
setlocal
set "ROOT=%~dp0"
where py >nul 2>nul
if %ERRORLEVEL% EQU 0 (
  py -3 "%ROOT%tooling\context\Contextualize-AppOutput.py" %*
  exit /b %ERRORLEVEL%
)
where python >nul 2>nul
if %ERRORLEVEL% EQU 0 (
  python "%ROOT%tooling\context\Contextualize-AppOutput.py" %*
  exit /b %ERRORLEVEL%
)
echo ERROR: Python 3 is required. 1>&2
exit /b 2
