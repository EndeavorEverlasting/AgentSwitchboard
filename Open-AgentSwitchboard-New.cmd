@echo off
setlocal
set "_root=%~dp0"
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%_root%tooling\profiles\windows\Invoke-AgentSwitchboardTmuxLaunch.ps1" -Mode new -Operation Launch -ManifestPath "%_root%tooling\profiles\windows\windows-tmux-launch.json"
set "_code=%ERRORLEVEL%"
endlocal & exit /b %_code%
