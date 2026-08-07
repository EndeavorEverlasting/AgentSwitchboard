[CmdletBinding()]
param(
    [string]$RootPath,
    [switch]$NoWrite,
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $rootLines = @(& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $rootLines.Count -eq 0) {
        throw 'Unable to resolve the AgentSwitchboard repository root.'
    }
    $RootPath = ([string]$rootLines[0]).Trim()
    if ([string]::IsNullOrWhiteSpace($RootPath)) {
        throw 'Unable to resolve the AgentSwitchboard repository root.'
    }
}
$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path

$registryPath = Join-Path $RootPath 'tooling\profiles\windows\harness\technician-ready\harness.registry.json'
if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
    throw "Technician bootstrap-order harness registry is missing: $registryPath"
}
$registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json

$components = @(
    foreach ($relativePath in @($registry.requiredPaths)) {
        [pscustomobject]@{
            path = [string]$relativePath
            exists = Test-Path -LiteralPath (Join-Path $RootPath ([string]$relativePath)) -PathType Leaf
        }
    }
)
$missingComponents = @($components | Where-Object { -not $_.exists })

$branchLines = @(& git -C $RootPath branch --show-current 2>$null)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to resolve the current Git branch state.'
}
$branch = if ($branchLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$branchLines[0])) {
    ([string]$branchLines[0]).Trim()
} elseif (-not [string]::IsNullOrWhiteSpace($env:GITHUB_HEAD_REF)) {
    ([string]$env:GITHUB_HEAD_REF).Trim()
} else {
    '<detached>'
}

$headLines = @(& git -C $RootPath rev-parse HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or $headLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$headLines[0])) {
    throw 'Unable to resolve the current Git HEAD.'
}
$head = ([string]$headLines[0]).Trim()
$status = if ($missingComponents.Count -eq 0) { 'repository-ready' } else { 'incomplete' }

$working = @(
    'Focused codebase map, workflow specs, artifact registry, skill routing, scoped skill, validators, opt-in hook, status reporter, operator guide, and CI are registered.',
    'The front door remains contractually gated so the prerequisite stage must return zero before the higher runtime engine is invoked.',
    'Source-token anchors are explicitly refactor-coupled: semantic source refactors update the contract and affected validators together.',
    'Generated validation and status evidence is local-operational and untracked.'
)
$broken = @()
if ($missingComponents.Count -gt 0) {
    $broken += "Missing tracked harness components: $($missingComponents.path -join ', ')"
}
$unproven = @(
    'No live WezTerm installation is proven by this harness.',
    'No WSL mutation or tmux session execution is proven by this harness.',
    'No visible terminal-window, provider, deployment, or operator-acceptance result is proven by this harness.'
)
$nextCommand = 'Test-TechnicianBootstrapOrderHarness.cmd'
$nextArtifact = 'bootstrap-order-harness-validation.json plus bootstrap-order-harness-status.md under the local run root'

$result = [ordered]@{
    schema = 'agentswitchboard.technician-bootstrap-order-harness-status.v1'
    status = $status
    repository = [string]$registry.repository
    branch = $branch
    head = $head
    components = @($components)
    missing = @($missingComponents | ForEach-Object { $_.path })
    working = $working
    broken = $broken
    unproven = $unproven
    proofCeiling = [string]$registry.proofCeiling
    nextOwner = 'repository harness owner'
    nextDependency = 'current exact HEAD remains unchanged'
    nextCommand = $nextCommand
    nextArtifact = $nextArtifact
    nextGate = 'focused completeness, order contracts, readiness contracts, and diff hygiene all pass at the same exact HEAD'
}

Write-Host 'TECHNICIAN BOOTSTRAP-ORDER HARNESS' -ForegroundColor Cyan
Write-Host ("Status: {0}" -f $status)
Write-Host ("Branch: {0}" -f $result.branch)
Write-Host ("HEAD: {0}" -f $result.head)
Write-Host ("Components: {0}/{1} present" -f ($components.Count - $missingComponents.Count), $components.Count)
Write-Host 'Working:'
$working | ForEach-Object { Write-Host ("- {0}" -f $_) }
Write-Host 'Broken:'
if ($broken.Count -eq 0) { Write-Host '- none detected by repository component inspection' } else { $broken | ForEach-Object { Write-Host ("- {0}" -f $_) } }
Write-Host 'Missing / unproven:'
$unproven | ForEach-Object { Write-Host ("- {0}" -f $_) }
Write-Host ("Next: {0}" -f $nextCommand)

if (-not $NoWrite) {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $runId = '{0}-{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')), ([guid]::NewGuid().ToString('N').Substring(0, 8))
        $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [System.IO.Path]::GetTempPath() }
        $OutputDirectory = Join-Path $base ("AgentSwitchboard/technician-bootstrap-order/runs/{0}" -f $runId)
    }
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    $jsonPath = Join-Path $OutputDirectory 'bootstrap-order-harness-status.json'
    $mdPath = Join-Path $OutputDirectory 'bootstrap-order-harness-status.md'
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding utf8
    $lines = @('# Technician Bootstrap-Order Harness Report','',('- Repository: `{0}`' -f $result.repository),('- Branch: `{0}`' -f $result.branch),('- HEAD: `{0}`' -f $result.head),('- Status: `{0}`' -f $result.status),('- Components: {0}/{1}' -f ($components.Count - $missingComponents.Count), $components.Count),'','## Working')
    $lines += @($working | ForEach-Object { '- ' + $_ })
    $lines += @('', '## Broken')
    if ($broken.Count -eq 0) { $lines += '- none detected by repository component inspection' } else { $lines += @($broken | ForEach-Object { '- ' + $_ }) }
    $lines += @('', '## Missing / unproven')
    $lines += @($unproven | ForEach-Object { '- ' + $_ })
    $lines += @('', '## Proof ceiling', [string]$result.proofCeiling)
    $lines += @('', '## Next action', ('- Owner: `{0}`' -f $result.nextOwner), ('- Dependency: `{0}`' -f $result.nextDependency), '```powershell', $nextCommand, '```', ('Expected artifact: `{0}`' -f $nextArtifact), ('Completion gate: {0}' -f $result.nextGate))
    $lines | Set-Content -LiteralPath $mdPath -Encoding utf8
    Write-Host ("JSON: {0}" -f $jsonPath)
    Write-Host ("Report: {0}" -f $mdPath)
}

if ($missingComponents.Count -gt 0) { exit 1 }
exit 0
