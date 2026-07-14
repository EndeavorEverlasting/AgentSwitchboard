@echo off
setlocal
where pwsh >nul 2>nul
if errorlevel 1 goto :pwsh_missing

pushd "%~dp0"
set "_config=%LOCALAPPDATA%\AgentSwitchboard\Nap\nap-sprint.json"
if not exist "%_config%" (
  echo No nap sprint configuration exists yet.
  echo Starting the one-time configuration wizard...
  pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\nap\Configure-NapSprint.ps1"
  if errorlevel 1 goto :configuration_failed
)

echo.
echo Starting bounded unattended sprint...
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\nap\Start-AgentSwitchboardNap.ps1" %*
set "_code=%ERRORLEVEL%"
popd
echo.
echo Evidence root: %LOCALAPPDATA%\AgentSwitchboard\Nap\runs
if not "%_code%"=="0" echo Nap sprint stopped or failed with exit code %_code%.
pause
endlocal & exit /b %_code%

:configuration_failed
set "_code=%ERRORLEVEL%"
popd
echo.
echo Configuration did not complete. No coding sprint was started.
pause
endlocal & exit /b %_code%

:pwsh_missing
echo [BLOCKED] PowerShell 7 ^(pwsh^) is required.
echo Install PowerShell 7, then rerun this launcher.
pause
endlocal & exit /b 9009
