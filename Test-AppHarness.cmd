@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "PSHOST="
where pwsh.exe >nul 2>&1
if not errorlevel 1 set "PSHOST=pwsh.exe"
if not defined PSHOST (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) is required for the offline app-harness proof.
  exit /b 23
)
for %%I in ("%~dp0.") do set "ROOT=%%~fI"
"%PSHOST%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\scripts\Test-AppHarnessOneCommandProof.ps1" -RootPath "%ROOT%" %*
set "RESULT=%ERRORLEVEL%"
endlocal & exit /b %RESULT%
