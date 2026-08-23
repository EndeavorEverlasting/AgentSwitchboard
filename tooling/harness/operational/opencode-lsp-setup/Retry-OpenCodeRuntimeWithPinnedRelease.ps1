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

function Get-LatestRuntimeReceiptPath {
    param([Parameter(Mandatory)][string]$RunsRoot)

    $item = @(
        Get-ChildItem -LiteralPath $RunsRoot -Filter 'opencode-runtime-recovery.json' -File -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
    )
    if ($item.Count -eq 0) { return $null }
    return [string]$item[0].FullName
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$FailureCode)
    try {
        return Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Stop-Retry $FailureCode "Machine-local retry evidence could not be parsed: $Path"
    }
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

$runtimeRunsRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\opencode-lsp\runs'
$latestReceiptPath = Get-LatestRuntimeReceiptPath -RunsRoot $runtimeRunsRoot
if ([string]::IsNullOrWhiteSpace([string]$latestReceiptPath)) {
    Stop-Retry 'OPENCODE_PINNED_RETRY_RECEIPT_MISSING' 'No prior OpenCode runtime-recovery receipt was found; this retry is only valid after a proven installer failure.'
}
$priorReceipt = Read-JsonFile -Path $latestReceiptPath -FailureCode 'OPENCODE_PINNED_RETRY_RECEIPT_INVALID'
$priorRunId = [string]$priorReceipt.runId
if ([string]::IsNullOrWhiteSpace($priorRunId)) {
    Stop-Retry 'OPENCODE_PINNED_RETRY_RECEIPT_INVALID' 'The latest OpenCode runtime-recovery receipt did not contain a runId.'
}

foreach ($attemptFile in @(
    Get-ChildItem -LiteralPath $runtimeRunsRoot -Filter 'opencode-release-pinned-retry.json' -File -Recurse -ErrorAction SilentlyContinue
)) {
    try { $attempt = Get-Content -LiteralPath $attemptFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop }
    catch { continue }
    if ([string]$attempt.sourceRunId -eq $priorRunId -or [string]$attempt.resultRunId -eq $priorRunId) {
        Stop-Retry 'OPENCODE_PINNED_RETRY_ALREADY_ATTEMPTED' "The latest runtime-recovery run '$priorRunId' is already bound to a release-pinned retry attempt."
    }
}

if ([string]$priorReceipt.failureCode -ne 'OPENCODE_POST_INSTALL_MISSING' -or
    -not [bool]$priorReceipt.installAttempted -or
    $null -eq $priorReceipt.installerExitCode -or
    [int]$priorReceipt.installerExitCode -eq 0) {
    Stop-Retry 'OPENCODE_PINNED_RETRY_NOT_APPLICABLE' 'Release-pinned retry requires the latest receipt to prove a nonzero installer exit followed by OPENCODE_POST_INSTALL_MISSING.'
}

$releaseApiUrl = 'https://api.github.com/repos/anomalyco/opencode/releases/latest'
$headers = @{
    'Accept' = 'application/vnd.github+json'
    'User-Agent' = 'AgentSwitchboard-OpenCodePinnedRetry'
}
try {
    $release = Invoke-RestMethod -Uri $releaseApiUrl -Headers $headers -Method Get -TimeoutSec $NetworkTimeoutSeconds -ErrorAction Stop
}
catch {
    Stop-Retry 'OPENCODE_RELEASE_DISCOVERY_FAILED' "Windows host could not resolve OpenCode release metadata within the bounded $NetworkTimeoutSeconds-second window."
}

$tag = [string]$release.tag_name
if ($tag -notmatch '^v(?<version>[0-9]+(?:\.[0-9]+){2}(?:-[0-9A-Za-z.-]+)?)$') {
    Stop-Retry 'OPENCODE_RELEASE_TAG_INVALID' 'OpenCode latest-release metadata returned an unsupported release tag.'
}
$selectedVersion = [string]$Matches['version']

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

$attemptPath = Join-Path (Split-Path -Parent $latestReceiptPath) 'opencode-release-pinned-retry.json'
if (Test-Path -LiteralPath $attemptPath) {
    Stop-Retry 'OPENCODE_PINNED_RETRY_ALREADY_ATTEMPTED' "The source runtime-recovery run '$priorRunId' already contains a release-pinned retry attempt receipt."
}
$attemptReceipt = [ordered]@{
    schema = 'agentswitchboard.opencode-release-pinned-retry.v1'
    sourceRunId = $priorRunId
    selectedVersion = $selectedVersion
    releaseSelectionOwner = 'windows-github-api'
    attemptedAt = [DateTime]::UtcNow.ToString('o')
    resultRunId = $null
    status = 'started'
    secretOrEnvironmentDumpPersisted = $false
}
$attemptReceipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $attemptPath -Encoding utf8NoBOM

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
    Write-Host "OPENCODE_PINNED_RETRY_PRIOR_RECEIPT=$latestReceiptPath"
    Write-Host "OPENCODE_PINNED_RETRY_ATTEMPT_RECEIPT=$attemptPath"
    Write-Host "OPENCODE_PINNED_RETRY_RELEASE=$selectedVersion"
    Write-Host 'OPENCODE_PINNED_RETRY_RELEASE_SOURCE=windows-github-api'
    & ([scriptblock]::Create($bootstrapText)) -ModelId $ModelId -Distribution $Distribution -InstallTimeoutSeconds $InstallTimeoutSeconds -NetworkTimeoutSeconds $NetworkTimeoutSeconds
}
finally {
    $resultReceiptPath = Get-LatestRuntimeReceiptPath -RunsRoot $runtimeRunsRoot
    if (-not [string]::IsNullOrWhiteSpace([string]$resultReceiptPath) -and
        -not [string]::Equals($resultReceiptPath, $latestReceiptPath, [StringComparison]::OrdinalIgnoreCase)) {
        try {
            $resultReceipt = Get-Content -LiteralPath $resultReceiptPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $attemptReceipt.resultRunId = [string]$resultReceipt.runId
            $attemptReceipt.status = 'completed-with-runtime-receipt'
        }
        catch {
            $attemptReceipt.status = 'completed-with-unreadable-runtime-receipt'
        }
    }
    else {
        $attemptReceipt.status = 'completed-without-new-runtime-receipt'
    }
    $attemptReceipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $attemptPath -Encoding utf8NoBOM

    if ($hadVersion) { $env:VERSION = $priorVersion } else { Remove-Item Env:VERSION -ErrorAction SilentlyContinue }
    if ($hadWslEnv) { $env:WSLENV = $priorWslEnv } else { Remove-Item Env:WSLENV -ErrorAction SilentlyContinue }
}
