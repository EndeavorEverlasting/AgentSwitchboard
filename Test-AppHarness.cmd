@echo off
setlocal
set "_ROOT=%~dp0"
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%_ROOT%scripts\Test-AppHarness.ps1" %*
set "_CODE=%ERRORLEVEL%"
endlocal & exit /b %_CODE%
