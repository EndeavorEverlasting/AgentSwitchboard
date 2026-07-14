@echo off
setlocal
where pwsh >nul 2>nul
if errorlevel 1 (
  echo [BLOCKED] PowerShell 7 ^(pwsh^) is required.
  echo Install PowerShell 7, then rerun this launcher.
  pause
  exit /b 9009
)
pushd "%~dp0"
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\nap\Configure-NapSprint.ps1" %*
set "_code=%ERRORLEVEL%"
popd
echo.
if not "%_code%"=="0" echo Configuration failed with exit code %_code%.
pause
endlocal & exit /b %_code%
