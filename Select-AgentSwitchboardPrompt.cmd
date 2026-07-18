@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tooling\prompts\Select-AgentSwitchboardPrompt.ps1" %*
set "_code=%ERRORLEVEL%"
endlocal & exit /b %_code%
