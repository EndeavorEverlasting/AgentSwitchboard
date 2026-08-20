[CmdletBinding()]
param(
    [string]$PreferredPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

$canonicalUrl = 'https://github.com/EndeavorEverlasting/AgentSwitchboard.git'
$resolverPath = Join-Path $PSScriptRoot 'Resolve-AgentSwitchboardCheckout.ps1'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'GIT_NOT_FOUND|Git is required to resolve the canonical AgentSwitchboard checkout.'
}
if (-not (Test-Path -LiteralPath $resolverPath -PathType Leaf)) {
    throw "CHECKOUT_RESOLVER_NOT_FOUND|Canonical checkout resolver is missing at $resolverPath"
}

$symrefLines = @(& git ls-remote --symref $canonicalUrl HEAD 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw 'DEFAULT_BRANCH_RESOLUTION_FAILED|Unable to resolve the canonical AgentSwitchboard default branch from GitHub.'
}
$defaultBranch = $null
foreach ($line in $symrefLines) {
    $match = [regex]::Match([string]$line, '^ref:\s+refs/heads/(?<branch>[^\s]+)\s+HEAD$')
    if ($match.Success) {
        $defaultBranch = $match.Groups['branch'].Value
        break
    }
}
if ([string]::IsNullOrWhiteSpace($defaultBranch)) {
    throw 'DEFAULT_BRANCH_NOT_FOUND|GitHub did not return a canonical default-branch symref for AgentSwitchboard.'
}

$headLines = @(& git ls-remote $canonicalUrl "refs/heads/$defaultBranch" 2>&1)
if ($LASTEXITCODE -ne 0 -or $headLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$headLines[0])) {
    throw 'DEFAULT_BRANCH_HEAD_RESOLUTION_FAILED|Unable to resolve the fresh canonical default-branch head.'
}
$expectedHead = (([string]$headLines[0]) -split '\s+')[0].Trim().ToLowerInvariant()
if ($expectedHead -notmatch '^[0-9a-f]{40}$') {
    throw 'DEFAULT_BRANCH_HEAD_INVALID|The resolved canonical default-branch head is not a full Git commit SHA.'
}

Write-Host "RECOVERY_DEFAULT_BRANCH=$defaultBranch"
Write-Host "RECOVERY_EXPECTED_HEAD=$expectedHead"
& $resolverPath -PreferredPath $PreferredPath -ExpectedBranch $defaultBranch -ExpectedHead $expectedHead
$code = $LASTEXITCODE
if ($code -ne 0) { exit $code }
exit 0
