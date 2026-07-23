[CmdletBinding()]
param(
    [string]$StageId = 'P09',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Running P09-Hermes-Optional stage..." -ForegroundColor Yellow

$setupScript = Join-Path $RepoRoot 'tooling\profiles\windows\Setup-TechnicianAgentSwitchboard.ps1'
Write-Host "Delegating to Setup-TechnicianAgentSwitchboard.ps1 -Mode hermes..." -ForegroundColor Gray

$proc = Start-Process -FilePath "pwsh.exe" -ArgumentList "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$setupScript`"", "-Mode", "hermes", "-RepoRoot", "`"$RepoRoot`"" -Wait -NoNewWindow -PassThru

if ($proc.ExitCode -ne 0) {
    Write-Warning "Launch Hermes returned exit code $($proc.ExitCode)."
}

Write-Host "P09-Hermes-Optional completed." -ForegroundColor Green
return 0
