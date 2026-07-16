@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-DeepSeekGnhfLiveProof.ps1" %*
set "_code=%ERRORLEVEL%"
endlocal & exit /b %_code%
