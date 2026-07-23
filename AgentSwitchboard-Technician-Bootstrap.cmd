@echo off
setlocal EnableExtensions DisableDelayedExpansion
title AgentSwitchboard Technician Bootstrap
cd /d "%~dp0"

echo ============================================================
echo  AgentSwitchboard Technician Bootstrap
echo ============================================================
echo.

call "%~dp0Pull-Repo-And-Setup-AgentSwitchboard.cmd" %*
set "EXITCODE=%ERRORLEVEL%"

if not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" (
  echo.
  echo Press any key to close this window.
  pause >nul
)

exit /b %EXITCODE%
