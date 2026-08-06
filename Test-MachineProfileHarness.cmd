@echo off
setlocal EnableExtensions
set "ERRORLEVEL="
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Test-MachineProfileHarnessCompleteness.ps1"
set "_rc=%ERRORLEVEL%"
endlocal & exit /b %_rc%
