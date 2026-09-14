<#
.SYNOPSIS
  FM-WSL-12 Admin Box one-shot: contract → physical-floor-continue → protected control.

.DESCRIPTION
  Durable operator entrypoint for the FM-WSL-12 live runtime proof on an authorized
  Windows Admin Box. Runs the contract floor, then physical-floor-continue (allowlisted
  apt repair + rerun), then optionally the report-only physical-floor protected control.

  Does not mutate credentials. Exit 45 (BLOCKED_GITHUB_AUTH) remains an operator gate.
  Cloud/Linux hosts without wsl.exe fail closed with exit 46 (WINDOWS_WSL_REQUIRED).
  Local receipt text is written under an untracked evidence root; do not commit it.
#>
[CmdletBinding()]
param(
    [string]$ExpectedHead,

    [string]$FirstMatePath,
    [string]$SourceRepositoryPath,
    [string]$EvidenceRoot,
    [string]$WslDistribution = 'Ubuntu',

    [switch]$SkipProtectedControl,
    [switch]$ContractOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7+ (pwsh) is required for FM-WSL-12 Admin Box live proof.'
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$HarnessPath = Join-Path $Root 'Test-AgentSwitchboard-FirstMate-Harness.ps1'
$IntegrationContractPath = Join-Path $Root 'tooling\firstmate\harness\integration-contract.json'

if (-not (Test-Path -LiteralPath $HarnessPath -PathType Leaf)) {
    throw "Missing FirstMate harness front door: $HarnessPath"
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

$canonicalDistribution = [string]$recovery.distribution
if ([string]::IsNullOrWhiteSpace($canonicalDistribution)) {
    $canonicalDistribution = [string]$integration.platform_contract.wsl_distribution
}
if ($WslDistribution -ne $canonicalDistribution) {
    throw "WSL distribution mismatch. Contract=$canonicalDistribution Requested=$WslDistribution"
}

if ([string]::IsNullOrWhiteSpace($ExpectedHead)) {
    $ExpectedHead = (& git -C $Root rev-parse HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve exact AgentSwitchboard HEAD.' }
}
if ($ExpectedHead -notmatch '^[0-9a-fA-F]{40}$') {
    throw "ExpectedHead must be a 40-character SHA. Received=$ExpectedHead"
}

$actualHead = (& git -C $Root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve exact AgentSwitchboard HEAD.' }
if ($actualHead -ne $ExpectedHead.ToLowerInvariant()) {
    throw "Exact-head mismatch. Expected=$ExpectedHead Actual=$actualHead"
}

if ($ContractOnly) {
    Write-Host '[PASS] FM_WSL_12_ADMIN_BOX_LIVE_PROOF_CONTRACT'
    Write-Host "HEAD=$actualHead"
    Write-Host "WSL_DISTRIBUTION=$WslDistribution"
    Write-Host 'SEQUENCE=contract,physical-floor-continue,physical-floor(protected)'
    Write-Host 'CREDENTIAL_MUTATION=false'
    Write-Host 'PROOF_CEILING=Admin Box live observation required; ContractOnly is not live PASS'
    exit 0
}

$pwsh = Get-Command pwsh -ErrorAction Stop

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $runId = '{0}-{1}-{2}' -f $actualHead.Substring(0, 8), (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $EvidenceRoot = Join-Path ([System.IO.Path]::GetTempPath()) "AgentSwitchboard\fm-wsl12-admin-box-live\$runId"
}
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$EvidenceRoot = (Resolve-Path -LiteralPath $EvidenceRoot).Path
$receiptPath = Join-Path $EvidenceRoot 'fm-wsl12-admin-box-live-receipt.txt'

function Invoke-HarnessMode {
    param(
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string]$AttemptEvidenceRoot
    )

    New-Item -ItemType Directory -Force -Path $AttemptEvidenceRoot | Out-Null
    $argumentList = @(
        '-NoLogo', '-NoProfile', '-File', $HarnessPath,
        '-Mode', $Mode,
        '-ExpectedHead', $ExpectedHead,
        '-WslDistribution', $WslDistribution,
        '-EvidenceRoot', $AttemptEvidenceRoot
    )
    if (-not [string]::IsNullOrWhiteSpace($SourceRepositoryPath)) {
        $argumentList += @('-SourceRepositoryPath', $SourceRepositoryPath)
    }
    if (-not [string]::IsNullOrWhiteSpace($FirstMatePath)) {
        $argumentList += @('-FirstMatePath', $FirstMatePath)
    }

    $stdoutPath = Join-Path $AttemptEvidenceRoot 'stdout.txt'
    $stderrPath = Join-Path $AttemptEvidenceRoot 'stderr.txt'

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $pwsh.Source
    $psi.WorkingDirectory = $Root
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in $argumentList) {
        [void]$psi.ArgumentList.Add([string]$argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    if (-not $process.Start()) { throw "Unable to start harness mode=$Mode." }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit(3600 * 1000)
    if (-not $completed) {
        try { $process.Kill($true); $process.WaitForExit() } catch {}
        throw "Harness mode=$Mode timed out after 3600 seconds."
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    Set-Content -LiteralPath $stdoutPath -Value $stdout
    Set-Content -LiteralPath $stderrPath -Value $stderr
    if (-not [string]::IsNullOrWhiteSpace($stdout)) { Write-Host $stdout.TrimEnd() }
    if (-not [string]::IsNullOrWhiteSpace($stderr)) { Write-Host $stderr.TrimEnd() }

    return [pscustomobject]@{
        Mode = $Mode
        ExitCode = $process.ExitCode
        EvidenceRoot = $AttemptEvidenceRoot
    }
}

Write-Host '[FM-WSL-12] Admin Box live-proof sequence start'
Write-Host "HEAD=$actualHead"
Write-Host "WSL_DISTRIBUTION=$WslDistribution"
Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
Write-Host 'PROOF_CEILING=physical WSL floor only; no FirstMate crew dispatch'

$steps = [System.Collections.Generic.List[string]]::new()
$finalExit = 0

$contract = Invoke-HarnessMode -Mode 'contract' -AttemptEvidenceRoot (Join-Path $EvidenceRoot '01-contract')
$steps.Add("contract:$($contract.ExitCode)")
if ($contract.ExitCode -ne 0) {
    $finalExit = $contract.ExitCode
    Set-Content -LiteralPath $receiptPath -Value @(
        "HEAD=$actualHead"
        "WSL_DISTRIBUTION=$WslDistribution"
        "EVIDENCE_ROOT=$EvidenceRoot"
        "STEPS=$($steps -join ',')"
        "FINAL_EXIT=$finalExit"
        'RESULT=CONTRACT_FAILED'
        'LIVE_RUNTIME_PROOF=UNPROVEN'
    )
    exit $finalExit
}

$continue = Invoke-HarnessMode -Mode 'physical-floor-continue' -AttemptEvidenceRoot (Join-Path $EvidenceRoot '02-physical-floor-continue')
$steps.Add("physical-floor-continue:$($continue.ExitCode)")
if ($continue.ExitCode -ne 0) {
    $finalExit = $continue.ExitCode
    $result = if ($continue.ExitCode -eq 45) {
        'BLOCKED_GITHUB_AUTH'
    } elseif ($continue.ExitCode -eq 46) {
        'BLOCKED_WINDOWS_WSL_REQUIRED'
    } elseif ($continue.ExitCode -eq 44) {
        'BLOCKED_MISSING_TOOLS'
    } else {
        'PHYSICAL_FLOOR_CONTINUE_FAILED'
    }
    Set-Content -LiteralPath $receiptPath -Value @(
        "HEAD=$actualHead"
        "WSL_DISTRIBUTION=$WslDistribution"
        "EVIDENCE_ROOT=$EvidenceRoot"
        "STEPS=$($steps -join ',')"
        "FINAL_EXIT=$finalExit"
        "RESULT=$result"
        'LIVE_RUNTIME_PROOF=UNPROVEN'
        'RECEIPT_PATH=' + $receiptPath
    )
    Write-Host "RECEIPT_PATH=$receiptPath"
    Write-Host "RESULT=$result"
    exit $finalExit
}

if (-not $SkipProtectedControl) {
    $protected = Invoke-HarnessMode -Mode 'physical-floor' -AttemptEvidenceRoot (Join-Path $EvidenceRoot '03-physical-floor-protected')
    $steps.Add("physical-floor:$($protected.ExitCode)")
    if ($protected.ExitCode -ne 0) {
        $finalExit = $protected.ExitCode
        Set-Content -LiteralPath $receiptPath -Value @(
            "HEAD=$actualHead"
            "WSL_DISTRIBUTION=$WslDistribution"
            "EVIDENCE_ROOT=$EvidenceRoot"
            "STEPS=$($steps -join ',')"
            "FINAL_EXIT=$finalExit"
            'RESULT=PROTECTED_CONTROL_FAILED'
            'LIVE_RUNTIME_PROOF=UNPROVEN'
            'NOTE=continuation PASS then protected-control failure; investigate regression'
            'RECEIPT_PATH=' + $receiptPath
        )
        Write-Host "RECEIPT_PATH=$receiptPath"
        Write-Host 'RESULT=PROTECTED_CONTROL_FAILED'
        exit $finalExit
    }
} else {
    $steps.Add('physical-floor:skipped')
}

Set-Content -LiteralPath $receiptPath -Value @(
    "HEAD=$actualHead"
    "WSL_DISTRIBUTION=$WslDistribution"
    "EVIDENCE_ROOT=$EvidenceRoot"
    "STEPS=$($steps -join ',')"
    'FINAL_EXIT=0'
    'RESULT=PHYSICAL_FLOOR_PASS'
    'LIVE_RUNTIME_PROOF=OBSERVED_PHYSICAL_FLOOR_ONLY'
    'PROOF_CEILING=no FirstMate crew dispatch claimed'
    'RECEIPT_PATH=' + $receiptPath
)

Write-Host '[PASS] FM_WSL_12_ADMIN_BOX_LIVE_PROOF'
Write-Host "HEAD=$actualHead"
Write-Host "WSL_DISTRIBUTION=$WslDistribution"
Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
Write-Host "RECEIPT_PATH=$receiptPath"
Write-Host 'LIVE_RUNTIME_PROOF=OBSERVED_PHYSICAL_FLOOR_ONLY'
Write-Host '[PROOF_CEILING] Physical WSL interoperability floor only; no live FirstMate crew dispatch is proven.'
exit 0
