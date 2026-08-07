[CmdletBinding()]
param(
    [string]$RootPath,
    [string]$ExpectedHead,
    [string]$BaseRef
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $rootLines = @(& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $rootLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$rootLines[0])) {
        throw 'Unable to resolve repository root.'
    }
    $RootPath = ([string]$rootLines[0]).Trim()
}
$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path

$originLines = @(& git -C $RootPath remote get-url origin 2>$null)
if ($LASTEXITCODE -ne 0 -or $originLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$originLines[0])) {
    throw 'Unable to resolve origin remote.'
}
$origin = ([string]$originLines[0]).Trim()
if ($origin -notmatch 'EndeavorEverlasting[/:]AgentSwitchboard(?:\.git)?$') {
    throw "Wrong repository origin: $origin"
}

$branchLines = @(& git -C $RootPath branch --show-current 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve current branch.' }
if ($branchLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$branchLines[0])) {
    throw 'Pre-push validation requires an attached branch; detached HEAD is not an outgoing branch.'
}
$branch = ([string]$branchLines[0]).Trim()

$headLines = @(& git -C $RootPath rev-parse HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or $headLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$headLines[0])) {
    throw 'Unable to resolve current HEAD.'
}
$head = ([string]$headLines[0]).Trim()
if (-not [string]::IsNullOrWhiteSpace($ExpectedHead) -and $head -ne $ExpectedHead.Trim()) {
    throw "Exact-head mismatch. Expected $($ExpectedHead.Trim()); current HEAD is $head"
}

$registryPath = Join-Path $RootPath 'tooling\profiles\windows\harness\technician-ready\harness.registry.json'
if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
    throw "Harness registry is missing: $registryPath"
}
$registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json

$relevantPaths = [Collections.Generic.List[string]]::new()
foreach ($path in @($registry.requiredPaths)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$path)) { [void]$relevantPaths.Add([string]$path) }
}
foreach ($owner in @(
    [string]$registry.canonicalOwners.frontDoor,
    [string]$registry.canonicalOwners.prerequisiteGate,
    [string]$registry.canonicalOwners.runtimeEngine
)) {
    if (-not [string]::IsNullOrWhiteSpace($owner) -and $owner -notin $relevantPaths) { [void]$relevantPaths.Add($owner) }
}

$dirty = @(& git -C $RootPath status --porcelain --untracked-files=no -- @relevantPaths 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect harness-owned working-tree state.' }
if ($dirty.Count -gt 0) {
    throw "Harness-owned tracked files are dirty; commit or preserve them before push:`n$($dirty -join "`n")"
}

if ([string]::IsNullOrWhiteSpace($BaseRef)) {
    $upstreamLines = @(& git -C $RootPath rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>$null)
    if ($LASTEXITCODE -eq 0 -and $upstreamLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$upstreamLines[0])) {
        $BaseRef = ([string]$upstreamLines[0]).Trim()
    }
    else {
        $global:LASTEXITCODE = 0
        & git -C $RootPath show-ref --verify --quiet refs/remotes/origin/main
        if ($LASTEXITCODE -eq 0) {
            $BaseRef = 'origin/main'
        }
        else {
            throw 'Unable to resolve an upstream or origin/main base for outgoing diff validation. Supply -BaseRef explicitly.'
        }
    }
}

$baseLines = @(& git -C $RootPath rev-parse $BaseRef 2>$null)
if ($LASTEXITCODE -ne 0 -or $baseLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$baseLines[0])) {
    throw "Unable to resolve pre-push base ref: $BaseRef"
}

$mergeBaseLines = @(& git -C $RootPath merge-base $BaseRef HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or $mergeBaseLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$mergeBaseLines[0])) {
    throw "Unable to resolve merge base between $BaseRef and HEAD."
}
$mergeBase = ([string]$mergeBaseLines[0]).Trim()

Push-Location -LiteralPath $RootPath
try {
    $validator = Join-Path $RootPath 'Test-TechnicianBootstrapOrderHarness.cmd'
    if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
        throw "Canonical harness validator is missing: $validator"
    }
    & $validator
    if ($LASTEXITCODE -ne 0) { throw "Harness validation failed with exit code $LASTEXITCODE" }

    & git -C $RootPath diff --check "$mergeBase..HEAD"
    if ($LASTEXITCODE -ne 0) { throw "Outgoing commit-range diff hygiene failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

$afterHeadLines = @(& git -C $RootPath rev-parse HEAD 2>$null)
if ($LASTEXITCODE -ne 0 -or $afterHeadLines.Count -eq 0 -or ([string]$afterHeadLines[0]).Trim() -ne $head) {
    throw 'HEAD changed during pre-push validation.'
}
$afterDirty = @(& git -C $RootPath status --porcelain --untracked-files=no -- @relevantPaths 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'Unable to re-check harness-owned working-tree state.' }
if ($afterDirty.Count -gt 0) {
    throw "Pre-push validation mutated harness-owned tracked files:`n$($afterDirty -join "`n")"
}

Write-Host 'PASS: technician bootstrap-order pre-push gate passed.' -ForegroundColor Green
Write-Host ("Branch: {0}" -f $branch)
Write-Host ("HEAD:   {0}" -f $head)
Write-Host ("Base:   {0} ({1})" -f $BaseRef, $mergeBase)
