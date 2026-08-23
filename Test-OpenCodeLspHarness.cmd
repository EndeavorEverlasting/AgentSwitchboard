@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ROOT=%~dp0"
where pwsh.exe >nul 2>nul || (echo [FAIL] PowerShell 7 is required.& endlocal & exit /b 127)
set "PY_KIND="
set "RESULT="
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
if not defined PY_KIND (echo [FAIL] Python 3 is required: usable python.exe or py.exe -3.& endlocal & exit /b 127)
pushd "%ROOT%" || (echo [FAIL] Cannot enter repository root.& endlocal & exit /b 2)
if "%PY_KIND%"=="python" goto :run_python
goto :run_py

:run_python
python.exe -m unittest tests.test_opencode_lsp_harness tests.test_opencode_cwd_independent_bootstrap -v
if errorlevel 1 set "RESULT=%ERRORLEVEL%"
if defined RESULT goto :fail
goto :powershell_checks

:run_py
py.exe -3 -m unittest tests.test_opencode_lsp_harness tests.test_opencode_cwd_independent_bootstrap -v
if errorlevel 1 set "RESULT=%ERRORLEVEL%"
if defined RESULT goto :fail

:powershell_checks
pwsh.exe -NoLogo -NoProfile -File "%ROOT%scripts\Test-OpenCodeLspHarness.ps1" -RootPath "%ROOT%."
if errorlevel 1 set "RESULT=%ERRORLEVEL%"
if defined RESULT goto :fail
pwsh.exe -NoLogo -NoProfile -File "%ROOT%scripts\Test-AgentDocumentationContract.ps1" -RootPath "%ROOT%."
if errorlevel 1 set "RESULT=%ERRORLEVEL%"
if defined RESULT goto :fail
git diff --check
if errorlevel 1 set "RESULT=%ERRORLEVEL%"
if defined RESULT goto :fail
popd
endlocal
exit /b 0

:fail
popd
endlocal & exit /b %RESULT%
