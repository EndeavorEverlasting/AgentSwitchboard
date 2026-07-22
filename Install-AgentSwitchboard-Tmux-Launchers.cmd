@echo off
setlocal
set "_root=%~dp0"
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%_root%tooling\profiles\windows\Install-AgentSwitchboardTmuxLaunchers.ps1" -Mode Apply
set "_code=%ERRORLEVEL%"
endlocal & exit /b %_code%
