[CmdletBinding()]
param(
    [string]$ModelId = 'opencode/nemotron-3-ultra-free',
    [string]$Distribution = 'Ubuntu',
    [ValidateRange(30, 900)][int]$InstallTimeoutSeconds = 180,
    [ValidateRange(5, 120)][int]$NetworkTimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

function Stop-Retry {
    param([Parameter(Mandatory)][string]$Code, [Parameter(Mandatory)][string]$Message)
    throw ([InvalidOperationException]::new("$Code|$Message"))
}

function Get-RuntimeReceiptsForDistribution {
    param(
        [Parameter(Mandatory)][string]$RunsRoot,
        [Parameter(Mandatory)][string]$RequestedDistribution
    )

    $matches = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @(
        Get-ChildItem -LiteralPath $RunsRoot -Filter 'opencode-runtime-recovery.json' -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending
    )) {
        try { $receipt = Get-Content -LiteralPath $item.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
        catch { continue }
        $receiptDistribution = if ($receipt.PSObject.Properties.Name -contains 'distribution') { [string]$receipt.distribution } else { '' }
        if (-not [string]::Equals($receiptDistribution, $RequestedDistribution, [StringComparison]::OrdinalIgnoreCase)) { continue }
        [void]$matches.Add([pscustomobject]@{
            Path = [string]$item.FullName
            Receipt = $receipt
            LastWriteTimeUtc = $item.LastWriteTimeUtc
        })
    }
    return @($matches)
}

function Get-RetryAttemptsForSourceRun {
    param(
        [Parameter(Mandatory)][string]$RunsRoot,
        [Parameter(Mandatory)][string]$SourceRunId
    )

    $matches = [System.Collections.Generic.List[object]]::new()
    foreach ($item in @(
        Get-ChildItem -LiteralPath $RunsRoot -Filter 'opencode-release-pinned-retry.json' -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending
    )) {
        try { $attempt = Get-Content -LiteralPath $item.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
        catch { continue }
        $attemptSourceRunId = if ($attempt.PSObject.Properties.Name -contains 'sourceRunId') { [string]$attempt.sourceRunId } else { '' }
        if ($attemptSourceRunId -ne $SourceRunId) { continue }
        [void]$matches.Add([pscustomobject]@{
            Path = [string]$item.FullName
            Attempt = $attempt
            LastWriteTimeUtc = $item.LastWriteTimeUtc
        })
    }
    return @($matches)
}

function Test-AttemptConsumed {
    param([Parameter(Mandatory)]$Attempt)

    $status = if ($Attempt.PSObject.Properties.Name -contains 'status') { [string]$Attempt.status } else { '' }
    $resultRunId = if ($Attempt.PSObject.Properties.Name -contains 'resultRunId') { [string]$Attempt.resultRunId } else { '' }
    $resultRunIds = if ($Attempt.PSObject.Properties.Name -contains 'resultRunIds') { @($Attempt.resultRunIds | ForEach-Object { [string]$_ }) } else { @() }
    return ($status -eq 'dispatched' -or $status -like 'completed-*' -or -not [string]::IsNullOrWhiteSpace($resultRunId) -or $resultRunIds.Count -gt 0)
}

function Resolve-OpenCodeReleaseVersion {
    param(
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][hashtable]$Headers
    )

    $releaseRedirectUrl = 'https://github.com/anomalyco/opencode/releases/latest'
    try {
        $redirectResponse = Invoke-WebRequest -Uri $releaseRedirectUrl -Headers $Headers -Method Get -MaximumRedirection 5 -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        $finalUri = [string]$redirectResponse.BaseResponse.RequestMessage.RequestUri.AbsoluteUri
        if ($finalUri -match '^https://github\.com/anomalyco/opencode/releases/tag/v(?<version>[0-9]+(?:\.[0-9]+){2}(?:-[0-9A-Za-z.-]+)?)/?$') {
            return [pscustomobject]@{
                Version = [string]$Matches['version']
                Source = 'windows-github-release-redirect'
            }
        }
    }
    catch {
        # The REST fallback below is separately bounded and persists no raw network error.
    }

    $releaseApiUrl = 'https://api.github.com/repos/anomalyco/opencode/releases/latest'
    try {
        $release = Invoke-RestMethod -Uri $releaseApiUrl -Headers $Headers -Method Get -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        $tag = [string]$release.tag_name
        if ($tag -match '^v(?<version>[0-9]+(?:\.[0-9]+){2}(?:-[0-9A-Za-z.-]+)?)$') {
            return [pscustomobject]@{
                Version = [string]$Matches['version']
                Source = 'windows-github-api'
            }
        }
    }
    catch {
        # Fall through to one typed failure after both official GitHub surfaces fail.
    }

    Stop-Retry 'OPENCODE_RELEASE_DISCOVERY_FAILED' "Windows host could not resolve OpenCode release metadata from either official GitHub surface within bounded $TimeoutSeconds-second requests."
}

function Release-OwnedPreDispatchClaim {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$RetryRunId
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    try { $claim = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { return }
    if ($claim.PSObject.Properties.Name -notcontains 'retryRunId') { return }
    if ([string]$claim.retryRunId -ne $RetryRunId) { return }
    Remove-Item -LiteralPath $Path -Force -ErrorAction Stop
}

if ($env:OS -ne 'Windows_NT') {
    Stop-Retry 'OPENCODE_PINNED_RETRY_WINDOWS_ONLY' 'The release-pinned OpenCode retry is Windows-only.'
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Stop-Retry 'OPENCODE_PINNED_RETRY_PWSH_REQUIRED' 'The release-pinned OpenCode retry requires PowerShell 7.'
}
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
    Stop-Retry 'OPENCODE_PINNED_RETRY_LOCALAPPDATA_REQUIRED' 'LOCALAPPDATA is required to bind the retry to preserved runtime-recovery evidence.'
}
if ([string]::IsNullOrWhiteSpace($Distribution)) {
    Stop-Retry 'OPENCODE_PINNED_RETRY_DISTRIBUTION_REQUIRED' 'A WSL distribution is required to select matching runtime-recovery evidence.'
}

$stateRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\opencode-lsp'
$runtimeRunsRoot = Join-Path $stateRoot 'runs'
$distributionReceipts = @(Get-RuntimeReceiptsForDistribution -RunsRoot $runtimeRunsRoot -RequestedDistribution $Distribution)
if ($distributionReceipts.Count -eq 0) {
    Stop-Retry 'OPENCODE_PINNED_RETRY_RECEIPT_MISSING' "No prior OpenCode runtime-recovery receipt was found for distribution '$Distribution'."
}
$selectedEvidence = $distributionReceipts[0]
$latestReceiptPath = [string]$selectedEvidence.Path
$priorReceipt = $selectedEvidence.Receipt
$priorRunId = [string]$priorReceipt.runId
if ($priorRunId -notmatch '^[A-Za-z0-9-]+$') {
    Stop-Retry 'OPENCODE_PINNED_RETRY_RECEIPT_INVALID' 'The selected OpenCode runtime-recovery receipt did not contain a safe runId.'
}
if (-not [string]::Equals([string]$priorReceipt.distribution, $Distribution, [StringComparison]::OrdinalIgnoreCase)) {
    Stop-Retry 'OPENCODE_PINNED_RETRY_DISTRIBUTION_MISMATCH' 'The selected runtime-recovery receipt does not match the requested WSL distribution.'
}
if ([string]$priorReceipt.failureCode -ne 'OPENCODE_POST_INSTALL_MISSING' -or
    -not [bool]$priorReceipt.installAttempted -or
    $null -eq $priorReceipt.installerExitCode -or
    [int]$priorReceipt.installerExitCode -eq 0) {
    Stop-Retry 'OPENCODE_PINNED_RETRY_NOT_APPLICABLE' "Release-pinned retry requires the latest '$Distribution' receipt to prove a nonzero installer exit followed by OPENCODE_POST_INSTALL_MISSING."
}

$claimRoot = Join-Path $stateRoot 'retry-claims'
$null = New-Item -ItemType Directory -Path $claimRoot -Force
$claimPath = Join-Path $claimRoot "$priorRunId.claim"
$claimLeaseSeconds = (3 * $NetworkTimeoutSeconds) + 30
$existingAttempts = @(Get-RetryAttemptsForSourceRun -RunsRoot $runtimeRunsRoot -SourceRunId $priorRunId)
foreach ($attemptEvidence in $existingAttempts) {
    if (Test-AttemptConsumed -Attempt $attemptEvidence.Attempt) {
        Stop-Retry 'OPENCODE_PINNED_RETRY_ALREADY_ATTEMPTED' "The latest '$Distribution' runtime-recovery run '$priorRunId' is already bound to a dispatched release-pinned retry attempt."
    }
}

if (Test-Path -LiteralPath $claimPath -PathType Leaf) {
    $claimItem = Get-Item -LiteralPath $claimPath -ErrorAction Stop
    $claimAgeSeconds = ([DateTime]::UtcNow - $claimItem.LastWriteTimeUtc).TotalSeconds
    if ($claimAgeSeconds -lt $claimLeaseSeconds) {
        Stop-Retry 'OPENCODE_PINNED_RETRY_ALREADY_ATTEMPTED' "The '$Distribution' runtime-recovery run '$priorRunId' has an active pre-dispatch retry claim."
    }

    $latestPreDispatchAttempt = $existingAttempts | Select-Object -First 1
    if ($null -ne $latestPreDispatchAttempt) {
        $abandoned = $latestPreDispatchAttempt.Attempt
        if (-not (Test-AttemptConsumed -Attempt $abandoned)) {
            $abandoned.status = 'abandoned-before-dispatch'
            if ($abandoned.PSObject.Properties.Name -contains 'abandonedAt') {
                $abandoned.abandonedAt = [DateTime]::UtcNow.ToString('o')
            }
            else {
                $abandoned | Add-Member -NotePropertyName abandonedAt -NotePropertyValue ([DateTime]::UtcNow.ToString('o'))
            }
            $abandoned | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $latestPreDispatchAttempt.Path -Encoding utf8NoBOM
        }
    }
    Remove-Item -LiteralPath $claimPath -Force -ErrorAction Stop
    Write-Host "OPENCODE_PINNED_RETRY_RECOVERED_PREDISPATCH_CLAIM=$priorRunId"
}

$retryRunId = '{0}-{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')), ([guid]::NewGuid().ToString('N').Substring(0,8))
$claimPayload = [ordered]@{
    schema = 'agentswitchboard.opencode-release-pinned-retry-claim.v2'
    sourceRunId = $priorRunId
    retryRunId = $retryRunId
    distribution = $Distribution
    claimedAt = [DateTime]::UtcNow.ToString('o')
    leaseSeconds = $claimLeaseSeconds
    dispatchStarted = $false
    secretOrEnvironmentDumpPersisted = $false
} | ConvertTo-Json -Compress
$claimBytes = [Text.Encoding]::UTF8.GetBytes($claimPayload)
try {
    $claimStream = [IO.File]::Open($claimPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $claimStream.Write($claimBytes, 0, $claimBytes.Length) }
    finally { $claimStream.Dispose() }
}
catch [IO.IOException] {
    Stop-Retry 'OPENCODE_PINNED_RETRY_ALREADY_ATTEMPTED' "The '$Distribution' runtime-recovery run '$priorRunId' already has an atomic retry claim."
}

