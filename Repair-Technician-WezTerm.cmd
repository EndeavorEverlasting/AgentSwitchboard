@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Technician Live-Cert Repair WezTerm
cd /d "%~dp0"
set "REPAIR_DISPATCHER=%~dp0tooling\profiles\windows\technician-live-cert\Invoke-TechnicianRepair.ps1"
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%REPAIR_DISPATCHER%" -RepairId WezTerm -RepoRoot "%~dp0" %*
set "EXITCODE=%ERRORLEVEL%"
if not "%AGENT_SWITCHBOARD_NO_PAUSE%"=="1" ( echo. & echo Press any key to close this window. & pause >nul )
exit /b %EXITCODE%
