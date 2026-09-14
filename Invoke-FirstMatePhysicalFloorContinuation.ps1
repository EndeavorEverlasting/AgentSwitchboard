<#
.SYNOPSIS
  FM-WSL-12 execution-owner continuation: bounded Ubuntu package repair then rerun.

.DESCRIPTION
  Runs the non-installing physical-floor gate. When the gate reports
  STATUS=BLOCKED_MISSING_TOOLS, executes only the exact allowlisted apt-get
  NEXT_ACTION inside the contract Ubuntu distribution, then reruns the gate.
  Stops without another permission round-trip for package repair.

  Does not mutate credentials. STATUS=BLOCKED_GITHUB_AUTH remains an operator
  credential gate. The physical-floor harness itself stays fail-closed and
  non-installing; this entrypoint is the authorized execution-owner loop.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$ExpectedHead,

    [string]$SourceRepositoryPath,
    [string]$FirstMatePath,
    [string]$EvidenceRoot,
    [string]$WslDistribution = 'Ubuntu',

    [ValidateRange(1, 3)]
    [int]$MaxPackageRepairAttempts = 2,

    [ValidateRange(10, 300)]
    [int]$PrerequisiteTimeoutSeconds = 60,

    [switch]$ContractOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7+ (pwsh) is required for FM-WSL-12 physical-floor continuation.'
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PhysicalFloorPath = Join-Path $Root 'Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1'
$IntegrationContractPath = Join-Path $Root 'tooling\firstmate\harness\integration-contract.json'

if (-not (Test-Path -LiteralPath $PhysicalFloorPath -PathType Leaf)) {
    throw "Missing physical-floor entrypoint: $PhysicalFloorPath"
}
if (-not (Test-Path -LiteralPath $IntegrationContractPath -PathType Leaf)) {
    throw "Missing integration contract: $IntegrationContractPath"
}

$integration = Get-Content -LiteralPath $IntegrationContractPath -Raw | ConvertFrom-Json
$recovery = $integration.physical_floor_recovery
if ($null -eq $recovery) {
    throw 'integration-contract.json missing physical_floor_recovery.'
}
if ([string]$recovery.lane -ne 'FM-WSL-12') {
    throw "Unexpected physical_floor_recovery.lane=$($recovery.lane)"
}
if (-not [bool]$recovery.execution_owner_may_install_missing_packages) {
    throw 'Contract denies execution-owner package repair authority.'
}
if ([bool]$recovery.additional_operator_confirmation_required) {
    throw 'Contract unexpectedly requires additional operator confirmation for package repair.'
}
if ([bool]$recovery.credential_mutation) {
    throw 'Contract must keep credential_mutation=false.'
}

$canonicalDistribution = [string]$recovery.distribution
if ([string]::IsNullOrWhiteSpace($canonicalDistribution)) {
    $canonicalDistribution = [string]$integration.platform_contract.wsl_distribution
}
if ($WslDistribution -ne $canonicalDistribution) {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_WSL_DISTRIBUTION'
    Write-Host "CONTRACT_WSL_DISTRIBUTION=$canonicalDistribution"
    Write-Host "REQUESTED_WSL_DISTRIBUTION=$WslDistribution"
    Write-Host 'NEXT=rerun with -WslDistribution matching integration-contract physical_floor_recovery.distribution (or platform_contract.wsl_distribution)'
    exit 1
}

$packageManager = [string]$recovery.package_manager
$allowlist = @($recovery.package_allowlist | ForEach-Object { [string]$_ })
if ($packageManager -ne 'apt-get') {
    throw "Unsupported package_manager=$packageManager"
}
if ($allowlist.Count -eq 0) {
    throw 'physical_floor_recovery.package_allowlist is empty.'
}

function Normalize-NativeText {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return '' }
    return $Text.Replace(([char]0).ToString(), '')
}

