[CmdletBinding()]
param(
    [string]$ConfigPath,
    [string]$RepoPath,
    [ValidateSet("hermes", "opencode", "goose", "copilot", "agy")]
    [string]$Agent,
    [string]$Prompt,
    [string]$PromptPath,
    [string]$InstallRoot,
    [switch]$PlanOnly,
    [string]$EvidenceRoot = "$env:LOCALAPPDATA\AgentSwitchboard\Nap\operator-runs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NapFailureGuidance {
    param([string]$Text)

    $message = if ([string]::IsNullOrWhiteSpace($Text)) { "The nap sprint stopped without a readable error message." } else { $Text.Trim() }

    switch -Regex ($message) {
        'configuration not found|schemaVersion|repoPath|ConvertFrom-Json|configuration did not complete' {
            return [pscustomobject]@{
                Code = "NAP-CONFIG"
                Message = "The local nap configuration is missing or invalid."
                NextAction = "Double-click Configure-NapSprint.cmd, confirm the repository path, then retry."
                Retryable = $true
            }
        }
        'clipboard|promptSource|prompt path|sprint prompt is empty|prompt is empty' {
            return [pscustomobject]@{
                Code = "NAP-PROMPT"
                Message = "No usable bounded sprint prompt was available."
                NextAction = "Copy the complete sprint prompt to the Windows clipboard, or configure a prompt file, then retry."
                Retryable = $true
            }
        }
        'clean target checkout|not a Git working tree|Detached HEAD|existing GNHF worktree|Launch from a normal base branch|git .* failed' {
            return [pscustomobject]@{
                Code = "NAP-REPOSITORY"
                Message = "The target repository is not safe for unattended work."
                NextAction = "Open the repository, run git status --short, preserve existing work, and retry from a clean attached branch."
                Retryable = $true
            }
        }
        'Fleet state|setup failed|setup script is unavailable|launcher is missing|Rerun Setup-AgentSwitchboard' {
            return [pscustomobject]@{
                Code = "NAP-SETUP"
                Message = "AgentSwitchboard setup is missing or unhealthy."
                NextAction = "Double-click Setup-AgentSwitchboard.cmd, review the setup summary, then retry."
                Retryable = $true
            }
        }
        'No configured agent is ready|Agent .* blocked|authenticate a provider|quota|usage exceeded|rate limit' {
            return [pscustomobject]@{
                Code = "NAP-AGENT"
                Message = "No configured coding agent completed readiness or provider access."
                NextAction = "Run AgentSwitchboard readiness, authenticate the selected provider, or choose another ready agent before retrying."
                Retryable = $true
            }
        }
        'sprint failed|sprint exited|GNHF|worktree' {
            return [pscustomobject]@{
                Code = "NAP-EXECUTION"
                Message = "The bounded coding run started but did not complete successfully."
                NextAction = "Review the linked inner GNHF log and preserve any generated worktree before retrying."
                Retryable = $false
            }
        }
        default {
            return [pscustomobject]@{
                Code = "NAP-INTERNAL"
                Message = "AgentSwitchboard encountered an unexpected local failure."
                NextAction = "Review the technician console log and operator summary before retrying."
                Retryable = $false
            }
        }
    }
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 is required. Run this operator wrapper with pwsh."
}
if ($Prompt -and $PromptPath) {
    throw "Use either -Prompt or -PromptPath, not both."
}

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $EvidenceRoot = Join-Path ([IO.Path]::GetTempPath()) "AgentSwitchboard\Nap\operator-runs"
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$operatorRunRoot = Join-Path $EvidenceRoot $timestamp
New-Item -ItemType Directory -Path $operatorRunRoot -Force | Out-Null
$consoleLogPath = Join-Path $operatorRunRoot "technician-console.log"
$operatorSummaryPath = Join-Path $operatorRunRoot "operator-summary.json"
$startedAt = Get-Date
$innerRunsRoot = Join-Path $env:LOCALAPPDATA "AgentSwitchboard\Nap\runs"
$innerSummaryPath = $null
$wrapperPromptPath = $null
$childExitCode = 70
$failureText = $null
$guidance = $null
$status = "starting"

$summary = [ordered]@{
    schemaVersion = 1
    startedAt = $startedAt.ToString("o")
    completedAt = $null
    status = $status
    childExitCode = $null
    failureCode = $null
    operatorMessage = $null
    nextAction = $null
    retryable = $false
    innerSummaryPath = $null
    consoleLogPath = $consoleLogPath
    argumentCount = 0
    promptTransport = if ($Prompt) { "ephemeral-file" } elseif ($PromptPath) { "file" } else { "configured" }
}

