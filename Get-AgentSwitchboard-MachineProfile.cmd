@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "SCRIPT=%~dp0tooling\profiles\windows\Get-AgentSwitchboardMachineProfile.ps1"
if not exist "%SCRIPT%" (
  echo [FAIL] Machine profile detector is missing: %SCRIPT%
  exit /b 2
)
where powershell.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] Windows PowerShell was not found.
  exit /b 3
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -Mode Apply -Emit Json %*
exit /b %ERRORLEVEL%
