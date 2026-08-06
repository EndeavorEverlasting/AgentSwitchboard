@echo off
setlocal EnableExtensions
set "ERRORLEVEL="
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\profiles\windows\harness\machine-profile\Invoke-MachineProfileHarnessCandidate.ps1" %*
set "_rc=%ERRORLEVEL%"
endlocal & exit /b %_rc%
