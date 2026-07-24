@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Install Technician Live-Cert Desktop Shortcuts
cd /d "%~dp0"
set "INSTALL_SCRIPT=%~dp0tooling\profiles\windows\technician-live-cert\Install-TechnicianLiveCertShortcuts.ps1"
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%INSTALL_SCRIPT%" -RepoRoot "%~dp0" %*
set "EXITCODE=%ERRORLEVEL%"
if not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" ( echo. & echo Press any key to close this window. & pause >nul )
exit /b %EXITCODE%
