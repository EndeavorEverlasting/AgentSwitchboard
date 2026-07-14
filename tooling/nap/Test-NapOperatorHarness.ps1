[CmdletBinding()]
param(
    [string]$RootPath = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$wrapperPath = Join-Path $RootPath "Invoke-NapSprintSafely.ps1"
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("AgentSwitchboard-NapHarness-" + [Guid]::NewGuid().ToString("N"))
$oldLocalAppData = $env:LOCALAPPDATA

function Add-Result {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [string]$FailureMessage = ""
    )

    if ($Passed) {
        [void]$passes.Add($Name)
    }
    else {
        [void]$failures.Add("$Name`: $FailureMessage")
    }
}

function Get-LatestOperatorSummary {
    param([Parameter(Mandatory)][string]$EvidencePath)

    return Get-ChildItem -LiteralPath $EvidencePath -Filter "operator-summary.json" -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $env:LOCALAPPDATA = Join-Path $tempRoot "LocalAppData"
    New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force | Out-Null

    $missingConfig = Join-Path $tempRoot "missing\nap-sprint.json"
    $operatorEvidence = Join-Path $tempRoot "operator-runs"
    $harnessOutput = Join-Path $tempRoot "harness-console.log"

    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $wrapperPath `
        -ConfigPath $missingConfig `
        -EvidenceRoot $operatorEvidence *> $harnessOutput
    $exitCode = $LASTEXITCODE

    Add-Result -Passed ($exitCode -ne 0) -Name "missing-config/nonzero-exit" -FailureMessage "wrapper unexpectedly returned zero"

    $operatorSummaryFile = Get-LatestOperatorSummary -EvidencePath $operatorEvidence
    Add-Result -Passed ($null -ne $operatorSummaryFile) -Name "missing-config/operator-summary" -FailureMessage "operator-summary.json was not produced"

    if ($operatorSummaryFile) {
        $summary = Get-Content -LiteralPath $operatorSummaryFile.FullName -Raw | ConvertFrom-Json
        Add-Result -Passed ([string]$summary.status -eq "blocked") -Name "missing-config/status" -FailureMessage "expected blocked, found '$($summary.status)'"
        Add-Result -Passed ([string]$summary.failureCode -eq "NAP-CONFIG") -Name "missing-config/failure-code" -FailureMessage "expected NAP-CONFIG, found '$($summary.failureCode)'"
        Add-Result -Passed (-not [string]::IsNullOrWhiteSpace([string]$summary.nextAction)) -Name "missing-config/next-action" -FailureMessage "nextAction is blank"
        Add-Result -Passed ([bool]$summary.retryable) -Name "missing-config/retryable" -FailureMessage "configuration failure should be retryable"
        Add-Result -Passed (Test-Path -LiteralPath ([string]$summary.consoleLogPath) -PathType Leaf) -Name "missing-config/technician-log" -FailureMessage "technician console log is missing"
    }

    $sentinel = "NAP-PROMPT-SENTINEL-" + [Guid]::NewGuid().ToString("N")
    $promptEvidence = Join-Path $tempRoot "prompt-operator-runs"
    $promptHarnessOutput = Join-Path $tempRoot "prompt-harness-console.log"

    & pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $wrapperPath `
        -ConfigPath $missingConfig `
        -Prompt $sentinel `
        -EvidenceRoot $promptEvidence *> $promptHarnessOutput
    $promptExitCode = $LASTEXITCODE

    Add-Result -Passed ($promptExitCode -ne 0) -Name "prompt-boundary/nonzero-exit" -FailureMessage "wrapper unexpectedly returned zero"

    $promptSummaryFile = Get-LatestOperatorSummary -EvidencePath $promptEvidence
    Add-Result -Passed ($null -ne $promptSummaryFile) -Name "prompt-boundary/operator-summary" -FailureMessage "operator-summary.json was not produced"
    if ($promptSummaryFile) {
        $promptSummary = Get-Content -LiteralPath $promptSummaryFile.FullName -Raw | ConvertFrom-Json
        Add-Result -Passed ([string]$promptSummary.promptTransport -eq "ephemeral-file") -Name "prompt-boundary/transport" -FailureMessage "direct prompt was not converted to an ephemeral file"
    }

    $leftoverPrompt = Get-ChildItem -LiteralPath $tempRoot -Filter "*prompt*.md" -File -Recurse -ErrorAction SilentlyContinue
    Add-Result -Passed (@($leftoverPrompt).Count -eq 0) -Name "prompt-boundary/no-prompt-artifact" -FailureMessage "an ephemeral prompt file was left behind"

    $sentinelMatches = Get-ChildItem -LiteralPath $tempRoot -File -Recurse -ErrorAction SilentlyContinue |
        Select-String -SimpleMatch $sentinel -ErrorAction SilentlyContinue
    Add-Result -Passed (@($sentinelMatches).Count -eq 0) -Name "prompt-boundary/no-prompt-text-in-evidence" -FailureMessage "prompt text was persisted in an evidence file"
}
catch {
    [void]$failures.Add("harness/runtime: $($_.Exception.Message)")
}
finally {
    $env:LOCALAPPDATA = $oldLocalAppData
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "NAP OPERATOR FAILURE HARNESS" -ForegroundColor Cyan
foreach ($pass in $passes) {
    Write-Host "[PASS] $pass" -ForegroundColor Green
}
foreach ($failure in $failures) {
    Write-Host "[FAIL] $failure" -ForegroundColor Red
}
Write-Host ""
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)

if ($failures.Count -gt 0) {
    exit 1
}
exit 0