function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FileName
    $psi.WorkingDirectory = $env:SystemRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        [void]$psi.ArgumentList.Add([string]$argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    try {
        if (-not $process.Start()) {
            Write-Host 'STATUS=BLOCKED_HARNESS_START'
            Write-Host "PROCESS_FILE=$FileName"
            Write-Host "NEXT=ensure $FileName can launch on this host, then rerun; unable to start process"
            exit 1
        }
    }
    catch {
        Write-Host 'STATUS=BLOCKED_HARNESS_START'
        Write-Host "PROCESS_FILE=$FileName"
        Write-Host "NEXT=ensure $FileName can launch on this host, then rerun; process Start threw"
        Write-Host ("HARNESS_START_ERROR={0}" -f $_.Exception.Message)
        exit 1
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    $timedOut = -not $completed
    if ($timedOut) {
        try {
            $process.Kill($true)
            $process.WaitForExit()
        }
        catch {}
    }

    return [pscustomobject]@{
        ExitCode = if ($timedOut) { 124 } else { $process.ExitCode }
        TimedOut = $timedOut
        Stdout = Normalize-NativeText -Text $stdoutTask.GetAwaiter().GetResult()
        Stderr = Normalize-NativeText -Text $stderrTask.GetAwaiter().GetResult()
    }
}

function Get-StatusFromText {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match($Text, '(?m)^STATUS=(.+)$')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $null
}

function Get-NextActionFromText {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match($Text, '(?m)^NEXT_ACTION=(.+)$')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $null
}

function Get-OperatorNextFromText {
    param([AllowNull()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match($Text, '(?m)^NEXT=(.+)$')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    $inline = [regex]::Match($Text, '(?m)(?:^|\s)NEXT=(.+)$')
    if ($inline.Success) { return $inline.Groups[1].Value.Trim() }
    return $null
}

function Test-AllowlistedAptNextAction {
    param(
        [Parameter(Mandatory = $true)][string]$NextAction,
        [Parameter(Mandatory = $true)][string[]]$PackageAllowlist
    )

    $trimmed = $NextAction.Trim()
    $prefix = 'sudo apt-get update && sudo apt-get install -y '
    if (-not $trimmed.StartsWith($prefix)) {
        return $false
    }
    $packagesText = $trimmed.Substring($prefix.Length).Trim()
    if ([string]::IsNullOrWhiteSpace($packagesText)) {
        return $false
    }
    if ($packagesText -match '[;&|<>`$]') {
        return $false
    }
    $packages = @($packagesText -split '\s+' | Where-Object { $_ -ne '' })
    if ($packages.Count -eq 0) {
        return $false
    }
    foreach ($package in $packages) {
        if ($package -notin $PackageAllowlist) {
            return $false
        }
    }
    return $true
}

function Invoke-PhysicalFloorOnce {
    param(
        [Parameter(Mandatory = $true)][string]$AttemptEvidenceRoot,
        [Parameter(Mandatory = $true)][System.Management.Automation.CommandInfo]$PwshCommand
    )

    New-Item -ItemType Directory -Force -Path $AttemptEvidenceRoot | Out-Null
    $stdoutPath = Join-Path $AttemptEvidenceRoot 'continuation-physical-floor-stdout.txt'
    $stderrPath = Join-Path $AttemptEvidenceRoot 'continuation-physical-floor-stderr.txt'

    $argumentList = @(
        '-NoLogo', '-NoProfile', '-File', $PhysicalFloorPath,
        '-ExpectedHead', $ExpectedHead,
        '-WslDistribution', $WslDistribution,
        '-EvidenceRoot', $AttemptEvidenceRoot,
        '-PrerequisiteTimeoutSeconds', "$PrerequisiteTimeoutSeconds"
    )
    if (-not [string]::IsNullOrWhiteSpace($SourceRepositoryPath)) {
        $argumentList += @('-SourceRepositoryPath', $SourceRepositoryPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($FirstMatePath)) {
        $argumentList += @('-FirstMatePath', $FirstMatePath)
    }

    $captured = Invoke-CapturedProcess -FileName $PwshCommand.Source -Arguments $argumentList -TimeoutSeconds 900
    Set-Content -LiteralPath $stdoutPath -Value $captured.Stdout.TrimEnd()
    Set-Content -LiteralPath $stderrPath -Value $captured.Stderr.TrimEnd()
    if (-not [string]::IsNullOrWhiteSpace($captured.Stdout)) {
        Write-Host $captured.Stdout.TrimEnd()
    }
    if (-not [string]::IsNullOrWhiteSpace($captured.Stderr)) {
        Write-Host $captured.Stderr.TrimEnd()
    }

    $combined = ($captured.Stdout + "`n" + $captured.Stderr)
    $prerequisitePath = Join-Path $AttemptEvidenceRoot 'firstmate-wsl-prerequisites.txt'
    if (Test-Path -LiteralPath $prerequisitePath -PathType Leaf) {
        $combined = $combined + "`n" + (Get-Content -LiteralPath $prerequisitePath -Raw)
    }
    $bridgeStderrPath = Join-Path $AttemptEvidenceRoot 'bridge-stderr.txt'
    if (Test-Path -LiteralPath $bridgeStderrPath -PathType Leaf) {
        $combined = $combined + "`n" + (Get-Content -LiteralPath $bridgeStderrPath -Raw)
    }

    $status = Get-StatusFromText -Text $combined
    if ([string]::IsNullOrWhiteSpace($status)) {
        if ($captured.ExitCode -eq 44) { $status = 'BLOCKED_MISSING_TOOLS' }
        elseif ($captured.ExitCode -eq 45) { $status = 'BLOCKED_GITHUB_AUTH' }
        elseif ($captured.ExitCode -eq 0) { $status = 'PASS' }
    }

    return [pscustomobject]@{
        ExitCode = $captured.ExitCode
        Status = $status
        NextAction = Get-NextActionFromText -Text $combined
        EvidenceRoot = $AttemptEvidenceRoot
        PrerequisitePath = $prerequisitePath
    }
}

if ($ContractOnly) {
    $probeAction = 'sudo apt-get update && sudo apt-get install -y gh'
    if (-not (Test-AllowlistedAptNextAction -NextAction $probeAction -PackageAllowlist $allowlist)) {
        throw 'ContractOnly allowlist probe unexpectedly rejected gh repair.'
    }
    $rejectAction = 'sudo apt-get update && sudo apt-get install -y curl'
    if (Test-AllowlistedAptNextAction -NextAction $rejectAction -PackageAllowlist $allowlist) {
        throw 'ContractOnly allowlist probe unexpectedly accepted non-allowlisted curl.'
    }
    Write-Host '[PASS] FIRSTMATE_PHYSICAL_FLOOR_CONTINUATION_CONTRACT'
    Write-Host "HEAD=$ExpectedHead"
    Write-Host "WSL_DISTRIBUTION=$WslDistribution"
    Write-Host "PACKAGE_ALLOWLIST=$($allowlist -join ',')"
    Write-Host 'CREDENTIAL_MUTATION=false'
    Write-Host 'HARNESS_INSTALLS_PACKAGES=false'
    Write-Host 'EXECUTION_OWNER_MAY_INSTALL_MISSING_PACKAGES=true'
    exit 0
}

$actualHeadRaw = & git -C $Root rev-parse HEAD
if ($LASTEXITCODE -ne 0) {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_GIT_HEAD'
    Write-Host 'NEXT=repair the AgentSwitchboard checkout so git rev-parse HEAD succeeds, then rerun Invoke-FirstMatePhysicalFloorContinuation.ps1'
    Write-Host 'Unable to resolve exact AgentSwitchboard HEAD.'
    exit 1
}
$actualHead = ("$actualHeadRaw").Trim()
if ($actualHead -ne $ExpectedHead.ToLowerInvariant()) {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_HEAD_MISMATCH'
    Write-Host "EXPECTED_HEAD=$ExpectedHead"
    Write-Host "ACTUAL_HEAD=$actualHead"
    Write-Host 'NEXT=ff-only refresh main, re-resolve HEAD, and rerun with the recorded SHA'
    exit 1
}

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) {
    Write-Host 'STATUS=BLOCKED_WINDOWS_WSL_REQUIRED'
    Write-Host 'FAILURE_CODE=WINDOWS_WSL_REQUIRED'
    Write-Host 'PROOF_LEVEL=LIVE_ATTEMPT_FAIL_CLOSED'
    Write-Host "HEAD=$actualHead"
    Write-Host "WSL_DISTRIBUTION=$WslDistribution"
    Write-Host '[PROOF_CEILING] physical-floor-continue requires Windows+wsl.exe+Ubuntu; package-repair authority does not create that host.'
    exit 46
}
$pwsh = Get-Command pwsh -ErrorAction Stop

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $runId = '{0}-{1}-{2}' -f $actualHead.Substring(0, 8), (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $EvidenceRoot = Join-Path ([System.IO.Path]::GetTempPath()) "AgentSwitchboard\firstmate-physical-floor-continue\$runId"
}
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$EvidenceRoot = (Resolve-Path -LiteralPath $EvidenceRoot).Path

Write-Host '[FM-WSL-12] physical-floor continuation start'
Write-Host "HEAD=$actualHead"
Write-Host "WSL_DISTRIBUTION=$WslDistribution"
Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
Write-Host 'AUTHORITY=execution_owner_may_install_missing_packages; harness remains non-installing'

$packageRepairs = 0
for ($attempt = 1; $attempt -le ($MaxPackageRepairAttempts + 1); $attempt++) {
    $attemptRoot = Join-Path $EvidenceRoot ("attempt-{0:d2}" -f $attempt)
    Write-Host "[FM-WSL-12] physical-floor attempt $attempt"
    $result = Invoke-PhysicalFloorOnce -AttemptEvidenceRoot $attemptRoot -PwshCommand $pwsh

    if ($result.ExitCode -eq 0 -or $result.Status -eq 'PASS') {
        Write-Host '[PASS] FIRSTMATE_WINDOWS_WSL_PHYSICAL_FLOOR_CONTINUATION'
        Write-Host "HEAD=$actualHead"
        Write-Host "WSL_DISTRIBUTION=$WslDistribution"
        Write-Host "PACKAGE_REPAIR_COUNT=$packageRepairs"
        Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
        Write-Host '[PROOF_CEILING] Physical WSL interoperability floor only; no live FirstMate crew dispatch is proven.'
        exit 0
    }

    $status = $result.Status
    $nextAction = $result.NextAction
    Write-Host "STATUS=$status"
    if (-not [string]::IsNullOrWhiteSpace($nextAction)) {
        Write-Host "NEXT_ACTION=$nextAction"
    }

    if ($status -eq 'BLOCKED_GITHUB_AUTH' -or $result.ExitCode -eq 45) {
        Write-Host '[BLOCKED] BLOCKED_GITHUB_AUTH — operator credential/login required; package repair authority does not cover authentication.'
        Write-Host "PREREQUISITE_EVIDENCE=$($result.PrerequisitePath)"
        Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
        exit 45
    }

    if ($status -ne 'BLOCKED_MISSING_TOOLS' -and $result.ExitCode -ne 44) {
        Write-Host "[BLOCKED] Non-package physical-floor blocker STATUS=$status Exit=$($result.ExitCode)"
        $operatorBlob = @(
            $nextAction
            (Get-Content -LiteralPath (Join-Path $attemptRoot 'continuation-physical-floor-stdout.txt') -Raw -ErrorAction SilentlyContinue)
            (Get-Content -LiteralPath (Join-Path $attemptRoot 'continuation-physical-floor-stderr.txt') -Raw -ErrorAction SilentlyContinue)
            (Get-Content -LiteralPath (Join-Path $attemptRoot 'bridge-stderr.txt') -Raw -ErrorAction SilentlyContinue)
        ) -join "`n"
        $operatorNext = Get-OperatorNextFromText -Text $operatorBlob
        if (-not [string]::IsNullOrWhiteSpace($operatorNext)) {
            Write-Host "NEXT=$operatorNext"
        }
        Write-Host "PREREQUISITE_EVIDENCE=$($result.PrerequisitePath)"
        Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
        exit $(if ($result.ExitCode -ne 0) { $result.ExitCode } else { 1 })
    }

    if ($packageRepairs -ge $MaxPackageRepairAttempts) {
        Write-Host "[BLOCKED] Exhausted $MaxPackageRepairAttempts bounded package-repair attempt(s)."
        Write-Host 'STATUS=BLOCKED_MISSING_TOOLS'
        Write-Host 'FAILURE_CODE=BOUNDED_PACKAGE_REPAIR_EXHAUSTED'
        Write-Host 'NEXT=inspect NEXT_ACTION=/evidence; install allowlisted missing tools manually if apt repair did not clear them, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
        if (-not [string]::IsNullOrWhiteSpace($nextAction)) {
            Write-Host "NEXT_ACTION=$nextAction"
        }
        Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
        exit 44
    }

    if ([string]::IsNullOrWhiteSpace($nextAction)) {
        # Keep structured — do not throw (throw collapses to unstructured exit 1).
        Write-Host 'STATUS=BLOCKED_MISSING_TOOLS'
        Write-Host 'FAILURE_CODE=MISSING_TOOLS_WITHOUT_NEXT_ACTION'
        Write-Host 'NEXT=inspect physical-floor evidence for NEXT_ACTION=; repair gate output so missing-tools emits an allowlisted NEXT_ACTION, then rerun'
        Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
        exit 44
    }
    if (-not (Test-AllowlistedAptNextAction -NextAction $nextAction -PackageAllowlist $allowlist)) {
        # Keep structured — do not throw (throw collapses to unstructured exit 1).
        Write-Host 'STATUS=BLOCKED_MISSING_TOOLS'
        Write-Host 'FAILURE_CODE=NON_ALLOWLISTED_NEXT_ACTION'
        Write-Host "NEXT_ACTION=$nextAction"
        Write-Host 'NEXT=emit an allowlisted apt-get NEXT_ACTION from the physical-floor gate (or clear missing tools manually), then rerun'
        Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
        exit 44
    }

    Write-Host "[FM-WSL-12] probing passwordless sudo for apt-get before bounded apt repair"
    # Probe the privilege actually used for repair (apt-get), not an unrelated binary.
    $sudoProbeArgs = @('--distribution', $WslDistribution, '--exec', 'bash', '-lc', 'sudo -n apt-get --version')
    $sudoProbe = Invoke-CapturedProcess -FileName $wsl.Source -Arguments $sudoProbeArgs -TimeoutSeconds 30
    $sudoProbeStdout = Join-Path $attemptRoot 'sudo-probe-stdout.txt'
    $sudoProbeStderr = Join-Path $attemptRoot 'sudo-probe-stderr.txt'
    Set-Content -LiteralPath $sudoProbeStdout -Value $sudoProbe.Stdout
    Set-Content -LiteralPath $sudoProbeStderr -Value $sudoProbe.Stderr
    if ($sudoProbe.ExitCode -ne 0) {
        Write-Host 'STATUS=BLOCKED_SUDO'
        Write-Host 'FAILURE_CODE=PASSWORDLESS_SUDO_APT_REQUIRED'
        Write-Host 'NEXT=enable passwordless sudo for apt-get in Ubuntu (sudo -n apt-get --version must succeed), then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
        Write-Host "SUDO_PROBE_EXIT_CODE=$($sudoProbe.ExitCode)"
        Write-Host "SUDO_PROBE_TIMED_OUT=$($sudoProbe.TimedOut)"
        Write-Host "SUDO_PROBE_STDOUT=$sudoProbeStdout"
        Write-Host "SUDO_PROBE_STDERR=$sudoProbeStderr"
        Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
        exit 47
    }

    Write-Host "[FM-WSL-12] executing bounded package repair inside $WslDistribution (no extra permission round-trip)"
    $repairStdout = Join-Path $attemptRoot 'bounded-package-repair-stdout.txt'
    $repairStderr = Join-Path $attemptRoot 'bounded-package-repair-stderr.txt'
    $repairArgs = @('--distribution', $WslDistribution, '--exec', 'bash', '-lc', "set -euo pipefail; $nextAction")
    $repair = Invoke-CapturedProcess -FileName $wsl.Source -Arguments $repairArgs -TimeoutSeconds 900
    Set-Content -LiteralPath $repairStdout -Value $repair.Stdout
    Set-Content -LiteralPath $repairStderr -Value $repair.Stderr
    if ($repair.ExitCode -ne 0) {
        Write-Host "[BLOCKED] Bounded apt-get repair failed. Exit=$($repair.ExitCode)"
        Write-Host 'STATUS=BLOCKED_MISSING_TOOLS'
        Write-Host 'FAILURE_CODE=BOUNDED_APT_REPAIR_FAILED'
        Write-Host 'NEXT=inspect REPAIR_STDERR; fix apt failure (dpkg lock/network/mirror), then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
        if (-not [string]::IsNullOrWhiteSpace($nextAction)) {
            Write-Host "NEXT_ACTION=$nextAction"
        }
        Write-Host "REPAIR_STDOUT=$repairStdout"
        Write-Host "REPAIR_STDERR=$repairStderr"
        Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
        exit 44
    }

    $packageRepairs++
    Write-Host "[FM-WSL-12] package repair succeeded; rerunning physical-floor (repair_count=$packageRepairs)"
}

Write-Host '[BLOCKED] Continuation loop ended without PASS.'
Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
exit 1
