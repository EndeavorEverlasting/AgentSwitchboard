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

$UpstreamPinPath = Join-Path $Root 'tooling\firstmate\harness\upstream-pin.json'
if (-not (Test-Path -LiteralPath $UpstreamPinPath -PathType Leaf)) {
    throw "Missing FirstMate upstream pin: $UpstreamPinPath"
}

function Get-Asq017ExpectedFirstMateHead {
    $upstreamPin = Get-Content -LiteralPath $UpstreamPinPath -Raw | ConvertFrom-Json
    $head = [string]$upstreamPin.commit
    if ($head -notmatch '^[0-9a-f]{40}$') {
        # Keep structured — do not throw (throw collapses to unstructured exit 1).
        Write-Host 'STATUS=BLOCKED_FIRSTMATE_PIN'
        Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_FIRSTMATE_PIN'
        Write-Host "NEXT=repair tooling/firstmate/harness/upstream-pin.json so commit is a 40-character lowercase hex SHA; Received=$head"
        exit 50
    }
    return $head
}

function Get-Asq017OperatorNextFromText {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $matches = [regex]::Matches($Text, '(?m)^NEXT=(.+)$')
    if ($matches.Count -gt 0) {
        return $matches[$matches.Count - 1].Groups[1].Value.Trim()
    }
    return $null
}

function Write-Asq017Status {
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Value)
    Write-Host ('{0}={1}' -f $Key, $Value)
}

function Write-Asq017GitRefreshBlocker {
    param(
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][int]$GitExitCode
    )
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_GIT_REFRESH'
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_GIT_REFRESH'
    Write-Asq017Status -Key 'GIT_OPERATION' -Value $Operation
    Write-Asq017Status -Key 'GIT_EXIT_CODE' -Value "$GitExitCode"
    Write-Host 'NEXT=commit/stash/move unrelated local changes (or use a clean worktree), then rerun Invoke-Asq017AdminBoxLiveFloor.ps1; use -SkipGitRefresh only when already on the intended tip'
    Write-Host ("git {0} failed with exit {1}" -f $Operation, $GitExitCode)
    exit 1
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
        # Keep structured — do not throw (throw collapses to unstructured exit 1).
        $contractExit = [int]$LASTEXITCODE
        Write-Host 'STATUS=CONTRACT_FAIL'
        Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'CONTRACT_FAIL'
        Write-Asq017Status -Key 'CHILD_EXIT_CODE' -Value "$contractExit"
        Write-Asq017Status -Key 'NEXT' -Value 'inspect ContractOnly oneshot console; repair wiring/contract surfaces, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1 -ContractOnly'
        Write-Asq017Status -Key 'PROOF_CEILING' -Value 'ContractOnly is not Admin Box live PASS'
        exit $contractExit
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
        Write-Asq017GitRefreshBlocker -Operation 'fetch' -GitExitCode $LASTEXITCODE
    }

    git switch $Branch
    if ($LASTEXITCODE -ne 0) {
        Write-Asq017GitRefreshBlocker -Operation 'switch' -GitExitCode $LASTEXITCODE
    }

    git pull --ff-only $Remote $Branch
    if ($LASTEXITCODE -ne 0) {
        Write-Asq017GitRefreshBlocker -Operation 'pull' -GitExitCode $LASTEXITCODE
    }
}

# Reload pin after ff-only refresh so exit-50 NEXT matches tip upstream-pin.json
$expectedFirstMateHead = Get-Asq017ExpectedFirstMateHead

