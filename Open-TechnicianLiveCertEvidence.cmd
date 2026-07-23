@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Open Technician Live-Cert Evidence
cd /d "%~dp0"
set "OPEN_SCRIPT=%~dp0tooling\profiles\windows\technician-live-cert\Open-TechnicianLiveCertEvidence.ps1"
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%OPEN_SCRIPT%" %*
set "EXITCODE=%ERRORLEVEL%"
if not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" ( echo. & echo Press any key to close this window. & pause >nul )
exit /b %EXITCODE%
