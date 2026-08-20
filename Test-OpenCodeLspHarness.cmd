@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ROOT=%~dp0"
set "PY_KIND="
set "R="
where python.exe >nul 2>nul
if not errorlevel 1 (
  python.exe -c "import sys; raise SystemExit(0 if sys.version_info.major == 3 else 1)" >nul 2>nul
  if not errorlevel 1 set "PY_KIND=python"
)
if not defined PY_KIND (
  where py.exe >nul 2>nul
  if not errorlevel 1 (
    py.exe -3 -c "import sys; raise SystemExit(0 if sys.version_info.major == 3 else 1)" >nul 2>nul
    if not errorlevel 1 set "PY_KIND=py"
  )
)
if not defined PY_KIND (echo [FAIL] usable Python 3 is required.& endlocal & exit /b 127)
pushd "%ROOT%" || (echo [FAIL] cannot enter repository root.& endlocal & exit /b 2)
if "%PY_KIND%"=="python" goto :run_python
goto :run_py

:run_python
python.exe -m unittest tests.test_opencode_lsp_harness -v
if errorlevel 1 set "R=%ERRORLEVEL%"
if defined R goto :fail
goto :powershell_checks

:run_py
py.exe -3 -m unittest tests.test_opencode_lsp_harness -v
if errorlevel 1 set "R=%ERRORLEVEL%"
if defined R goto :fail

:powershell_checks
pwsh -NoLogo -NoProfile -File "%ROOT%scripts\Test-OpenCodeLspHarness.ps1" -RootPath "%ROOT%."
if errorlevel 1 set "R=%ERRORLEVEL%"
if defined R goto :fail
pwsh -NoLogo -NoProfile -File "%ROOT%scripts\Test-AgentDocumentationContract.ps1" -RootPath "%ROOT%."
if errorlevel 1 set "R=%ERRORLEVEL%"
if defined R goto :fail

git diff --check
if errorlevel 1 set "R=%ERRORLEVEL%"
if defined R goto :fail
popd
endlocal
exit /b 0

:fail
popd
endlocal & exit /b %R%