$headRaw = git rev-parse HEAD
if ($LASTEXITCODE -ne 0) {
    Write-Host 'STATUS=BLOCKED_GIT_HEAD'
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_GIT_HEAD'
    Write-Host 'NEXT=repair the AgentSwitchboard checkout so git rev-parse HEAD succeeds, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
    Write-Host 'Unable to resolve HEAD'
    exit 1
}
$head = ("$headRaw").Trim()
if ([string]::IsNullOrWhiteSpace($head)) {
    Write-Host 'STATUS=BLOCKED_GIT_HEAD'
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_GIT_HEAD'
    Write-Host 'NEXT=repair the AgentSwitchboard checkout so git rev-parse HEAD returns a non-empty SHA, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
    Write-Host 'Unable to resolve HEAD'
    exit 1
}
if ($head -notmatch '^[0-9a-fA-F]{40}$') {
    Write-Host 'STATUS=BLOCKED_GIT_HEAD'
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_GIT_HEAD'
    Write-Host 'NEXT=repair the AgentSwitchboard checkout so HEAD is a 40-character SHA, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
    Write-Host ("HEAD must be a 40-character SHA. Received={0}" -f $head)
    exit 1
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

$oneshotStdoutPath = Join-Path ([System.IO.Path]::GetTempPath()) ('asq017-oneshot-stdout-' + [guid]::NewGuid().ToString('n') + '.log')
$oneshotStderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ('asq017-oneshot-stderr-' + [guid]::NewGuid().ToString('n') + '.log')
# Keep structured — do not throw (throw collapses to unstructured exit 1).
try {
    $oneshotProcess = Start-Process -FilePath 'pwsh' -ArgumentList $argumentList -NoNewWindow -Wait -PassThru -RedirectStandardOutput $oneshotStdoutPath -RedirectStandardError $oneshotStderrPath -ErrorAction Stop
}
catch {
    Write-Host 'STATUS=BLOCKED_HARNESS_START'
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_HARNESS_START'
    Write-Host 'NEXT=ensure pwsh can launch Invoke-FmWsl12AdminBoxLiveProof.ps1 on this host, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1; unable to start oneshot process'
    Write-Host ("HARNESS_START_ERROR={0}" -f $_.Exception.Message)
    exit 1
}
if ($null -eq $oneshotProcess) {
    Write-Host 'STATUS=BLOCKED_HARNESS_START'
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_HARNESS_START'
    Write-Host 'NEXT=ensure pwsh can launch Invoke-FmWsl12AdminBoxLiveProof.ps1 on this host, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1; oneshot Start-Process returned no process object'
    exit 1
}
if (Test-Path -LiteralPath $oneshotStdoutPath -PathType Leaf) {
    Get-Content -LiteralPath $oneshotStdoutPath | ForEach-Object { Write-Host $_ }
}
if (Test-Path -LiteralPath $oneshotStderrPath -PathType Leaf) {
    Get-Content -LiteralPath $oneshotStderrPath | ForEach-Object { [Console]::Error.WriteLine($_) }
}
$childExit = [int]$oneshotProcess.ExitCode
Write-Asq017Status -Key 'CHILD_EXIT_CODE' -Value "$childExit"

$oneshotBlob = ''
foreach ($path in @($oneshotStdoutPath, $oneshotStderrPath)) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $oneshotBlob += "`n" + (Get-Content -LiteralPath $path -Raw)
    }
}
# Prefer child NEXT= (includes -FirstMatePath-specific guidance) over parent fallbacks.
$preservedNext = Get-Asq017OperatorNextFromText -Text $oneshotBlob

function Write-Asq017Blocker {
    param(
        [Parameter(Mandatory)][string]$Result,
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string]$FallbackNext,
        [string]$ProofLevel
    )
    # Emit STATUS= so parent-mapped exits stay greppable even when child stdout is empty.
    Write-Host ("STATUS={0}" -f $Result)
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value $Result
    if (-not [string]::IsNullOrWhiteSpace($ProofLevel)) {
        Write-Asq017Status -Key 'PROOF_LEVEL' -Value $ProofLevel
    }
    if (-not [string]::IsNullOrWhiteSpace($preservedNext)) {
        Write-Asq017Status -Key 'NEXT' -Value $preservedNext
    } else {
        Write-Asq017Status -Key 'NEXT' -Value $FallbackNext
    }
    exit $ExitCode
}

