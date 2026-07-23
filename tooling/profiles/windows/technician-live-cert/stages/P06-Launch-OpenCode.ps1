[CmdletBinding()]
param(
    [string]$StageId = 'P06',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Running P06-Launch-OpenCode stage..." -ForegroundColor Yellow

$setupScript = Join-Path $RepoRoot 'tooling\profiles\windows\Setup-TechnicianAgentSwitchboard.ps1'
Write-Host "Delegating to Setup-TechnicianAgentSwitchboard.ps1 -Mode opencode..." -ForegroundColor Gray

$proc = Start-Process -FilePath "pwsh.exe" -ArgumentList "-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$setupScript`"", "-Mode", "opencode", "-RepoRoot", "`"$RepoRoot`"" -Wait -NoNewWindow -PassThru

if ($proc.ExitCode -ne 0) {
    Write-Warning "Launch OpenCode returned exit code $($proc.ExitCode)."
}

Write-Host "P06-Launch-OpenCode completed." -ForegroundColor Green
return 0
