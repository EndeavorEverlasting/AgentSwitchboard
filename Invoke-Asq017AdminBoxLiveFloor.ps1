<#
.SYNOPSIS
  ASQ-017 Admin Box live-floor owner: ff-only main refresh → FM-WSL-12 one-shot.

.DESCRIPTION
  Graduates the recurring Admin Box paste formerly kept only as an ASQ-017 ledger
  snippet. Performs fail-closed git refresh (native LASTEXITCODE checks; capture
  rev-parse before Trim), then invokes Invoke-FmWsl12AdminBoxLiveProof.ps1.

  When launched via pwsh -File, this script propagates the child exit code with
  exit. Operators pasting at an interactive prompt should still wrap the call and
  throw on nonzero CHILD_EXIT_CODE rather than using interactive exit.

  -ContractOnly validates wiring without git mutation or live WSL and never claims
  LIVE PASS.
#>
[CmdletBinding()]
param(
    [string]$Remote = 'origin',
    [string]$Branch = 'main',
    [string]$WslDistribution = 'Ubuntu',
    [string]$FirstMatePath,
    [string]$EvidenceRoot,
    [switch]$SkipProtectedControl,
    [switch]$SkipGitRefresh,
    [switch]$ContractOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7+ (pwsh) is required for ASQ-017 Admin Box live floor.'
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$OneShotPath = Join-Path $Root 'Invoke-FmWsl12AdminBoxLiveProof.ps1'
if (-not (Test-Path -LiteralPath $OneShotPath -PathType Leaf)) {
    throw "Missing FM-WSL-12 Admin Box one-shot: $OneShotPath"
}

function Write-Asq017Status {
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Value)
    Write-Host ('{0}={1}' -f $Key, $Value)
}

if ($ContractOnly) {
    Write-Asq017Status -Key 'ASQ017_MODE' -Value 'ContractOnly'
    Write-Asq017Status -Key 'ASQ017_ONESHOT' -Value $OneShotPath
    Write-Asq017Status -Key 'ASQ017_GIT_REFRESH' -Value 'skipped'
    $contractArgs = @(
        '-NoLogo', '-NoProfile', '-File', $OneShotPath,
        '-WslDistribution', $WslDistribution,
        '-ContractOnly'
    )
    if (-not [string]::IsNullOrWhiteSpace($FirstMatePath)) {
        $contractArgs += @('-FirstMatePath', $FirstMatePath)
    }
    & pwsh @contractArgs
    if ($LASTEXITCODE -ne 0) {
        throw "ASQ-017 ContractOnly one-shot failed with exit $LASTEXITCODE"
    }
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'CONTRACT_PASS'
    Write-Asq017Status -Key 'LIVE_RUNTIME_PROOF' -Value 'UNPROVEN'
    Write-Asq017Status -Key 'PROOF_CEILING' -Value 'ContractOnly is not Admin Box live PASS'
    exit 0
}

Set-Location -LiteralPath $Root

if (-not $SkipGitRefresh) {
    Write-Asq017Status -Key 'ASQ017_GIT_REFRESH' -Value ("{0}/{1} ff-only" -f $Remote, $Branch)

    git fetch --all --prune --tags
    if ($LASTEXITCODE -ne 0) {
        throw "git fetch failed with exit $LASTEXITCODE"
    }

    git switch $Branch
    if ($LASTEXITCODE -ne 0) {
        throw "git switch failed with exit $LASTEXITCODE"
    }

    git pull --ff-only $Remote $Branch
    if ($LASTEXITCODE -ne 0) {
        throw "git pull failed with exit $LASTEXITCODE"
    }
}

$headRaw = git rev-parse HEAD
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to resolve HEAD'
}
$head = ("$headRaw").Trim()
if ([string]::IsNullOrWhiteSpace($head)) {
    throw 'Unable to resolve HEAD'
}
if ($head -notmatch '^[0-9a-fA-F]{40}$') {
    throw "HEAD must be a 40-character SHA. Received=$head"
}

