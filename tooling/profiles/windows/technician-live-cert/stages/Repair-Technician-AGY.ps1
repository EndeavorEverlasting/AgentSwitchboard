[CmdletBinding()]
param(
    [string]$RepairId = 'AGY',
    [string]$RunId,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Repairing AGY installation..." -ForegroundColor Yellow
$proc = Start-Process -FilePath "wsl.exe" -ArgumentList "-d", "Ubuntu", "--", "bash", "-lc", "'curl -fsSL https://antigravity.google/cli/install.sh | bash'" -Wait -NoNewWindow -PassThru
Write-Host "AGY repair complete." -ForegroundColor Green
exit 0
