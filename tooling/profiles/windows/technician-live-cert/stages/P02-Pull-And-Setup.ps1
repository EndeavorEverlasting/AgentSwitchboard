[CmdletBinding()]
param(
    [string]$StageId = 'P02',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Running P02-Pull-And-Setup stage...' -ForegroundColor Yellow

$pullRunCmd = Join-Path $RepoRoot 'Pull-And-Run-AgentSwitchboard.cmd'
if (-not (Test-Path -LiteralPath $pullRunCmd -PathType Leaf)) {
    throw "Canonical technician pull/run CMD is missing: $pullRunCmd"
}

$branch = (& git.exe -C $RepoRoot symbolic-ref --quiet --short HEAD 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
    throw 'P02 requires an attached Git branch. The repository is detached.'
}
$beforeHead = (& git.exe -C $RepoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve repository HEAD before P02.' }

Write-Host "Delegating repository fast-forward and setup to $pullRunCmd" -ForegroundColor Gray
& $pullRunCmd setup $RepoRoot $branch
$setupExit = $LASTEXITCODE
if ($setupExit -ne 0) {
    throw "Pull-And-Run-AgentSwitchboard.cmd setup failed with exit code $setupExit."
}

$afterHead = (& git.exe -C $RepoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve repository HEAD after P02.' }
$dirty = @(& git.exe -C $RepoRoot status --porcelain=v1 --untracked-files=normal 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'Unable to verify repository cleanliness after P02.' }
if ($dirty.Count -gt 0) {
    throw "P02 setup completed but the repository is no longer clean. Nothing will be discarded automatically."
}

$summary = [ordered]@{
    schema = 'agentswitchboard.technician-live-cert-setup.v1'
    branch = $branch
    beforeHead = $beforeHead
    afterHead = $afterHead
    exitCode = $setupExit
    repositoryClean = $true
    delegatedTo = $pullRunCmd
    passed = $true
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $StageDir 'setup-summary.json') -Encoding utf8NoBOM

Write-Host "P02-Pull-And-Setup passed at $afterHead." -ForegroundColor Green
return 0
