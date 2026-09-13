@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ROOT=%~dp0"
set "ENTRY=%ROOT%Test-AgentSwitchboard-FirstMate-Harness.ps1"

where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) is required.
  exit /b 1
)

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ENTRY%" %*
set "EXITCODE=%ERRORLEVEL%"
exit /b %EXITCODE%
