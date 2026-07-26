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

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\pi\Install-AgentSwitchboardPi.ps1" -Mode Install %*
set "RESULT=%ERRORLEVEL%"
if "%RESULT%"=="0" (
  echo [PASS] Pi installation and exact-version verification completed.
  echo [NEXT] Run Start-AgentSwitchboardPi.cmd
) else (
  echo [FAIL] Pi installation failed with exit code %RESULT%.
)
endlocal & exit /b %RESULT%
