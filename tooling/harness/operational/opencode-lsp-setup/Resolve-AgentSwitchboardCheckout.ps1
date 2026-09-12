[CmdletBinding()]
param(
    [string]$PreferredPath,
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$ExpectedBranch,
    [Parameter(Mandatory=$true)][ValidatePattern('^[0-9a-fA-F]{40}$')][string]$ExpectedHead,
    [switch]$AllowRemoteBranchAdvance
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

$repository = 'EndeavorEverlasting/AgentSwitchboard'
$canonicalUrl = 'https://github.com/EndeavorEverlasting/AgentSwitchboard.git'
$canonicalOriginPattern = '^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/|git://github\.com/)EndeavorEverlasting/AgentSwitchboard(?:\.git)?/?$'
$base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
$stateRoot = Join-Path $base 'AgentSwitchboard\opencode-lsp'
$runId = '{0}-{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')), ([guid]::NewGuid().ToString('N').Substring(0,8))
$evidenceDirectory = Join-Path $stateRoot "runs\$runId"
$null = New-Item -ItemType Directory -Path $evidenceDirectory -Force
$receiptPath = Join-Path $evidenceDirectory 'opencode-lsp-checkout-resolution.json'
$reportPath = Join-Path $evidenceDirectory 'opencode-lsp-checkout-resolution.md'

$sourceRoot = $null
$sourceMode = 'unresolved'
$worktreePath = $null
$origin = $null
$actualHead = $null
$remoteHeadAtResolution = $null
$remoteAdvancedAfterSnapshot = $false
$failureCode = $null
$failureMessage = $null
$searchedCandidates = [Collections.Generic.List[string]]::new()
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

function Stop-Recovery {
    param([Parameter(Mandatory)][string]$Code, [Parameter(Mandatory)][string]$Message)
    throw ([InvalidOperationException]::new("$Code|$Message"))
}

function Add-Candidate {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try { $full = [IO.Path]::GetFullPath($Path) } catch { return }
    if ($seen.Add($full)) { [void]$searchedCandidates.Add($full) }
}

function Get-CanonicalCheckout {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $null }
    $rootLines = @(& git -C $Path rev-parse --show-toplevel 2>&1)
    if ($LASTEXITCODE -ne 0 -or $rootLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$rootLines[0])) { return $null }
    $root = ([string]$rootLines[0]).Trim()
    $originLines = @(& git -C $root remote get-url origin 2>&1)
    if ($LASTEXITCODE -ne 0 -or $originLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$originLines[0])) { return $null }
    $candidateOrigin = ([string]$originLines[0]).Trim()
    if ($candidateOrigin -notmatch $canonicalOriginPattern) { return $null }
    return [pscustomobject]@{ Root = $root; Origin = $candidateOrigin }
}

