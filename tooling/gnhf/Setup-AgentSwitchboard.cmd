@echo off
setlocal
title AgentSwitchboard Robust Setup
pushd "%~dp0"

echo ============================================================
echo AgentSwitchboard Robust Setup
echo Hermes + GNHF fleet + readiness state + validation evidence
echo ============================================================
echo.

where pwsh >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh^) was not found on PATH.
  echo Install PowerShell 7, reopen this launcher, and try again.
  set "_code=1"
  goto :finish
)

pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup-AgentSwitchboard.ps1" -InstallOpenCodeAndCopilot %*
set "_code=%ERRORLEVEL%"

:finish
echo.
if "%_code%"=="0" (
  echo [DONE] Setup completed. Review the readiness table and log paths above.
) else (
  echo [FAIL] Setup exited with code %_code%.
  echo Evidence is under %%LOCALAPPDATA%%\AgentSwitchboard\setup-logs.
)
echo.
pause
popd
endlocal & exit /b %_code%
