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
echo Starting bounded unattended sprint through the technician-safe wrapper...
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\nap\Invoke-NapSprintSafely.ps1" %*
set "_code=%ERRORLEVEL%"
popd
echo.
echo Operator evidence: %LOCALAPPDATA%\AgentSwitchboard\Nap\operator-runs
echo Inner run evidence: %LOCALAPPDATA%\AgentSwitchboard\Nap\runs
if not "%_code%"=="0" echo The run stopped safely with exit code %_code%. Follow the displayed next action.
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
