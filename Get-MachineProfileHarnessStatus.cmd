@echo off
setlocal
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\profiles\windows\Get-MachineProfileHarnessStatus.ps1" %*
set "_rc=%ERRORLEVEL%"
endlocal & exit /b %_rc%