$retryRunRoot = Join-Path $runtimeRunsRoot $retryRunId
$null = New-Item -ItemType Directory -Path $retryRunRoot -Force
$attemptPath = Join-Path $retryRunRoot 'opencode-release-pinned-retry.json'
$attemptReceipt = [ordered]@{
    schema = 'agentswitchboard.opencode-release-pinned-retry.v1'
    retryRunId = $retryRunId
    sourceRunId = $priorRunId
    distribution = $Distribution
    selectedVersion = $null
    releaseSelectionOwner = $null
    attemptedAt = [DateTime]::UtcNow.ToString('o')
    abandonedAt = $null
    preDispatchFailureCode = $null
    resultRunId = $null
    resultRunIds = @()
    status = 'claimed'
    secretOrEnvironmentDumpPersisted = $false
}
$attemptReceipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $attemptPath -Encoding utf8NoBOM

$headers = @{
    'Accept' = 'application/vnd.github+json'
    'User-Agent' = 'AgentSwitchboard-OpenCodePinnedRetry'
}
$dispatchStarted = $false
try {
    try {
        $releaseSelection = Resolve-OpenCodeReleaseVersion -TimeoutSeconds $NetworkTimeoutSeconds -Headers $headers
        $selectedVersion = [string]$releaseSelection.Version
        $releaseSelectionOwner = [string]$releaseSelection.Source
        $attemptReceipt.selectedVersion = $selectedVersion
        $attemptReceipt.releaseSelectionOwner = $releaseSelectionOwner
        $attemptReceipt.status = 'release-selected'
        $attemptReceipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $attemptPath -Encoding utf8NoBOM

        $bootstrapApiUrl = 'https://api.github.com/repos/EndeavorEverlasting/AgentSwitchboard/contents/tooling/harness/operational/opencode-lsp-setup/Invoke-AgentSwitchboardOpenCodeBootstrap.ps1'
        try {
            $bootstrapResponse = Invoke-RestMethod -Uri $bootstrapApiUrl -Headers $headers -Method Get -TimeoutSec $NetworkTimeoutSeconds -ErrorAction Stop
        }
        catch {
            Stop-Retry 'OPENCODE_PINNED_RETRY_BOOTSTRAP_FETCH_FAILED' "Windows host could not fetch the canonical AgentSwitchboard bootstrap within the bounded $NetworkTimeoutSeconds-second window."
        }
        if ([string]$bootstrapResponse.encoding -ne 'base64' -or [string]::IsNullOrWhiteSpace([string]$bootstrapResponse.content)) {
            Stop-Retry 'OPENCODE_PINNED_RETRY_BOOTSTRAP_INVALID' 'Canonical bootstrap content was missing or not base64 encoded.'
        }
        try {
            $bootstrapText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(([string]$bootstrapResponse.content -replace '\s','')))
        }
        catch {
            Stop-Retry 'OPENCODE_PINNED_RETRY_BOOTSTRAP_INVALID' 'Canonical bootstrap content could not be decoded.'
        }

        $currentEvidence = @(Get-RuntimeReceiptsForDistribution -RunsRoot $runtimeRunsRoot -RequestedDistribution $Distribution)
        if ($currentEvidence.Count -eq 0 -or [string]$currentEvidence[0].Receipt.runId -ne $priorRunId) {
            Stop-Retry 'OPENCODE_PINNED_RETRY_SOURCE_STALE' "A newer '$Distribution' runtime-recovery receipt appeared after retry claim; installer dispatch was refused."
        }
        $preexistingRunIds = @($currentEvidence | ForEach-Object { [string]$_.Receipt.runId } | Where-Object { $_ })
    }
    catch {
        $failureText = [string]$_.Exception.Message
        $failureCode = if ($failureText -match '^([^|]+)\|') { [string]$Matches[1] } else { 'OPENCODE_PINNED_RETRY_PREDISPATCH_FAILED' }
        $attemptReceipt.status = 'pre-dispatch-failed'
        $attemptReceipt.preDispatchFailureCode = $failureCode
        $attemptReceipt.abandonedAt = [DateTime]::UtcNow.ToString('o')
        $attemptReceipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $attemptPath -Encoding utf8NoBOM
        Release-OwnedPreDispatchClaim -Path $claimPath -RetryRunId $retryRunId
        throw
    }

    $hadVersion = Test-Path Env:VERSION
    $priorVersion = if ($hadVersion) { [string]$env:VERSION } else { $null }
    $hadWslEnv = Test-Path Env:WSLENV
    $priorWslEnv = if ($hadWslEnv) { [string]$env:WSLENV } else { $null }
    $wslEntries = @()
    if (-not [string]::IsNullOrWhiteSpace($priorWslEnv)) {
        $wslEntries = @($priorWslEnv -split ':' | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and
            -not [string]::Equals((($_ -split '/', 2)[0]), 'VERSION', [StringComparison]::OrdinalIgnoreCase)
        })
    }
    $wslEntries += 'VERSION'

    try {
        $env:VERSION = $selectedVersion
        $env:WSLENV = ($wslEntries -join ':')
        $dispatchStarted = $true
        $attemptReceipt.status = 'dispatched'
        $attemptReceipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $attemptPath -Encoding utf8NoBOM
        Write-Host "OPENCODE_PINNED_RETRY_PRIOR_RECEIPT=$latestReceiptPath"
        Write-Host "OPENCODE_PINNED_RETRY_ATTEMPT_RECEIPT=$attemptPath"
        Write-Host "OPENCODE_PINNED_RETRY_RELEASE=$selectedVersion"
        Write-Host "OPENCODE_PINNED_RETRY_RELEASE_SOURCE=$releaseSelectionOwner"
        & ([scriptblock]::Create($bootstrapText)) -ModelId $ModelId -Distribution $Distribution -InstallTimeoutSeconds $InstallTimeoutSeconds -NetworkTimeoutSeconds $NetworkTimeoutSeconds
    }
    finally {
        $postReceipts = @(Get-RuntimeReceiptsForDistribution -RunsRoot $runtimeRunsRoot -RequestedDistribution $Distribution)
        $newRunIds = @($postReceipts | ForEach-Object { [string]$_.Receipt.runId } | Where-Object { $_ -and $_ -notin $preexistingRunIds } | Select-Object -Unique)
        $attemptReceipt.resultRunIds = $newRunIds
        if ($newRunIds.Count -eq 1) {
            $attemptReceipt.resultRunId = $newRunIds[0]
            $attemptReceipt.status = 'completed-with-runtime-receipt'
        }
        elseif ($newRunIds.Count -gt 1) {
            $attemptReceipt.status = 'completed-with-ambiguous-runtime-receipts'
        }
        else {
            $attemptReceipt.status = 'completed-without-new-runtime-receipt'
        }
        $attemptReceipt | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $attemptPath -Encoding utf8NoBOM

        if ($hadVersion) { $env:VERSION = $priorVersion } else { Remove-Item Env:VERSION -ErrorAction SilentlyContinue }
        if ($hadWslEnv) { $env:WSLENV = $priorWslEnv } else { Remove-Item Env:WSLENV -ErrorAction SilentlyContinue }
    }
}
finally {
    if (-not $dispatchStarted) {
        Release-OwnedPreDispatchClaim -Path $claimPath -RetryRunId $retryRunId
    }
}
