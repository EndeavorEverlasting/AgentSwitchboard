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

    [ValidateRange(10, 300)]
    [int]$PrerequisiteTimeoutSeconds = 180,

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
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_HARNESS_CONTRACT'
    Write-Host "NEXT=restore Test-AgentSwitchboard-FirstMate-Harness.ps1 at checkout root ($HarnessPath), then rerun Invoke-FmWsl12AdminBoxLiveProof.ps1"
    exit 52
}
if (-not (Test-Path -LiteralPath $IntegrationContractPath -PathType Leaf)) {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_HARNESS_CONTRACT'
    Write-Host "NEXT=restore tooling/firstmate/harness/integration-contract.json ($IntegrationContractPath), then rerun Invoke-FmWsl12AdminBoxLiveProof.ps1"
    exit 52
}

$UpstreamPinPath = Join-Path $Root 'tooling\firstmate\harness\upstream-pin.json'
if (-not (Test-Path -LiteralPath $UpstreamPinPath -PathType Leaf)) {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_HARNESS_CONTRACT'
    Write-Host "NEXT=restore tooling/firstmate/harness/upstream-pin.json ($UpstreamPinPath), then rerun Invoke-FmWsl12AdminBoxLiveProof.ps1"
    exit 52
}
$upstreamPin = Get-Content -LiteralPath $UpstreamPinPath -Raw | ConvertFrom-Json
$expectedFirstMateHead = [string]$upstreamPin.commit
if ($expectedFirstMateHead -notmatch '^[0-9a-f]{40}$') {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_FIRSTMATE_PIN'
    Write-Host "NEXT=repair tooling/firstmate/harness/upstream-pin.json so commit is a 40-character lowercase hex SHA; Received=$expectedFirstMateHead"
    exit 50
}

$integration = Get-Content -LiteralPath $IntegrationContractPath -Raw | ConvertFrom-Json
$recovery = $integration.physical_floor_recovery
if ($null -eq $recovery) {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_HARNESS_CONTRACT'
    Write-Host 'NEXT=repair tooling/firstmate/harness/integration-contract.json so physical_floor_recovery is present, then rerun Invoke-FmWsl12AdminBoxLiveProof.ps1'
    exit 52
}
if ([string]$recovery.lane -ne 'FM-WSL-12') {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_HARNESS_CONTRACT'
    Write-Host "NEXT=repair tooling/firstmate/harness/integration-contract.json physical_floor_recovery.lane to FM-WSL-12; Received=$($recovery.lane)"
    exit 52
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

if ([string]::IsNullOrWhiteSpace($ExpectedHead)) {
    $ExpectedHeadRaw = & git -C $Root rev-parse HEAD
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'STATUS=BLOCKED_GIT_HEAD'
        Write-Host 'NEXT=repair the AgentSwitchboard checkout so git rev-parse HEAD succeeds, then rerun Invoke-FmWsl12AdminBoxLiveProof.ps1'
        Write-Host 'Unable to resolve exact AgentSwitchboard HEAD.'
        exit 1
    }
    $ExpectedHead = ("$ExpectedHeadRaw").Trim()
}
if ($ExpectedHead -notmatch '^[0-9a-fA-F]{40}$') {
    Write-Host 'STATUS=BLOCKED_GIT_HEAD'
    Write-Host "NEXT=pass -ExpectedHead as a 40-character SHA (or repair checkout HEAD); Received=$ExpectedHead"
    exit 1
}

