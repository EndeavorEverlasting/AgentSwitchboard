[CmdletBinding()]
param(
    [string]$RootPath = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Add-Check {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [string]$FailureMessage = "contract failed"
    )
    if ($Passed) {
        [void]$passes.Add($Name)
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    else {
        [void]$failures.Add("$Name`: $FailureMessage")
        Write-Host "[FAIL] $Name - $FailureMessage" -ForegroundColor Red
    }
}

$scriptPath = Join-Path $RootPath "Start-DeepSeekGnhfLiveProof.ps1"
Add-Check -Passed (Test-Path -LiteralPath $scriptPath -PathType Leaf) -Name "required-file/live-proof-script"

if (Test-Path -LiteralPath $scriptPath -PathType Leaf) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $scriptPath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    Add-Check -Passed ($parseErrors.Count -eq 0) -Name "powershell-parse/live-proof-script" -FailureMessage (($parseErrors | ForEach-Object Message) -join "; ")

    $text = Get-Content -LiteralPath $scriptPath -Raw
    Add-Check -Passed ($text.Contains('deepseek/deepseek-v4-pro')) -Name "deepseek/current-pro-model-default"
    Add-Check -Passed ($text.Contains('@("auth", "list")')) -Name "preflight/authentication-readiness"
    Add-Check -Passed ($text.Contains('@("models", "deepseek", "--refresh")')) -Name "preflight/exact-model-discovery"
    Add-Check -Passed ($text.Contains('OPENCODE_CONFIG_CONTENT')) -Name "runtime/model-override"
    Add-Check -Passed ($text.Contains('"--model", $ModelId')) -Name "runtime/explicit-model-selection"
    Add-Check -Passed ($text.Contains('AGENTSWITCHBOARD_DEEPSEEK_LIVE_OK')) -Name "runtime/response-marker"
    Add-Check -Passed ($text.Contains('activationState = "observed-response"')) -Name "runtime/activation-evidence"
    Add-Check -Passed ($text.Contains('live-provider-response-observed') -and $text.Contains('live-gnhf-behavior-observed')) -Name "proof-level/no-inflation"
    Add-Check -Passed ($text.Contains('TimeoutSeconds ($TimeoutMinutes * 60)')) -Name "runtime/bounded-wait"
    Add-Check -Passed ($text.Contains('$process.Kill($true)')) -Name "runtime/process-tree-termination"
    Add-Check -Passed ($text.Contains('Disposable DeepSeek GNHF live proof')) -Name "safety/disposable-repository"
    Add-Check -Passed ($text.Contains('personalDataMutation = $false')) -Name "safety/no-personal-data-mutation"
    Add-Check -Passed (-not $text.Contains('DEEPSEEK_API_KEY') -and -not $text.Contains('sk-')) -Name "safety/no-secret-handling"
    Add-Check -Passed (-not $text.Contains('--push') -and -not $text.Contains('git push') -and -not $text.Contains('git merge')) -Name "safety/no-push-merge"
    Add-Check -Passed ($text.Contains('deepseek-live-proof.json') -and $text.Contains('@("show", "--name-only", "--format=", "HEAD")')) -Name "runtime/behavior-and-commit-observation"
    Add-Check -Passed ($text.Contains('launcher-summary.json') -and $text.Contains('model-activation.json')) -Name "runtime/artifact-chain"
}

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "Result: $($passes.Count) passed / $($failures.Count) failed" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}

Write-Host "Result: $($passes.Count) passed / 0 failed" -ForegroundColor Green
exit 0
