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

    [ValidateRange(10, 300)]
    [int]$PrerequisiteTimeoutSeconds = 180,

    [switch]$SkipProtectedControl,
    [switch]$SkipGitRefresh,
    [string]$QuiescenceStatePath,
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
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_HARNESS_CONTRACT'
    Write-Host "ASQ017_RESULT=BLOCKED_HARNESS_CONTRACT"
    Write-Host "CHILD_EXIT_CODE=52"
    Write-Host "NEXT=restore Invoke-FmWsl12AdminBoxLiveProof.ps1 at checkout root ($OneShotPath), then rerun Invoke-Asq017AdminBoxLiveFloor.ps1"
    exit 52
}

$UpstreamPinPath = Join-Path $Root 'tooling\firstmate\harness\upstream-pin.json'
if (-not (Test-Path -LiteralPath $UpstreamPinPath -PathType Leaf)) {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_HARNESS_CONTRACT'
    Write-Host "ASQ017_RESULT=BLOCKED_HARNESS_CONTRACT"
    Write-Host "CHILD_EXIT_CODE=52"
    Write-Host "NEXT=restore tooling/firstmate/harness/upstream-pin.json ($UpstreamPinPath), then rerun Invoke-Asq017AdminBoxLiveFloor.ps1"
    exit 52
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

function Get-Asq017StatusFromText {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $matches = [regex]::Matches($Text, '(?m)^STATUS=(.+)$')
    if ($matches.Count -gt 0) {
        return $matches[$matches.Count - 1].Groups[1].Value.Trim()
    }
    return $null
}

function Write-Asq017Status {
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Value)
    Write-Host ('{0}={1}' -f $Key, $Value)
}

function Get-Asq017Sha256Text {
    param([Parameter(Mandatory)][string]$Text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([Convert]::ToHexString($sha.ComputeHash($bytes))).ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-Asq017PathIdentity {
    param(
        [AllowNull()][AllowEmptyString()][string]$PathValue,
        [Parameter(Mandatory)][string]$DefaultMarker
    )
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $DefaultMarker }
    $resolved = [System.IO.Path]::GetFullPath($PathValue)
    if ($IsWindows) { return $resolved.ToLowerInvariant() }
    return $resolved
}

function Get-Asq017WslEnvironmentSignature {
    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($null -eq $wsl) { return 'wsl=missing' }

    # The signature is a cheap capability discriminator, not a second physical proof.
    # A timeout/launch error is UNKNOWN so quiescence fails open to the real child.
    $probeTimeoutSeconds = [Math]::Max(3, [Math]::Min(15, $PrerequisiteTimeoutSeconds))
    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $wsl.Source
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        foreach ($argument in @('--distribution', $WslDistribution, '--exec', 'true')) {
            [void]$psi.ArgumentList.Add([string]$argument)
        }
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $psi
        if (-not $process.Start()) { return $null }
        $completed = $process.WaitForExit($probeTimeoutSeconds * 1000)
        if (-not $completed) {
            try {
                $process.Kill($true)
                [void]$process.WaitForExit(5000)
            }
            catch {}
            return $null
        }
        if ($process.ExitCode -eq 0) { return 'wsl=runnable' }
        return ('wsl=blocked;exit={0}' -f $process.ExitCode)
    }
    catch {
        return $null
    }
}

function Get-Asq017ProofRelevanceFingerprint {
    param([AllowNull()][AllowEmptyString()][string]$WslEnvironmentSignature)
    # HEAD itself is deliberately excluded. Only behavior/proof inputs belong here,
    # so documentation/ledger/tip-cite movement cannot reopen an unchanged proof.
    try {
        if ([string]::IsNullOrWhiteSpace($WslEnvironmentSignature)) { return $null }
        $relativePaths = @(
            'Invoke-Asq017AdminBoxLiveFloor.ps1',
            'Invoke-FmWsl12AdminBoxLiveProof.ps1',
            'Invoke-FirstMatePhysicalFloorContinuation.ps1',
            'Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1',
            'Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1',
            'tooling\firstmate\harness\integration-contract.json',
            'tooling\firstmate\harness\upstream-pin.json'
        )
        $entries = [System.Collections.Generic.List[string]]::new()
        foreach ($relativePath in $relativePaths) {
            $fullPath = Join-Path $Root $relativePath
            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return $null }
            $normalized = $relativePath.Replace('\', '/')
            $hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            [void]$entries.Add(('{0}={1}' -f $normalized, $hash))
        }
        [void]$entries.Add(('wslDistribution={0}' -f $WslDistribution))
        [void]$entries.Add(('wslEnvironmentSignature={0}' -f $WslEnvironmentSignature))
        [void]$entries.Add(('prerequisiteTimeoutSeconds={0}' -f $PrerequisiteTimeoutSeconds))
        [void]$entries.Add(('skipProtectedControl={0}' -f [bool]$SkipProtectedControl))
        $firstMateSelector = Get-Asq017PathIdentity -PathValue $FirstMatePath -DefaultMarker '<default>'
        [void]$entries.Add(('firstMatePathSelectorSha256={0}' -f (Get-Asq017Sha256Text -Text $firstMateSelector)))
        $evidenceSelector = Get-Asq017PathIdentity -PathValue $EvidenceRoot -DefaultMarker '<default>'
        [void]$entries.Add(('evidenceRootSelectorSha256={0}' -f (Get-Asq017Sha256Text -Text $evidenceSelector)))
        return Get-Asq017Sha256Text -Text ($entries -join "`n")
    }
    catch {
        # Unknown proof relevance must never become a false stop signal. Allow one
        # fresh bounded attempt and report the fingerprint as UNKNOWN instead.
        return $null
    }
}

