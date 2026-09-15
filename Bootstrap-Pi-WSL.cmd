@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem One-click Pi bootstrap for the user-owned Ubuntu/WSL runtime.
rem This intentionally does not replace Bootstrap-Pi-SystemWide.cmd.
set "ASB_SOURCE_REPO=%~dp0"
call "%~dp0Pull-And-Run-AgentSwitchboard.cmd" bootstrap-pi-wsl "%~dp0" main
exit /b %ERRORLEVEL%