$actualHeadRaw = & git -C $Root rev-parse HEAD
if ($LASTEXITCODE -ne 0) {
    Write-Host 'STATUS=BLOCKED_GIT_HEAD'
    Write-Host 'NEXT=repair the AgentSwitchboard checkout so git rev-parse HEAD succeeds, then rerun Invoke-FmWsl12AdminBoxLiveProof.ps1'
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
    $argumentList += @('-PrerequisiteTimeoutSeconds', "$PrerequisiteTimeoutSeconds")

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
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    try {
        if (-not $process.Start()) {
            Write-Host 'STATUS=BLOCKED_HARNESS_START'
            Write-Host "HARNESS_MODE=$Mode"
            Write-Host 'NEXT=ensure pwsh can launch Test-AgentSwitchboard-FirstMate-Harness.ps1, then rerun; unable to start harness process'
            exit 1
        }
    }
    catch {
        Write-Host 'STATUS=BLOCKED_HARNESS_START'
        Write-Host "HARNESS_MODE=$Mode"
        Write-Host 'NEXT=ensure pwsh can launch Test-AgentSwitchboard-FirstMate-Harness.ps1, then rerun; harness process Start threw'
        Write-Host ("HARNESS_START_ERROR={0}" -f $_.Exception.Message)
        exit 1
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    # Mirror continuation (#281): outer PhysicalFloor once = Max(900, 2×prereq + 600 + 120).
    # Continuation defaults MaxPackageRepairAttempts=2 → up to 3 floor attempts + 2×(sudo+apt900).
    # Fixed 3600s under-ran that budget at PrerequisiteTimeoutSeconds=180 (≈5400s worst case).
    $physicalFloorOuterTimeoutSeconds = [Math]::Max(900, ($PrerequisiteTimeoutSeconds * 2) + 600 + 120)
    $continuationMaxPackageRepairAttempts = 2
    $continueBudgetSeconds = (($continuationMaxPackageRepairAttempts + 1) * $physicalFloorOuterTimeoutSeconds) +
        ($continuationMaxPackageRepairAttempts * ($PrerequisiteTimeoutSeconds + 900)) + 120
    $harnessTimeoutSeconds = [Math]::Max(3600, $continueBudgetSeconds)
    $completed = $process.WaitForExit($harnessTimeoutSeconds * 1000)
    if (-not $completed) {
        # Bound teardown: unbounded WaitForExit after Kill can hang Admin Box forever if the
        # child tree ignores Kill (WSL/orphans). 30s matches operator-visible timeout surfaces.
        $killTeardownTimeoutMs = 30000
        try {
            $process.Kill($true)
            [void]$process.WaitForExit($killTeardownTimeoutMs)
        }
        catch {}
        # Keep exit 124 structured — do not throw (throw collapses to unstructured exit 1).
        Write-Host 'STATUS=BLOCKED_HARNESS_TIMEOUT'
        Write-Host "HARNESS_MODE=$Mode"
        Write-Host "HARNESS_TIMEOUT_SECONDS=$harnessTimeoutSeconds"
        Write-Host "NEXT=inspect hung WSL/harness work, increase host capacity or repair the hang, then rerun; harness timed out after $harnessTimeoutSeconds seconds"
        exit 124
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

function Get-AttemptEvidenceBlob {
    param([Parameter(Mandatory = $true)]$Attempt)
    $blob = ''
    foreach ($path in @($Attempt.StdoutPath, $Attempt.StderrPath)) {
        if (-not [string]::IsNullOrWhiteSpace($path) -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            $blob += "`n" + (Get-Content -LiteralPath $path -Raw)
        }
    }
    return $blob
}

function Get-OperatorNextFromEvidence {
    param([Parameter(Mandatory = $true)]$Attempt)
    $blob = Get-AttemptEvidenceBlob -Attempt $Attempt
    $match = [regex]::Match($blob, '(?m)^NEXT=(.+)$')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    $inline = [regex]::Match($blob, '(?m)(?:^|\s)NEXT=(.+)$')
    if ($inline.Success) { return $inline.Groups[1].Value.Trim() }
    $nextAction = [regex]::Match($blob, '(?m)^NEXT_ACTION=(.+)$')
    if ($nextAction.Success) { return $nextAction.Groups[1].Value.Trim() }
    return $null
}

function Get-StatusFromEvidence {
    param([Parameter(Mandatory = $true)]$Attempt)
    $blob = Get-AttemptEvidenceBlob -Attempt $Attempt
    $matches = [regex]::Matches($blob, '(?m)^STATUS=(.+)$')
    if ($matches.Count -gt 0) {
        return $matches[$matches.Count - 1].Groups[1].Value.Trim()
    }
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
    # Child exit 124 is a hung prerequisite (WSL/sudo/apt/harness), not a harness-contract fail.
    $contractStatus = if ($contract.ExitCode -eq 124) {
        'BLOCKED_PREREQUISITE_TIMEOUT'
    } else {
        'BLOCKED_HARNESS_CONTRACT'
    }
    $contractNext = if ($contract.ExitCode -eq 124) {
        'repair hung WSL/sudo/apt/harness prerequisite or increase host capacity, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1; contract step timed out'
    } else {
        'inspect contract evidence under EVIDENCE_ROOT; repair FirstMate harness contract failure, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
    }
    Set-Content -LiteralPath $receiptPath -Value @(
        "HEAD=$actualHead"
        "WSL_DISTRIBUTION=$WslDistribution"
        "EVIDENCE_ROOT=$EvidenceRoot"
        "STEPS=$($steps -join ',')"
        "FINAL_EXIT=$finalExit"
        'RESULT=CONTRACT_FAILED'
        "STATUS=$contractStatus"
        'LIVE_RUNTIME_PROOF=UNPROVEN'
    )
    Write-Host "STATUS=$contractStatus"
    Write-Host 'RESULT=CONTRACT_FAILED'
    Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
    Write-Host "NEXT=$contractNext"
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
    } elseif ($continue.ExitCode -eq 51) {
        'BLOCKED_WSL_BOOTSTRAP'
    } elseif ($continue.ExitCode -eq 52) {
        'BLOCKED_HARNESS_CONTRACT'
    } elseif ($continue.ExitCode -eq 124) {
        'BLOCKED_PREREQUISITE_TIMEOUT'
    } else {
        # Prefer child STATUS=BLOCKED_* (e.g. BLOCKED_CONTINUATION_EXHAUSTED) over generic continue-fail.
        $preservedStatus = Get-StatusFromEvidence -Attempt $continue
        if (-not [string]::IsNullOrWhiteSpace($preservedStatus) -and $preservedStatus -match '^BLOCKED_') {
            $preservedStatus
        } else {
            'PHYSICAL_FLOOR_CONTINUE_FAILED'
        }
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
    Write-Host "STATUS=$result"
    Write-Host "RESULT=$result"
    # Prefer child NEXT= (includes checkout/object-vs-contract distinction and
    # -FirstMatePath-specific guidance) over generic fallbacks.
    $preservedNext = Get-OperatorNextFromEvidence -Attempt $continue
    if (-not [string]::IsNullOrWhiteSpace($preservedNext)) {
        Write-Host "NEXT=$preservedNext"
    } elseif ($continue.ExitCode -eq 45) {
        Write-Host 'NEXT=export PATH="$HOME/.local/bin:$PATH"; gh auth login --hostname github.com --git-protocol https --web inside Ubuntu, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
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
        Write-Host 'NEXT=verify the selected FirstMate checkout/object database; if the audited commit is healthy but a required path is absent, repair tooling/firstmate/harness/integration-contract.json and tooling/firstmate/harness/upstream-pin.json (or refresh the audited pin); do not retry the same SHA blindly; then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
    } elseif ($continue.ExitCode -eq 51) {
        Write-Host 'NEXT=inspect WSL diagnostics/bootstrap stdout; repair exact-head WSL clone/source-repo access, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
    } elseif ($continue.ExitCode -eq 52) {
        Write-Host 'NEXT=inspect evidence root; repair FirstMate harness contract failure inside Ubuntu, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
    } elseif ($continue.ExitCode -eq 124) {
        Write-Host 'NEXT=repair hung WSL/sudo/apt prerequisite or increase host capacity, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1; a prerequisite step timed out'
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
        # Child exit 124 is a hung prerequisite (WSL/sudo/apt/harness), not a protected-control regression label.
        $protectedStatus = if ($protected.ExitCode -eq 124) {
            'BLOCKED_PREREQUISITE_TIMEOUT'
        } else {
            'BLOCKED_PROTECTED_CONTROL'
        }
        $protectedResult = if ($protected.ExitCode -eq 124) {
            'BLOCKED_PREREQUISITE_TIMEOUT'
        } else {
            'PROTECTED_CONTROL_FAILED'
        }
        $protectedNext = if ($protected.ExitCode -eq 124) {
            'repair hung WSL/sudo/apt prerequisite or increase host capacity, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1; protected physical-floor step timed out after continuation PASS'
        } else {
            'continuation PASS then protected physical-floor failed; inspect evidence under EVIDENCE_ROOT for regression, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1'
        }
        Set-Content -LiteralPath $receiptPath -Value @(
            "HEAD=$actualHead"
            "WSL_DISTRIBUTION=$WslDistribution"
            "EVIDENCE_ROOT=$EvidenceRoot"
            "STEPS=$($steps -join ',')"
            "FINAL_EXIT=$finalExit"
            "RESULT=$protectedResult"
            "STATUS=$protectedStatus"
            'LIVE_RUNTIME_PROOF=UNPROVEN'
            'NOTE=continuation PASS then protected-control failure; investigate regression'
            'RECEIPT_PATH=' + $receiptPath
        )
        Write-Host "RECEIPT_PATH=$receiptPath"
        Write-Host "STATUS=$protectedStatus"
        Write-Host "RESULT=$protectedResult"
        Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
        Write-Host "NEXT=$protectedNext"
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