function Get-Asq017QuiescenceStatePath {
    if (-not [string]::IsNullOrWhiteSpace($QuiescenceStatePath)) {
        return [System.IO.Path]::GetFullPath($QuiescenceStatePath)
    }
    $rootIdentity = [System.IO.Path]::GetFullPath($Root)
    if ($IsWindows) { $rootIdentity = $rootIdentity.ToLowerInvariant() }
    $rootKey = (Get-Asq017Sha256Text -Text $rootIdentity).Substring(0, 16)
    $directory = Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard\quiescence'
    return Join-Path $directory ("fm-wsl12-asq017-$rootKey.json")
}

function Read-Asq017QuiescenceState {
    try {
        $path = Get-Asq017QuiescenceStatePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
        $state = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ([string]$state.schema -ne 'asb-quiescence-state/v1') { return $null }
        if ([string]$state.lane -ne 'FM-WSL-12') { return $null }
        return $state
    }
    catch {
        # Corrupt/foreign/unresolvable local state cannot be trusted as a stop signal;
        # fail open to a fresh bounded proof attempt instead of manufacturing quiescence.
        return $null
    }
}

function Write-Asq017QuiescenceState {
    param(
        [Parameter(Mandatory)][string]$BlockerStatus,
        [Parameter(Mandatory)][string]$Fingerprint,
        [Parameter(Mandatory)][string]$ObservedHead
    )
    try {
        $path = Get-Asq017QuiescenceStatePath
        $parent = Split-Path -Parent $path
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
        $state = [ordered]@{
            schema = 'asb-quiescence-state/v1'
            lane = 'FM-WSL-12'
            blockerStatus = $BlockerStatus
            proofRelevanceFingerprint = $Fingerprint
            observedHead = $ObservedHead
            observedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
        }
        $tempPath = Join-Path $parent ('.' + [System.IO.Path]::GetFileName($path) + '.' + [guid]::NewGuid().ToString('n') + '.tmp')
        try {
            $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $tempPath -Encoding utf8
            # Same-directory replace prevents readers from observing a truncated JSON file.
            [System.IO.File]::Move($tempPath, $path, $true)
        }
        finally {
            if (Test-Path -LiteralPath $tempPath -PathType Leaf) {
                Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Asq017Status -Key 'QUIESCENCE_STATE' -Value 'recorded'
        return $true
    }
    catch {
        # The cache is advisory. Persistence failure must not replace the real
        # runtime blocker or fabricate a successful quiescence observation.
        Write-Asq017Status -Key 'QUIESCENCE_STATE' -Value 'unavailable'
        Write-Asq017Status -Key 'QUIESCENCE_STATE_OPERATION' -Value 'write'
        return $false
    }
}

function Clear-Asq017QuiescenceState {
    try {
        $path = Get-Asq017QuiescenceStatePath
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
        }
    }
    catch {
        # Stale cache cleanup is also advisory. The current child result remains
        # authoritative; a cleanup problem cannot replace it.
        Write-Asq017Status -Key 'QUIESCENCE_STATE' -Value 'unavailable'
        Write-Asq017Status -Key 'QUIESCENCE_STATE_OPERATION' -Value 'clear'
    }
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
        '-PrerequisiteTimeoutSeconds', "$PrerequisiteTimeoutSeconds",
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

$wslEnvironmentSignature = Get-Asq017WslEnvironmentSignature
if ([string]::IsNullOrWhiteSpace($wslEnvironmentSignature)) {
    Write-Asq017Status -Key 'WSL_ENVIRONMENT_SIGNATURE' -Value 'UNKNOWN'
}
else {
    Write-Asq017Status -Key 'WSL_ENVIRONMENT_SIGNATURE' -Value $wslEnvironmentSignature
}
$proofRelevanceFingerprint = Get-Asq017ProofRelevanceFingerprint -WslEnvironmentSignature $wslEnvironmentSignature
if ([string]::IsNullOrWhiteSpace($proofRelevanceFingerprint)) {
    Write-Asq017Status -Key 'PROOF_RELEVANCE_FINGERPRINT' -Value 'UNKNOWN'
}
else {
    Write-Asq017Status -Key 'PROOF_RELEVANCE_FINGERPRINT' -Value $proofRelevanceFingerprint
}

# Runtime circuit breaker: a second identical environment blocker is not a new
# evidence pass. The environment signature lets an installed/repaired WSL floor
# change the fingerprint and reopen the real child; UNKNOWN always fails open.
if (-not [string]::IsNullOrWhiteSpace($proofRelevanceFingerprint)) {
    $priorQuiescence = Read-Asq017QuiescenceState
    if ($null -ne $priorQuiescence -and
        [string]$priorQuiescence.blockerStatus -eq 'BLOCKED_WINDOWS_WSL_REQUIRED' -and
        [string]$priorQuiescence.proofRelevanceFingerprint -eq $proofRelevanceFingerprint) {
        Write-Host 'STATUS=QUIESCENT_BLOCKED'
        Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'QUIESCENT_BLOCKED'
        Write-Asq017Status -Key 'BLOCKER_STATUS' -Value 'BLOCKED_WINDOWS_WSL_REQUIRED'
        Write-Asq017Status -Key 'PROGRESS_BEARING' -Value 'false'
        Write-Asq017Status -Key 'RETRY_ELIGIBLE' -Value 'false'
        Write-Asq017Status -Key 'QUIESCENCE_REASON' -Value 'REPEATED_UNCHANGED_EXTERNAL_BLOCKER'
        Write-Asq017Status -Key 'PROOF_LEVEL' -Value 'LIVE_ATTEMPT_FAIL_CLOSED'
        Write-Asq017Status -Key 'LIVE_RUNTIME_PROOF' -Value 'UNPROVEN'
        Write-Asq017Status -Key 'CHILD_EXIT_CODE' -Value '46'
        Write-Asq017Status -Key 'NEXT' -Value 'run on a Windows Admin Box with wsl.exe+Ubuntu, or change a proof-relevant runtime input; do not rerun this cloud/non-Windows proof or create citation-only/tip-cite updates while the fingerprint is unchanged'
        exit 46
    }
}

$argumentList = @(
    '-NoLogo', '-NoProfile', '-File', $OneShotPath,
    '-ExpectedHead', $head,
    '-WslDistribution', $WslDistribution,
    '-PrerequisiteTimeoutSeconds', "$PrerequisiteTimeoutSeconds"
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
# Use ProcessStartInfo.ArgumentList (not Start-Process -ArgumentList). PowerShell's
# Start-Process flattens ArgumentList into one command line without quoting, so an
# Admin Box checkout under a spaced path (for example OneDrive) splits -File and
# yields pwsh usage exit 64 before the oneshot can run.
$pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
if ($null -eq $pwshCommand) {
    Write-Host 'STATUS=BLOCKED_HARNESS_START'
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_HARNESS_START'
    Write-Host 'NEXT=install PowerShell 7+ (pwsh) on PATH, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1; unable to resolve pwsh'
    exit 1
}
$oneshotPsi = [System.Diagnostics.ProcessStartInfo]::new()
$oneshotPsi.FileName = $pwshCommand.Source
$oneshotPsi.WorkingDirectory = $Root
$oneshotPsi.UseShellExecute = $false
$oneshotPsi.CreateNoWindow = $true
$oneshotPsi.RedirectStandardOutput = $true
$oneshotPsi.RedirectStandardError = $true
foreach ($argument in $argumentList) {
    [void]$oneshotPsi.ArgumentList.Add([string]$argument)
}
$oneshotProcess = [System.Diagnostics.Process]::new()
$oneshotProcess.StartInfo = $oneshotPsi
# Keep structured — do not throw (throw collapses to unstructured exit 1).
try {
    if (-not $oneshotProcess.Start()) {
        Write-Host 'STATUS=BLOCKED_HARNESS_START'
        Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_HARNESS_START'
        Write-Host 'NEXT=ensure pwsh can launch Invoke-FmWsl12AdminBoxLiveProof.ps1 on this host, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1; unable to start oneshot process'
        exit 1
    }
}
catch {
    Write-Host 'STATUS=BLOCKED_HARNESS_START'
    Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'BLOCKED_HARNESS_START'
    Write-Host 'NEXT=ensure pwsh can launch Invoke-FmWsl12AdminBoxLiveProof.ps1 on this host, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1; unable to start oneshot process'
    Write-Host ("HARNESS_START_ERROR={0}" -f $_.Exception.Message)
    exit 1
}
$oneshotStdoutTask = $oneshotProcess.StandardOutput.ReadToEndAsync()
$oneshotStderrTask = $oneshotProcess.StandardError.ReadToEndAsync()
$oneshotProcess.WaitForExit()
$oneshotStdoutText = $oneshotStdoutTask.GetAwaiter().GetResult()
$oneshotStderrText = $oneshotStderrTask.GetAwaiter().GetResult()
Set-Content -LiteralPath $oneshotStdoutPath -Value $oneshotStdoutText -Encoding utf8
Set-Content -LiteralPath $oneshotStderrPath -Value $oneshotStderrText -Encoding utf8
if (Test-Path -LiteralPath $oneshotStdoutPath -PathType Leaf) {
    Get-Content -LiteralPath $oneshotStdoutPath | ForEach-Object { Write-Host $_ }
}
if (Test-Path -LiteralPath $oneshotStderrPath -PathType Leaf) {
    Get-Content -LiteralPath $oneshotStderrPath | ForEach-Object { [Console]::Error.WriteLine($_) }
}
$childExit = [int]$oneshotProcess.ExitCode
Write-Asq017Status -Key 'CHILD_EXIT_CODE' -Value "$childExit"

if ($childExit -eq 46 -and -not [string]::IsNullOrWhiteSpace($proofRelevanceFingerprint)) {
    $quiescenceRecorded = Write-Asq017QuiescenceState -BlockerStatus 'BLOCKED_WINDOWS_WSL_REQUIRED' -Fingerprint $proofRelevanceFingerprint -ObservedHead $head
    Write-Asq017Status -Key 'QUIESCENCE_ON_REPEAT' -Value $(if ($quiescenceRecorded) { 'true' } else { 'false' })
}
else {
    # The old environment blocker is no longer the current outcome. Clear it so a
    # changed environment/behavior is never suppressed by stale local state.
    Clear-Asq017QuiescenceState
}

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
    Write-Asq017Blocker -Result 'BLOCKED_GITHUB_AUTH' -ExitCode 45 -FallbackNext 'export PATH="$HOME/.local/bin:$PATH"; gh auth login --hostname github.com --git-protocol https --web inside Ubuntu, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
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
    Write-Asq017Blocker -Result 'BLOCKED_FIRSTMATE_PIN' -ExitCode 50 -FallbackNext 'follow the child NEXT= recovery above; if no child NEXT= is available, verify local FirstMate object integrity first; if the audited commit is healthy but a required path is absent, repair tooling/firstmate/harness/integration-contract.json and tooling/firstmate/harness/upstream-pin.json (or refresh the audited pin); do not retry the same SHA blindly; then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
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
    # Prefer child STATUS=BLOCKED_* (e.g. BLOCKED_CONTINUATION_EXHAUSTED) over generic FAILED.
    $preservedStatus = Get-Asq017StatusFromText -Text $oneshotBlob
    if (-not [string]::IsNullOrWhiteSpace($preservedStatus) -and $preservedStatus -match '^BLOCKED_') {
        Write-Asq017Blocker -Result $preservedStatus -ExitCode $childExit -FallbackNext 'inspect child console for NEXT=/NEXT_ACTION=; repair operator blocker; rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
    }
    Write-Asq017Blocker -Result 'FAILED' -ExitCode $childExit -FallbackNext 'inspect child console for NEXT=/NEXT_ACTION=; repair operator blocker; rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
}

Write-Asq017Status -Key 'ASQ017_RESULT' -Value 'PHYSICAL_FLOOR_PASS'
Write-Asq017Status -Key 'LIVE_RUNTIME_PROOF' -Value 'OBSERVED_PHYSICAL_FLOOR_ONLY'
Write-Asq017Status -Key 'PROOF_CEILING' -Value 'Physical WSL interoperability floor only; no FirstMate crew dispatch claimed'
exit 0
