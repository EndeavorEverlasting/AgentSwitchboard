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

$readyCmd = Join-Path $RepoRoot 'Technician-AgentSwitchboard-Ready.cmd'
if (-not (Test-Path -LiteralPath $readyCmd -PathType Leaf)) {
    throw "Canonical technician readiness CMD is missing: $readyCmd"
}

$branch = (& git.exe -C $RepoRoot symbolic-ref --quiet --short HEAD 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
    throw 'P02 requires an attached Git branch. The repository is detached.'
}
$beforeHead = (& git.exe -C $RepoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to resolve repository HEAD before P02.'
}

$startedAt = Get-Date
$env:AGENT_SWITCHBOARD_NO_PAUSE = '1'
& cmd.exe /d /c "call `"$readyCmd`" setup `"$RepoRoot`" `"$branch`""
$setupExit = $LASTEXITCODE
if ($setupExit -ne 0) {
    throw "Technician-AgentSwitchboard-Ready.cmd setup failed with exit code $setupExit."
}

$afterHead = (& git.exe -C $RepoRoot rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to resolve repository HEAD after P02.'
}
if ($afterHead -ne $beforeHead) {
    throw "P02 setup changed repository HEAD unexpectedly. Before=$beforeHead After=$afterHead"
}

$dirty = @(& git.exe -C $RepoRoot status --porcelain=v1 --untracked-files=normal 2>$null)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to verify repository cleanliness after P02.'
}
if ($dirty.Count -gt 0) {
    throw "P02 setup completed but the repository is no longer clean. Nothing will be discarded automatically."
}

$fleetStatePath = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\GnhfFleet\state.json'
if (-not (Test-Path -LiteralPath $fleetStatePath -PathType Leaf)) {
    throw "P02 setup did not produce canonical AgentSwitchboard fleet state: $fleetStatePath"
}
$fleetState = Get-Content -LiteralPath $fleetStatePath -Raw | ConvertFrom-Json
if ($fleetState.schemaVersion -ne 1 -or $null -eq $fleetState.agents) {
    throw "P02 observed malformed AgentSwitchboard fleet state: $fleetStatePath"
}

$agentShim = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\bin\AgentSwitchboard.cmd'
if (-not (Test-Path -LiteralPath $agentShim -PathType Leaf)) {
    throw "P02 setup did not install the AgentSwitchboard command shim: $agentShim"
}

$setupSummary = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\technician-ready\runs') `
    -Filter 'technician-ready-summary.json' -File -Recurse -ErrorAction Stop |
    Where-Object { $_.LastWriteTime -ge $startedAt } |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if (-not $setupSummary) {
    throw 'P02 setup completed without producing a fresh technician-ready summary.'
}
$setupResult = Get-Content -LiteralPath $setupSummary.FullName -Raw | ConvertFrom-Json
if ($setupResult.status -ne 'success') {
    throw "P02 setup summary is not successful: $($setupSummary.FullName)"
}
if (-not $setupResult.startupReadiness.stateObserved) {
    throw "P02 setup summary did not observe canonical fleet state: $($setupSummary.FullName)"
}
if ($setupResult.startupReadiness.overallStatus -in @('not-configured', 'blocked')) {
    throw "P02 setup left AgentSwitchboard unusable: $($setupResult.startupReadiness.overallStatus)"
}

$summary = [ordered]@{
    schema = 'agentswitchboard.technician-live-cert-setup.v2'
    branch = $branch
    beforeHead = $beforeHead
    afterHead = $afterHead
    exitCode = $setupExit
    repositoryClean = $true
    delegatedTo = $readyCmd
    fleetStatePath = $fleetStatePath
    agentSwitchboardShim = $agentShim
    readinessStatus = $setupResult.startupReadiness.overallStatus
    readinessEvidence = $setupResult.startupReadiness.evidence
    setupSummary = $setupSummary.FullName
    passed = $true
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $StageDir 'setup-summary.json') -Encoding utf8NoBOM

Write-Host "P02-Pull-And-Setup passed at $afterHead with AgentSwitchboard readiness '$($setupResult.startupReadiness.overallStatus)'." -ForegroundColor Green
return 0