function Add-BoundedNeighborCandidates {
    param([string]$Anchor)
    if ([string]::IsNullOrWhiteSpace($Anchor) -or -not (Test-Path -LiteralPath $Anchor -PathType Container)) { return }
    foreach ($child in @(Get-ChildItem -LiteralPath $Anchor -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($child.Name -match '(?i)^AgentSwitchBoard(?:[-_. ].*)?$') { Add-Candidate $child.FullName }
    }
}

try {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Stop-Recovery 'GIT_NOT_FOUND' 'Git is required to resolve or acquire the canonical AgentSwitchboard checkout.' }

    Add-Candidate $PreferredPath
    Add-Candidate ([string](Get-Location).Path)

    if (-not [string]::IsNullOrWhiteSpace($PreferredPath)) {
        try {
            $preferredFull = [IO.Path]::GetFullPath($PreferredPath)
            Add-BoundedNeighborCandidates $preferredFull
            $preferredParent = Split-Path -Parent $preferredFull
            Add-BoundedNeighborCandidates $preferredParent
        }
        catch { }
    }

    $checkoutRoot = Join-Path $base 'AgentSwitchboard\checkouts'
    Add-BoundedNeighborCandidates $checkoutRoot

    foreach ($candidate in $searchedCandidates) {
        $resolved = Get-CanonicalCheckout -Path $candidate
        if ($resolved) {
            $sourceRoot = [string]$resolved.Root
            $origin = [string]$resolved.Origin
            $sourceMode = 'bounded-existing-checkout'
            break
        }
    }

    if (-not $sourceRoot) {
        $null = New-Item -ItemType Directory -Path $checkoutRoot -Force
        $clonePath = Join-Path $checkoutRoot "canonical-$($ExpectedHead.Substring(0,8))"
        if (Test-Path -LiteralPath $clonePath) {
            $existingClone = Get-CanonicalCheckout -Path $clonePath
            if ($existingClone) {
                $sourceRoot = [string]$existingClone.Root
                $origin = [string]$existingClone.Origin
                $sourceMode = 'reused-isolated-clone'
            }
            else {
                $clonePath = Join-Path $checkoutRoot ("canonical-{0}-{1}" -f $ExpectedHead.Substring(0,8), ([guid]::NewGuid().ToString('N').Substring(0,8)))
            }
        }
        if (-not $sourceRoot) {
            $cloneLines = @(& git clone --no-checkout $canonicalUrl $clonePath 2>&1)
            if ($LASTEXITCODE -ne 0) { Stop-Recovery 'ISOLATED_CLONE_FAILED' 'No canonical checkout was found and the isolated LOCALAPPDATA clone failed. Existing folders were not removed or rewritten.' }
            $cloned = Get-CanonicalCheckout -Path $clonePath
            if (-not $cloned) { Stop-Recovery 'ISOLATED_CLONE_IDENTITY_FAILED' 'The isolated clone did not prove the exact canonical repository origin.' }
            $sourceRoot = [string]$cloned.Root
            $origin = [string]$cloned.Origin
            $sourceMode = 'created-isolated-clone'
        }
    }

    $fetchLines = @(& git -C $sourceRoot fetch --no-tags origin "refs/heads/${ExpectedBranch}:refs/remotes/origin/${ExpectedBranch}" 2>&1)
    if ($LASTEXITCODE -ne 0) { Stop-Recovery 'EXPECTED_BRANCH_FETCH_FAILED' 'The exact harness branch could not be fetched without force.' }

    $remoteHeadLines = @(& git -C $sourceRoot rev-parse "refs/remotes/origin/$ExpectedBranch" 2>&1)
    if ($LASTEXITCODE -ne 0 -or $remoteHeadLines.Count -eq 0) { Stop-Recovery 'EXPECTED_BRANCH_NOT_RESOLVED' 'The fetched harness branch could not be resolved.' }
    $remoteHeadAtResolution = ([string]$remoteHeadLines[0]).Trim().ToLowerInvariant()
    $expectedHeadNormalized = $ExpectedHead.ToLowerInvariant()
    if ($remoteHeadAtResolution -ne $expectedHeadNormalized) {
        if (-not $AllowRemoteBranchAdvance) {
            Stop-Recovery 'REMOTE_HEAD_MISMATCH' "The remote harness branch is at $remoteHeadAtResolution, not expected exact head $ExpectedHead. Refusing stale proof."
        }
        $ancestorLines = @(& git -C $sourceRoot merge-base --is-ancestor $ExpectedHead "refs/remotes/origin/$ExpectedBranch" 2>&1)
        if ($LASTEXITCODE -ne 0) {
            Stop-Recovery 'EXPECTED_HEAD_NO_LONGER_REACHABLE' "The remote branch moved to $remoteHeadAtResolution and the selected exact head $ExpectedHead is no longer an ancestor. Refusing to reinterpret the snapshot."
        }
        $remoteAdvancedAfterSnapshot = $true
    }

    $worktreeRoot = Join-Path $base 'AgentSwitchboard\worktrees'
    $null = New-Item -ItemType Directory -Path $worktreeRoot -Force
    $worktreePath = Join-Path $worktreeRoot "opencode-lsp-harness-$($ExpectedHead.Substring(0,8))"

    if (Test-Path -LiteralPath $worktreePath) {
        $existingWorktree = Get-CanonicalCheckout -Path $worktreePath
        $canReuse = $false
        if ($existingWorktree) {
            $existingHeadLines = @(& git -C $worktreePath rev-parse HEAD 2>&1)
            $existingDirtyLines = @(& git -C $worktreePath status --porcelain=v1 2>&1)
            if ($LASTEXITCODE -eq 0 -and $existingHeadLines.Count -gt 0) {
                $existingHead = ([string]$existingHeadLines[0]).Trim().ToLowerInvariant()
                $canReuse = ($existingHead -eq $expectedHeadNormalized) -and ($existingDirtyLines.Count -eq 0)
            }
        }
        if (-not $canReuse) {
            $worktreePath = Join-Path $worktreeRoot ("opencode-lsp-harness-{0}-{1}" -f $ExpectedHead.Substring(0,8), ([guid]::NewGuid().ToString('N').Substring(0,8)))
        }
    }

    if (-not (Test-Path -LiteralPath $worktreePath -PathType Container)) {
        $worktreeLines = @(& git -C $sourceRoot worktree add --detach $worktreePath $ExpectedHead 2>&1)
        if ($LASTEXITCODE -ne 0) { Stop-Recovery 'ISOLATED_WORKTREE_FAILED' 'Unable to create the isolated exact-head harness worktree. Existing checkout state was preserved.' }
    }

    $verifiedWorktree = Get-CanonicalCheckout -Path $worktreePath
    if (-not $verifiedWorktree) { Stop-Recovery 'WORKTREE_IDENTITY_FAILED' 'The isolated proof worktree does not have the exact canonical repository origin.' }
    $worktreeHeadLines = @(& git -C $worktreePath rev-parse HEAD 2>&1)
    if ($LASTEXITCODE -ne 0 -or $worktreeHeadLines.Count -eq 0) { Stop-Recovery 'WORKTREE_HEAD_FAILED' 'Unable to read the isolated proof worktree HEAD.' }
    $actualHead = ([string]$worktreeHeadLines[0]).Trim().ToLowerInvariant()
    if ($actualHead -ne $expectedHeadNormalized) { Stop-Recovery 'WORKTREE_HEAD_MISMATCH' "Isolated worktree is at $actualHead, not $ExpectedHead." }
    $worktreeDirty = @(& git -C $worktreePath status --porcelain=v1 2>&1)
    if ($LASTEXITCODE -ne 0 -or $worktreeDirty.Count -gt 0) { Stop-Recovery 'WORKTREE_NOT_CLEAN' 'The isolated exact-head worktree is not clean; it was preserved and not rewritten.' }
}
catch {
    $raw = [string]$_.Exception.Message
    if ($raw -match '^([A-Z0-9_]+)\|(.*)$') {
        $failureCode = $Matches[1]
        $failureMessage = $Matches[2]
    }
    else {
        $failureCode = 'UNEXPECTED_CHECKOUT_RECOVERY_FAILURE'
        $failureMessage = 'Checkout recovery failed before completion. Existing folders were preserved.'
    }
}

