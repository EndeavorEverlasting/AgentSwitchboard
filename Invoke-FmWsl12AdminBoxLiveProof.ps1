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
    $ExpectedHeadRaw = & git -C $Root rev-parse HEAD
    if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve exact AgentSwitchboard HEAD.' }
    $ExpectedHead = ("$ExpectedHeadRaw").Trim()
}
if ($ExpectedHead -notmatch '^[0-9a-fA-F]{40}$') {
    throw "ExpectedHead must be a 40-character SHA. Received=$ExpectedHead"
}

$actualHeadRaw = & git -C $Root rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve exact AgentSwitchboard HEAD.' }
$actualHead = ("$actualHeadRaw").Trim()
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
        StdoutPath = $stdoutPath
        StderrPath = $stderrPath
    }
}

function Get-OperatorNextFromEvidence {
    param([Parameter(Mandatory = $true)]$Attempt)
    $blob = ''
    foreach ($path in @($Attempt.StdoutPath, $Attempt.StderrPath)) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            $blob += "`n" + (Get-Content -LiteralPath $path -Raw)
        }
    }
    $match = [regex]::Match($blob, '(?m)^NEXT=(.+)$')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    $inline = [regex]::Match($blob, '(?m)(?:^|\s)NEXT=(.+)$')
    if ($inline.Success) { return $inline.Groups[1].Value.Trim() }
    $nextAction = [regex]::Match($blob, '(?m)^NEXT_ACTION=(.+)$')
    if ($nextAction.Success) { return $nextAction.Groups[1].Value.Trim() }
    return $null
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
    } elseif ($continue.ExitCode -eq 47) {
        'BLOCKED_SUDO'
    } elseif ($continue.ExitCode -eq 48) {
        'BLOCKED_PRIMARY_HARNESS'
    } elseif ($continue.ExitCode -eq 49) {
        'BLOCKED_FIRSTMATE_DIRTY'
    } elseif ($continue.ExitCode -eq 50) {
        'BLOCKED_FIRSTMATE_PIN'
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
    # Prefer child NEXT= (includes -FirstMatePath-specific guidance) over hardcoded
    # $HOME/firstmate fallbacks so operators do not repair the wrong tree.
    $preservedNext = Get-OperatorNextFromEvidence -Attempt $continue
    if (-not [string]::IsNullOrWhiteSpace($preservedNext)) {
        Write-Host "NEXT=$preservedNext"
    } elseif ($continue.ExitCode -eq 45) {
        Write-Host 'NEXT=complete gh auth login inside Ubuntu, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
    } elseif ($continue.ExitCode -eq 46) {
        Write-Host 'NEXT=run on Windows Admin Box with wsl.exe and Ubuntu; cloud/Linux hosts cannot prove physical floor'
    } elseif ($continue.ExitCode -eq 44) {
        Write-Host 'NEXT=install allowlisted missing tools via printed NEXT_ACTION, then rerun'
    } elseif ($continue.ExitCode -eq 47) {
        Write-Host 'NEXT=enable passwordless sudo for apt-get in Ubuntu (sudo -n apt-get --version must succeed), then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
    } elseif ($continue.ExitCode -eq 48) {
        Write-Host 'NEXT=install one primary harness on PATH inside Ubuntu visible to non-interactive bash -lc (claude|grok|pi|pi-signed|omp|codex|opencode|cursor-agent), then rerun'
    } elseif ($continue.ExitCode -eq 49) {
        Write-Host 'NEXT=commit/stash/move dirty work in $HOME/firstmate (or the -FirstMatePath override), or remove $HOME/firstmate so bounded bootstrap can run, then rerun'
    } elseif ($continue.ExitCode -eq 50) {
        Write-Host 'NEXT=in $HOME/firstmate (or -FirstMatePath) run: git fetch --all && git checkout b182d0f908b78d08c7ccb8dce3775bdca8c5d657, or remove that path / pass -FirstMatePath to a clean audited checkout, then rerun'
    } else {
        Write-Host 'NEXT=inspect evidence for NEXT=/NEXT_ACTION=; repair operator blocker; rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
    }
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
