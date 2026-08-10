@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ROOT=%~dp0"
where pwsh.exe >nul 2>nul || (echo [FAIL] PowerShell 7 is required.& endlocal & exit /b 127)
pushd "%ROOT%" || (echo [FAIL] Cannot enter repository root.& endlocal & exit /b 2)
python -m unittest tests.test_opencode_lsp_harness -v
if errorlevel 1 goto :fail
pwsh.exe -NoLogo -NoProfile -File "%ROOT%scripts\Test-OpenCodeLspHarness.ps1" -RootPath "%ROOT%"
if errorlevel 1 goto :fail
git diff --check
if errorlevel 1 goto :fail
popd
endlocal & exit /b 0
:fail
set "RESULT=%ERRORLEVEL%"
popd
endlocal & exit /b %RESULT%
