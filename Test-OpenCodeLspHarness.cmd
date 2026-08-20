@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ROOT=%~dp0"
set "PY_KIND="
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
if "%PY_KIND%"=="python" (
  python.exe -m unittest tests.test_opencode_lsp_harness -v
) else (
  py.exe -3 -m unittest tests.test_opencode_lsp_harness -v
)
if errorlevel 1 (set "R=%ERRORLEVEL%"& popd & endlocal & exit /b %R%)
pwsh -NoLogo -NoProfile -File "%ROOT%scripts\Test-OpenCodeLspHarness.ps1" -RootPath "%ROOT%."
if errorlevel 1 (set "R=%ERRORLEVEL%"& popd & endlocal & exit /b %R%)
pwsh -NoLogo -NoProfile -File "%ROOT%scripts\Test-AgentDocumentationContract.ps1" -RootPath "%ROOT%."
if errorlevel 1 (set "R=%ERRORLEVEL%"& popd & endlocal & exit /b %R%)
git diff --check
set "R=%ERRORLEVEL%"
popd
endlocal & exit /b %R%
