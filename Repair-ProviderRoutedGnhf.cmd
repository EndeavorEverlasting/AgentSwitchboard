@echo off
setlocal
cd /d "%~dp0" || exit /b 1
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File ".\tooling\gnhf\Install-ProviderRoutedGnhf.ps1" -Apply
set "_code=%ERRORLEVEL%"
if not "%_code%"=="0" pause
endlocal & exit /b %_code%
