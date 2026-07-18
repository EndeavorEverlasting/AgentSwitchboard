@echo off
setlocal
title AgentSwitchboard - Install BlacksmithGuild GNHF Night Panel
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 ^(pwsh.exe^) is required.
  echo Install or repair PowerShell 7, then run this installer again.
  pause
  exit /b 1
)

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\gnhf\Install-BlacksmithGuildNightPanel.ps1" -Apply %*
set "_code=%ERRORLEVEL%"
echo.
if not "%_code%"=="0" (
  echo Installation failed with exit code %_code%.
  echo Review the message above. Existing WezTerm configuration was preserved or backed up before mutation.
) else (
  echo Installation completed.
  echo Open WezTerm, open the launch menu, and select:
  echo   BlacksmithGuild - GNHF Night Shift
)
echo.
pause
endlocal & exit /b %_code%