try {
    $launcherPath = Join-Path $PSScriptRoot "Start-AgentSwitchboardNap.ps1"
    if (-not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
        throw "Nap launcher is missing: $launcherPath"
    }

    $childArguments = [System.Collections.Generic.List[string]]::new()
    foreach ($item in @("-NoLogo", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $launcherPath)) {
        [void]$childArguments.Add($item)
    }

    foreach ($parameterName in @("ConfigPath", "RepoPath", "Agent", "InstallRoot")) {
        if ($PSBoundParameters.ContainsKey($parameterName)) {
            [void]$childArguments.Add("-$parameterName")
            [void]$childArguments.Add([string](Get-Variable -Name $parameterName -ValueOnly))
        }
    }

    if ($Prompt) {
        $wrapperPromptPath = Join-Path $operatorRunRoot "operator-prompt.md"
        Set-Content -LiteralPath $wrapperPromptPath -Value $Prompt -Encoding utf8NoBOM
        [void]$childArguments.Add("-PromptPath")
        [void]$childArguments.Add($wrapperPromptPath)
    }
    elseif ($PromptPath) {
        [void]$childArguments.Add("-PromptPath")
        [void]$childArguments.Add($PromptPath)
    }

    if ($PlanOnly) {
        [void]$childArguments.Add("-PlanOnly")
    }
    $summary.argumentCount = $childArguments.Count

    Write-Host "`n=== TECHNICIAN-SAFE NAP SPRINT ===" -ForegroundColor Cyan
    Write-Host "Detailed child output: $consoleLogPath"
    Write-Host "AgentSwitchboard is running the guarded preflight. This window will remain available when it finishes."

    & pwsh @childArguments *> $consoleLogPath
    $childExitCode = $LASTEXITCODE

    if (Test-Path -LiteralPath $innerRunsRoot -PathType Container) {
        $innerSummary = Get-ChildItem -LiteralPath $innerRunsRoot -Filter "nap-summary.json" -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -ge $startedAt.ToUniversalTime().AddSeconds(-2) } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($innerSummary) {
            $innerSummaryPath = $innerSummary.FullName
            try {
                $innerRecord = Get-Content -LiteralPath $innerSummaryPath -Raw | ConvertFrom-Json
                if ($innerRecord.failure) {
                    $failureText = [string]$innerRecord.failure
                }
            }
            catch {
                $failureText = "Inner summary could not be parsed: $($_.Exception.Message)"
            }
        }
    }

    if ($childExitCode -eq 0) {
        $status = "completed"
        $summary.status = $status
        $summary.operatorMessage = "The bounded launcher completed. Review the generated worktree and validation evidence before merging."
        $summary.nextAction = "Open the inner nap summary and GNHF log, then inspect the generated branch."
        Write-Host "`n[COMPLETE] $($summary.operatorMessage)" -ForegroundColor Green
    }
    else {
        if ([string]::IsNullOrWhiteSpace($failureText) -and (Test-Path -LiteralPath $consoleLogPath -PathType Leaf)) {
            $failureText = (Get-Content -LiteralPath $consoleLogPath -Tail 40 -ErrorAction SilentlyContinue) -join [Environment]::NewLine
        }
        $guidance = Get-NapFailureGuidance -Text $failureText
        $status = if ($guidance.Code -eq "NAP-EXECUTION") { "failed" } else { "blocked" }
        $summary.status = $status
        $summary.failureCode = $guidance.Code
        $summary.operatorMessage = $guidance.Message
        $summary.nextAction = $guidance.NextAction
        $summary.retryable = $guidance.Retryable

        Write-Host "`n[$($guidance.Code)] $($guidance.Message)" -ForegroundColor Red
        Write-Host "Next action: $($guidance.NextAction)" -ForegroundColor Yellow
    }
}
catch {
    $failureText = $_.Exception.Message
    $guidance = Get-NapFailureGuidance -Text $failureText
    $status = "blocked"
    $summary.status = $status
    $summary.failureCode = $guidance.Code
    $summary.operatorMessage = $guidance.Message
    $summary.nextAction = $guidance.NextAction
    $summary.retryable = $guidance.Retryable
    if ($childExitCode -eq 0) {
        $childExitCode = 70
    }

    try {
        "WRAPPER FAILURE`r`n$($_ | Out-String)" | Set-Content -LiteralPath $consoleLogPath -Encoding utf8NoBOM
    }
    catch {
    }

    Write-Host "`n[$($guidance.Code)] $($guidance.Message)" -ForegroundColor Red
    Write-Host "Next action: $($guidance.NextAction)" -ForegroundColor Yellow
}
finally {
    if ($wrapperPromptPath -and (Test-Path -LiteralPath $wrapperPromptPath -PathType Leaf)) {
        Remove-Item -LiteralPath $wrapperPromptPath -Force -ErrorAction SilentlyContinue
    }

    $summary.completedAt = (Get-Date).ToString("o")
    $summary.childExitCode = $childExitCode
    $summary.innerSummaryPath = $innerSummaryPath

    try {
        $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $operatorSummaryPath -Encoding utf8NoBOM
    }
    catch {
        Write-Host "[WARNING] Could not write the operator summary: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host "Operator summary: $operatorSummaryPath" -ForegroundColor Cyan
Write-Host "Technician log:  $consoleLogPath" -ForegroundColor Cyan
if ($innerSummaryPath) {
    Write-Host "Inner summary:   $innerSummaryPath" -ForegroundColor Cyan
}

exit $childExitCode
