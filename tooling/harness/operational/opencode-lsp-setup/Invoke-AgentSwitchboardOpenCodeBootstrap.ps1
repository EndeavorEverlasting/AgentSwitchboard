[CmdletBinding()]
param(
    [ValidateSet('Recover','ResolveOnly')][string]$Mode = 'Recover',
    [string]$ModelId = 'opencode/nemotron-3-ultra-free',
    [string]$Distribution = 'Ubuntu',
    [ValidateRange(30, 900)][int]$InstallTimeoutSeconds = 180
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

$repository = 'EndeavorEverlasting/AgentSwitchboard'
$canonicalUrl = 'https://github.com/EndeavorEverlasting/AgentSwitchboard.git'
$canonicalOriginPattern = '^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/|git://github\.com/)EndeavorEverlasting/AgentSwitchboard(?:\.git)?/?$'
$rawBase = 'https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard'
$relativeRoot = 'tooling/harness/operational/opencode-lsp-setup'
$callerLocation = [string](Get-Location).Path
$runId = '{0}-{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')), ([guid]::NewGuid().ToString('N').Substring(0,8))
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) "AgentSwitchboard-bootstrap-$runId"
$finalExitCode = 1

function Stop-Bootstrap {
    param([Parameter(Mandatory)][string]$Code, [Parameter(Mandatory)][string]$Message)
    throw ([InvalidOperationException]::new("$Code|$Message"))
}

function Invoke-GitLines {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $lines = @(& git @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        Stop-Bootstrap 'BOOTSTRAP_GIT_FAILED' "git $($Arguments -join ' ') failed while resolving canonical repository state."
    }
    return $lines
}

