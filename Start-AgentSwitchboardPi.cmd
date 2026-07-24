@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 (
  echo [FAIL] Could not enter the AgentSwitchboard repository root.
  exit /b 10
)

where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) is required.
  exit /b 11
)

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\pi\Start-AgentSwitchboardPi.ps1" %*
set "RESULT=%ERRORLEVEL%"
endlocal & exit /b %RESULT%