Write-Asq017Status -Key 'PHYSICAL_FLOOR_HEAD' -Value $head
Write-Asq017Status -Key 'WSL_DISTRIBUTION' -Value $WslDistribution
Write-Asq017Status -Key 'ASQ017_ONESHOT' -Value $OneShotPath
Write-Asq017Status -Key 'LIVE_RUNTIME_PROOF' -Value 'UNPROVEN'

$argumentList = @(
    '-NoLogo', '-NoProfile', '-File', $OneShotPath,
    '-ExpectedHead', $head,
    '-WslDistribution', $WslDistribution
)
if (-not [string]::IsNullOrWhiteSpace($FirstMatePath)) {
    $argumentList += @('-FirstMatePath', $FirstMatePath)
    Write-Asq017Status -Key 'FIRSTMATE_PATH' -Value $FirstMatePath
}
if (-not [string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $argumentList += @('-EvidenceRoot', $EvidenceRoot)
}
if ($SkipProtectedControl) {
    $argumentList += '-SkipProtectedControl'
}

& pwsh @argumentList
$childExit = $LASTEXITCODE
Write-Asq017Status -Key 'CHILD_EXIT_CODE' -Value "$childExit"

if ($childExit -eq 44) {
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_MISSING_TOOLS'
    Write-Asq017Status -Key 'NEXT' -Value 'install allowlisted missing tools via printed NEXT_ACTION=/NEXT= (or clear apt/dpkg blocker after exhausted bounded repair), then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
    exit 44
}
if ($childExit -eq 45) {
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_GITHUB_AUTH'
    Write-Asq017Status -Key 'NEXT' -Value 'complete gh auth login then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
    exit 45
}
if ($childExit -eq 46) {
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_WINDOWS_WSL_REQUIRED'
    Write-Asq017Status -Key 'PROOF_LEVEL' -Value 'LIVE_ATTEMPT_FAIL_CLOSED'
    Write-Asq017Status -Key 'NEXT' -Value 'run on Windows Admin Box with wsl.exe and Ubuntu; cloud/Linux hosts cannot prove physical floor'
    exit 46
}
if ($childExit -eq 47) {
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_SUDO'
    Write-Asq017Status -Key 'NEXT' -Value 'enable passwordless sudo for apt-get in Ubuntu (sudo -n apt-get --version must succeed), then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
    exit 47
}
if ($childExit -eq 48) {
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_PRIMARY_HARNESS'
    Write-Asq017Status -Key 'NEXT' -Value 'install one primary harness on PATH inside Ubuntu visible to non-interactive bash -lc (claude|grok|pi|pi-signed|omp|codex|opencode|cursor-agent), then rerun'
    exit 48
}
if ($childExit -eq 49) {
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_FIRSTMATE_DIRTY'
    Write-Asq017Status -Key 'NEXT' -Value 'commit/stash/move dirty work in $HOME/firstmate (or the -FirstMatePath override), or remove $HOME/firstmate so bounded bootstrap can run, then rerun'
    exit 49
}
if ($childExit -eq 50) {
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_FIRSTMATE_PIN'
    Write-Asq017Status -Key 'NEXT' -Value 'in $HOME/firstmate (or -FirstMatePath) run: git fetch --all && git checkout b182d0f908b78d08c7ccb8dce3775bdca8c5d657, or remove that path / pass -FirstMatePath to a clean audited checkout, then rerun'
    exit 50
}
if ($childExit -ne 0) {
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'FAILED'
    Write-Asq017Status -Key 'NEXT' -Value 'inspect child console for NEXT=/NEXT_ACTION=; repair operator blocker; rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
    exit $childExit
}

Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'PHYSICAL_FLOOR_PASS'
Write-Asq017Status -Key 'LIVE_RUNTIME_PROOF' -Value 'OBSERVED_PHYSICAL_FLOOR_ONLY'
Write-Asq017Status -Key 'PROOF_CEILING' -Value 'Physical WSL interoperability floor only; no FirstMate crew dispatch claimed'
exit 0
