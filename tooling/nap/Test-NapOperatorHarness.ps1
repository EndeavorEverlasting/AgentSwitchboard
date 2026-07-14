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

    $operatorSummaryFile = Get-ChildItem -LiteralPath $operatorEvidence -Filter "operator-summary.json" -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    Add-Result -Passed ($null -ne $operatorSummaryFile) -Name "missing-config/operator-summary" -FailureMessage "operator-summary.json was not produced"

    if ($operatorSummaryFile) {
        $summary = Get-Content -LiteralPath $operatorSummaryFile.FullName -Raw | ConvertFrom-Json
        Add-Result -Passed ([string]$summary.status -eq "blocked") -Name "missing-config/status" -FailureMessage "expected blocked, found '$($summary.status)'"
        Add-Result -Passed ([string]$summary.failureCode -eq "NAP-CONFIG") -Name "missing-config/failure-code" -FailureMessage "expected NAP-CONFIG, found '$($summary.failureCode)'"
        Add-Result -Passed (-not [string]::IsNullOrWhiteSpace([string]$summary.nextAction)) -Name "missing-config/next-action" -FailureMessage "nextAction is blank"
        Add-Result -Passed ([bool]$summary.retryable) -Name "missing-config/retryable" -FailureMessage "configuration failure should be retryable"
        Add-Result -Passed (Test-Path -LiteralPath ([string]$summary.consoleLogPath) -PathType Leaf) -Name "missing-config/technician-log" -FailureMessage "technician console log is missing"
    }

    $leftoverPrompt = Get-ChildItem -LiteralPath $tempRoot -Filter "sprint-prompt.md" -File -Recurse -ErrorAction SilentlyContinue
    Add-Result -Passed (@($leftoverPrompt).Count -eq 0) -Name "missing-config/no-prompt-artifact" -FailureMessage "an ephemeral prompt file was left behind"
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
