@echo off
setlocal
call "%~dp0tooling\gnhf\Setup-AgentSwitchboard.cmd" %*
set "_code=%ERRORLEVEL%"
endlocal & exit /b %_code%