try {
    if ($env:OS -ne 'Windows_NT') {
        Stop-Bootstrap 'BOOTSTRAP_WINDOWS_REQUIRED' 'The AgentSwitchboard OpenCode recovery bootstrap is Windows-only.'
    }
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Stop-Bootstrap 'BOOTSTRAP_POWERSHELL7_REQUIRED' 'The AgentSwitchboard OpenCode recovery bootstrap requires PowerShell 7.'
    }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Stop-Bootstrap 'BOOTSTRAP_LOCALAPPDATA_REQUIRED' 'LOCALAPPDATA is required for canonical AgentSwitchboard checkout and evidence state.'
    }
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Stop-Bootstrap 'BOOTSTRAP_GIT_NOT_FOUND' 'Git is required to resolve or acquire AgentSwitchboard from any working directory.'
    }

    $symrefLines = Invoke-GitLines -Arguments @('ls-remote','--symref',$canonicalUrl,'HEAD')
    $defaultBranch = $null
    foreach ($line in $symrefLines) {
        $match = [regex]::Match([string]$line, '^ref:\s+refs/heads/(?<branch>[^\s]+)\s+HEAD$')
        if ($match.Success) {
            $defaultBranch = $match.Groups['branch'].Value
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($defaultBranch)) {
        Stop-Bootstrap 'BOOTSTRAP_DEFAULT_BRANCH_NOT_FOUND' 'GitHub did not return the AgentSwitchboard default-branch symref.'
    }

    $headLines = Invoke-GitLines -Arguments @('ls-remote',$canonicalUrl,"refs/heads/$defaultBranch")
    if ($headLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$headLines[0])) {
        Stop-Bootstrap 'BOOTSTRAP_DEFAULT_HEAD_NOT_FOUND' 'GitHub did not return the current AgentSwitchboard default-branch head.'
    }
    $expectedHead = (([string]$headLines[0]) -split '\s+')[0].Trim().ToLowerInvariant()
    if ($expectedHead -notmatch '^[0-9a-f]{40}$') {
        Stop-Bootstrap 'BOOTSTRAP_DEFAULT_HEAD_INVALID' 'The resolved AgentSwitchboard default-branch head was not a full commit SHA.'
    }

    $null = New-Item -ItemType Directory -Path $stageRoot -Force
    $stagedFiles = @(
        'Recover-AgentSwitchboardCheckout.ps1',
        'Resolve-AgentSwitchboardCheckout.ps1'
    )
    foreach ($name in $stagedFiles) {
        $uri = "$rawBase/$expectedHead/$relativeRoot/$name"
        $destination = Join-Path $stageRoot $name
        try {
            Invoke-WebRequest -Uri $uri -OutFile $destination -UseBasicParsing -ErrorAction Stop
        }
        catch {
            Stop-Bootstrap 'BOOTSTRAP_STAGE_DOWNLOAD_FAILED' "Unable to stage $name from exact AgentSwitchboard head $expectedHead."
        }
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            Stop-Bootstrap 'BOOTSTRAP_STAGE_FILE_MISSING' "Exact-head bootstrap staging did not create $name."
        }
    }

    $checkoutRouter = Join-Path $stageRoot 'Recover-AgentSwitchboardCheckout.ps1'
    Write-Host "BOOTSTRAP_CALLER_LOCATION=$callerLocation"
    Write-Host "BOOTSTRAP_DEFAULT_BRANCH=$defaultBranch"
    Write-Host "BOOTSTRAP_EXPECTED_HEAD=$expectedHead"

    $resolutionLine = & pwsh -NoLogo -NoProfile -File $checkoutRouter | Select-Object -Last 1
    $resolutionExit = $LASTEXITCODE
    if ($resolutionExit -ne 0) {
        Stop-Bootstrap 'BOOTSTRAP_CHECKOUT_RECOVERY_FAILED' "Exact-head checkout recovery returned exit code $resolutionExit."
    }
    if ([string]::IsNullOrWhiteSpace([string]$resolutionLine)) {
        Stop-Bootstrap 'BOOTSTRAP_CHECKOUT_RECEIPT_EMPTY' 'Checkout recovery returned no machine-readable resolution object.'
    }

    try { $resolution = ([string]$resolutionLine) | ConvertFrom-Json -ErrorAction Stop }
    catch { Stop-Bootstrap 'BOOTSTRAP_CHECKOUT_RECEIPT_INVALID' 'Checkout recovery returned an invalid machine-readable resolution object.' }
    $resolved = [string]$resolution.resolvedWorktreePath
    if ([string]::IsNullOrWhiteSpace($resolved) -or -not (Test-Path -LiteralPath $resolved -PathType Container)) {
        Stop-Bootstrap 'BOOTSTRAP_RESOLVED_ROOT_MISSING' 'Checkout recovery did not return a reachable AgentSwitchboard worktree.'
    }

    $rootLines = @(& git -C $resolved rev-parse --show-toplevel 2>&1)
    if ($LASTEXITCODE -ne 0 -or $rootLines.Count -eq 0) {
        Stop-Bootstrap 'BOOTSTRAP_ROOT_VERIFICATION_FAILED' 'Resolved worktree failed git rev-parse --show-toplevel.'
    }
    $verifiedRoot = ([string]$rootLines[0]).Trim()
    $originLines = @(& git -C $verifiedRoot remote get-url origin 2>&1)
    if ($LASTEXITCODE -ne 0 -or $originLines.Count -eq 0) {
        Stop-Bootstrap 'BOOTSTRAP_ORIGIN_VERIFICATION_FAILED' 'Resolved worktree did not expose an origin remote.'
    }
    $origin = ([string]$originLines[0]).Trim()
    if ($origin -notmatch $canonicalOriginPattern) {
        Stop-Bootstrap 'BOOTSTRAP_WRONG_REPOSITORY' "Resolved worktree origin is not $repository."
    }
    $actualHeadLines = @(& git -C $verifiedRoot rev-parse HEAD 2>&1)
    if ($LASTEXITCODE -ne 0 -or $actualHeadLines.Count -eq 0) {
        Stop-Bootstrap 'BOOTSTRAP_HEAD_VERIFICATION_FAILED' 'Resolved AgentSwitchboard worktree HEAD could not be read.'
    }
    $actualHead = ([string]$actualHeadLines[0]).Trim().ToLowerInvariant()
    if ($actualHead -ne $expectedHead) {
        Stop-Bootstrap 'BOOTSTRAP_HEAD_MISMATCH' "Resolved AgentSwitchboard worktree is at $actualHead, not current default head $expectedHead."
    }
    $dirtyLines = @(& git -C $verifiedRoot status --porcelain=v1 2>&1)
    if ($LASTEXITCODE -ne 0 -or $dirtyLines.Count -gt 0) {
        Stop-Bootstrap 'BOOTSTRAP_WORKTREE_NOT_CLEAN' 'Resolved exact-head AgentSwitchboard worktree is not clean; it was preserved and not rewritten.'
    }

    Set-Location -LiteralPath $verifiedRoot
    Write-Host "BOOTSTRAP_RESOLVED_ROOT=$verifiedRoot"
    Write-Host "BOOTSTRAP_VERIFIED_ORIGIN=$origin"
    Write-Host "BOOTSTRAP_VERIFIED_HEAD=$actualHead"
    Write-Host "BOOTSTRAP_ACTIVE_LOCATION=$([string](Get-Location).Path)"

    if ($Mode -eq 'ResolveOnly') {
        $finalExitCode = 0
    }
    else {
        $runtimeRecovery = Join-Path $verifiedRoot "$relativeRoot/Recover-OpenCodeRuntime.ps1"
        if (-not (Test-Path -LiteralPath $runtimeRecovery -PathType Leaf)) {
            Stop-Bootstrap 'BOOTSTRAP_RUNTIME_ROUTER_MISSING' 'The verified exact-head worktree is missing Recover-OpenCodeRuntime.ps1.'
        }
        & pwsh -NoLogo -NoProfile -File $runtimeRecovery -RepoPath $verifiedRoot -ModelId $ModelId -Distribution $Distribution -InstallTimeoutSeconds $InstallTimeoutSeconds
        $finalExitCode = $LASTEXITCODE
    }
}
catch {
    $raw = [string]$_.Exception.Message
    if ($raw -match '^([A-Z0-9_]+)\|(.*)$') {
        Write-Host "BOOTSTRAP_FAILURE_CODE=$($Matches[1])"
        Write-Host "BOOTSTRAP_FAILURE_MESSAGE=$($Matches[2])"
    }
    else {
        Write-Host 'BOOTSTRAP_FAILURE_CODE=BOOTSTRAP_UNEXPECTED_FAILURE'
        Write-Host 'BOOTSTRAP_FAILURE_MESSAGE=The cwd-independent AgentSwitchboard bootstrap failed before dispatch.'
    }
    $finalExitCode = 1
}
finally {
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

exit $finalExitCode
