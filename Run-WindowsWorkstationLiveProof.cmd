@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
title AgentSwitchboard Windows workstation deploy and live proof
set "ROOT=%~dp0"

where pwsh.exe >nul 2>&1
if errorlevel 1 (
  echo [FAIL] PowerShell 7 ^(pwsh.exe^) is required.
  pause >nul
  exit /b 2
)

if not exist "%ROOT%Setup-TmuxGnhfWorkspace.cmd" (
  echo [FAIL] Core workstation setup launcher is missing:
  echo        %ROOT%Setup-TmuxGnhfWorkspace.cmd
  pause >nul
  exit /b 2
)

echo ============================================================
echo  AgentSwitchboard Windows workstation deployment + proof
echo ============================================================
echo.
echo Phase 1 deploys or reuses WezTerm, WSL, tmux, GNHF, and OpenCode.
echo Phase 2 installs and runs the disposable focus-independent proof lane.
echo No provider credentials, personal repositories, Git pushes, or default
echo branches are written by this launcher.
echo.

set "AGENT_SWITCHBOARD_NO_PAUSE=1"
call "%ROOT%Setup-TmuxGnhfWorkspace.cmd" apply
set "_setup_code=%ERRORLEVEL%"
if "%_setup_code%"=="30" (
  echo.
  echo [WAIT] Windows reboot or WSL first-run initialization is required.
  echo        Complete it, then double-click this same CMD again.
  pause >nul
  exit /b 30
)
if not "%_setup_code%"=="0" (
  echo.
  echo [FAIL] Core workstation deployment stopped with exit code %_setup_code%.
  pause >nul
  exit /b %_setup_code%
)

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%tooling\wsl\Install-WindowsWorkstationLiveProof.ps1" -SourceRoot "%ROOT%tooling\wsl" -ManifestPath "%ROOT%tooling\wsl\tmux-gnhf-workstation.example.json" -Apply -RunAfterInstall -Confirm:$false
set "_code=%ERRORLEVEL%"
if not "%_code%"=="0" (
  echo.
  echo [FAIL] The live proof did not complete. The exact failure and artifact
  echo        path are printed above. No lower proof level is promoted.
  pause >nul
) else (
  echo.
  echo [PASS] Workstation deployment and live proof completed.
)
endlocal & exit /b %_code%
