[CmdletBinding()]
param(
    [string]$RepairId = 'OpenCode',
    [string]$RunId,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Repairing OpenCode installation inside Ubuntu...' -ForegroundColor Yellow
$wsl = Get-Command wsl.exe -ErrorAction Stop
$script = 'set -euo pipefail; curl -fsSL https://opencode.ai/install | bash; export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"; command -v opencode; opencode --version'
$output = (& $wsl.Source -d Ubuntu -- bash -lc $script 2>&1 | Out-String).Trim()
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    throw "OpenCode repair failed inside Ubuntu with exit code $exitCode. Output: $output"
}
if ($output -notmatch '(?im)^/.+opencode\s*$') {
    throw "OpenCode installer returned success but command resolution was not proven. Output: $output"
}

Write-Host "OpenCode repair verified inside Ubuntu.`n$output" -ForegroundColor Green
return 0