if ($childExit -eq 44) {
    Write-Asq017Blocker -Result 'BLOCKED_MISSING_TOOLS' -ExitCode 44 -FallbackNext 'install allowlisted missing tools via printed NEXT_ACTION=/NEXT= (or clear apt/dpkg blocker after exhausted bounded repair), then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
}
if ($childExit -eq 45) {
    Write-Asq017Blocker -Result 'BLOCKED_GITHUB_AUTH' -ExitCode 45 -FallbackNext 'complete gh auth login then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
}
if ($childExit -eq 46) {
    Write-Asq017Blocker -Result 'BLOCKED_WINDOWS_WSL_REQUIRED' -ExitCode 46 -FallbackNext 'run on Windows Admin Box with wsl.exe and Ubuntu; cloud/Linux hosts cannot prove physical floor' -ProofLevel 'LIVE_ATTEMPT_FAIL_CLOSED'
}
if ($childExit -eq 47) {
    Write-Asq017Blocker -Result 'BLOCKED_SUDO' -ExitCode 47 -FallbackNext 'enable passwordless sudo for apt-get in Ubuntu (sudo -n apt-get --version must succeed), then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
}
if ($childExit -eq 48) {
    Write-Asq017Blocker -Result 'BLOCKED_PRIMARY_HARNESS' -ExitCode 48 -FallbackNext 'install one primary harness on PATH inside Ubuntu visible to non-interactive bash -lc (claude|grok|pi|pi-signed|omp|codex|opencode|cursor-agent), then rerun'
}
if ($childExit -eq 49) {
    Write-Asq017Blocker -Result 'BLOCKED_FIRSTMATE_DIRTY' -ExitCode 49 -FallbackNext 'commit/stash/move dirty work in $HOME/firstmate (or the -FirstMatePath override), or remove $HOME/firstmate so bounded bootstrap can run, then rerun'
}
if ($childExit -eq 50) {
    Write-Asq017Blocker -Result 'BLOCKED_FIRSTMATE_PIN' -ExitCode 50 -FallbackNext ('in $HOME/firstmate (or -FirstMatePath) run: git fetch --all && git checkout {0}, or remove that path / pass -FirstMatePath to a clean audited checkout, then rerun' -f $expectedFirstMateHead)
}
if ($childExit -eq 51) {
    Write-Asq017Blocker -Result 'BLOCKED_WSL_BOOTSTRAP' -ExitCode 51 -FallbackNext 'inspect WSL diagnostics/bootstrap stdout; repair exact-head WSL clone/source-repo access, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
}
if ($childExit -eq 52) {
    Write-Asq017Blocker -Result 'BLOCKED_HARNESS_CONTRACT' -ExitCode 52 -FallbackNext 'inspect evidence root; repair FirstMate harness contract failure inside Ubuntu, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
}
if ($childExit -eq 124) {
    # Keep hang/timeout exits structured — do not collapse to generic FAILED.
    Write-Asq017Blocker -Result 'BLOCKED_PREREQUISITE_TIMEOUT' -ExitCode 124 -FallbackNext 'repair hung WSL/sudo/apt prerequisite or increase host capacity, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1; a prerequisite step timed out'
}
if ($childExit -ne 0) {
    Write-Asq017Blocker -Result 'FAILED' -ExitCode $childExit -FallbackNext 'inspect child console for NEXT=/NEXT_ACTION=; repair operator blocker; rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
}

Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'PHYSICAL_FLOOR_PASS'
Write-Asq017Status -Key 'LIVE_RUNTIME_PROOF' -Value 'OBSERVED_PHYSICAL_FLOOR_ONLY'
Write-Asq017Status -Key 'PROOF_CEILING' -Value 'Physical WSL interoperability floor only; no FirstMate crew dispatch claimed'
exit 0
