[CmdletBinding()]
param(
    [string]$RepairId = 'OpenCode',
    [string]$RunId,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Repairing OpenCode installation..." -ForegroundColor Yellow
$proc = Start-Process -FilePath "wsl.exe" -ArgumentList "-d", "Ubuntu", "--", "bash", "-lc", "'curl -fsSL https://opencode.ai/install | bash'" -Wait -NoNewWindow -PassThru
Write-Host "OpenCode repair complete." -ForegroundColor Green
exit 0
