@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "ROOT=%~dp0"
where pwsh.exe >nul 2>nul
if errorlevel 1 (
  echo PowerShell 7 is required to validate the technician bootstrap order.
  endlocal & exit /b 127
)
pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%ROOT%scripts\Test-TechnicianBootstrapOrder.ps1" -RootPath "%ROOT%"
set "RESULT=%ERRORLEVEL%"
endlocal & exit /b %RESULT%
