@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Technician Live-Cert Stage P02 Pull and Setup
cd /d "%~dp0"
set "STAGE_DISPATCHER=%~dp0tooling\profiles\windows\technician-live-cert\Invoke-TechnicianLiveCertStage.ps1"
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%STAGE_DISPATCHER%" -StageId P02 -RepoRoot "%~dp0" %*
set "EXITCODE=%ERRORLEVEL%"
if not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" ( echo. & echo Press any key to close this window. & pause >nul )
exit /b %EXITCODE%