$status = if ($failureCode) { 'failed' } else { 'resolved' }
$nextCommand = if ($status -eq 'resolved') { "& `"$(Join-Path $worktreePath 'Test-OpenCodeLspHarness.cmd')`"" } else { 'repair the named checkout-recovery failure boundary, then rerun this resolver at the same expected branch/head' }
$result = [ordered]@{
    schema = 'agentswitchboard.opencode-lsp-checkout-resolution.v1'
    status = $status
    failureCode = $failureCode
    failureMessage = $failureMessage
    repository = $repository
    preferredPath = $PreferredPath
    sourceMode = $sourceMode
    sourceRepoPath = $sourceRoot
    origin = $origin
    expectedBranch = $ExpectedBranch
    expectedHead = $expectedHeadNormalized
    allowRemoteBranchAdvance = [bool]$AllowRemoteBranchAdvance
    remoteHeadAtResolution = $remoteHeadAtResolution
    remoteAdvancedAfterSnapshot = $remoteAdvancedAfterSnapshot
    resolvedWorktreePath = $worktreePath
    actualHead = $actualHead
    searchedCandidateCount = $searchedCandidates.Count
    evidenceDirectory = $evidenceDirectory
    nextCommand = $nextCommand
    proofCeiling = 'Proves bounded canonical checkout discovery/acquisition and exact-head clean isolated worktree only; does not prove OpenCode, model, LSP configuration, or active language-server behavior.'
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM
@(
    '# OpenCode LSP checkout-resolution report',
    '',
    "- Status: $status",
    "- Preferred path: $PreferredPath",
    "- Source mode: $sourceMode",
    "- Source repo: $sourceRoot",
    "- Expected branch: $ExpectedBranch",
    "- Expected HEAD: $ExpectedHead",
    "- Remote HEAD at resolution: $remoteHeadAtResolution",
    "- Remote advanced after selected snapshot: $remoteAdvancedAfterSnapshot",
    "- Resolved worktree: $worktreePath",
    "- Actual HEAD: $actualHead",
    "- Failure: $failureCode $failureMessage",
    "- Receipt: $receiptPath",
    '',
    '## Next command',
    $nextCommand,
    '',
    '## Proof ceiling',
    [string]$result.proofCeiling
) | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM

if ($failureCode) { throw ([InvalidOperationException]::new("$failureCode|$failureMessage|receipt=$receiptPath")) }
Write-Host "RESOLVED_WORKTREE=$worktreePath"
Write-Host "RESOLUTION_RECEIPT=$receiptPath"
Write-Host "RESOLUTION_REPORT=$reportPath"
Write-Output ($result | ConvertTo-Json -Depth 6 -Compress)
