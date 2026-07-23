[CmdletBinding()]
param(
    [string]$StageId = 'P05',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Running P05-Launch-AGY stage..." -ForegroundColor Yellow

$setupScript = Join-Path $RepoRoot 'tooling\profiles\windows\Setup-TechnicianAgentSwitchboard.ps1'
Write-Host "Delegating to Setup-TechnicianAgentSwitchboard.ps1 -Mode agy..." -ForegroundColor Gray

$proc = Start-Process -FilePath "pwsh.exe" -ArgumentList "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$setupScript`"", "-Mode", "agy", "-RepoRoot", "`"$RepoRoot`"" -Wait -NoNewWindow -PassThru

if ($proc.ExitCode -ne 0) {
    Write-Warning "Launch AGY returned exit code $($proc.ExitCode)."
}

Write-Host "P05-Launch-AGY completed." -ForegroundColor Green
return 0
