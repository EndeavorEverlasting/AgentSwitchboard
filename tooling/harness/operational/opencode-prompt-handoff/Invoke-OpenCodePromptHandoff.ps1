[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepoPath,
    [string]$PromptPath,
    [string]$Name = 'opencode-prompt-handoff',
    [ValidateRange(1, 100)][int]$MaxIterations = 4,
    [ValidateRange(1, 1000000000)][int]$MaxTokens = 250000,
    [string]$StopWhen = 'The bounded sprint is committed in the isolated worktree, targeted validation passes, and no unrelated files changed.',
    [switch]$PushBranch,
    [switch]$PreflightOnly,
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$RepoPath = (Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).Path
$launcher = Join-Path $RepoPath 'tooling/gnhf/Start-AgentSwitchboardOpenCode.ps1'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
    throw "Repository-owned OpenCode launcher not found: $launcher"
}

$childPowerShell = Join-Path $PSHOME 'pwsh.exe'
if (-not (Test-Path -LiteralPath $childPowerShell -PathType Leaf)) {
    throw "PowerShell 7 child executable not found: $childPowerShell"
}
if ([string]::IsNullOrWhiteSpace($StopWhen)) {
    throw '-StopWhen must describe an observable completion condition.'
}

$sourceKind = $null
$sourcePath = $null
if ($PromptPath) {
    $sourcePath = (Resolve-Path -LiteralPath $PromptPath -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Prompt path is not a file: $sourcePath"
    }
    $promptText = Get-Content -LiteralPath $sourcePath -Raw
    $sourceKind = 'prompt-file-snapshot'
}
else {
    $promptText = Get-Clipboard -Raw -ErrorAction Stop
    $sourceKind = 'clipboard-snapshot'
}
if ([string]::IsNullOrWhiteSpace($promptText)) {
    throw 'The bounded sprint prompt is empty.'
}

$runId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $baseRoot = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\prompt-handoff\runs'
    }
    else {
        Join-Path ([IO.Path]::GetTempPath()) 'AgentSwitchboard/prompt-handoff/runs'
    }
    $OutputRoot = Join-Path $baseRoot $runId
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
$null = New-Item -ItemType Directory -Path $OutputRoot -Force

$promptArtifact = Join-Path $OutputRoot 'bounded-sprint-prompt.md'
$receiptPath = Join-Path $OutputRoot 'prompt-handoff-receipt.json'
$reportPath = Join-Path $OutputRoot 'prompt-handoff-operator-report.md'
Set-Content -LiteralPath $promptArtifact -Value $promptText -Encoding utf8NoBOM

$initialHash = Get-Sha256 -Path $promptArtifact
$receipt = [ordered]@{
    schema = 'agentswitchboard.opencode-prompt-handoff-receipt.v1'
    runId = $runId
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    completedAt = $null
    status = 'materialized'
    repository = $RepoPath
    sourceKind = $sourceKind
    sourcePath = $sourcePath
    promptArtifact = $promptArtifact
    promptTracked = $false
    promptCharacters = $promptText.Length
    promptSha256 = $initialHash
    rawPromptRecordedInReceipt = $false
    preflight = [ordered]@{ attempted = $false; exitCode = $null; promptSha256After = $null }
    execution = [ordered]@{ requested = (-not $PreflightOnly); attempted = $false; exitCode = $null; promptSha256After = $null }
    proofLevel = 'prompt-materialized'
    proofCeiling = 'Prompt transport and gate ordering only; downstream provider, coding, push, merge, deployment, and acceptance claims require their owning evidence.'
    error = $null
}

function Save-Receipt {
    $receipt.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM

    $lines = @(
        '# AgentSwitchboard OpenCode Prompt Handoff',
        '',
        "- Status: $($receipt.status)",
        "- Repository: $($receipt.repository)",
        "- Prompt source: $($receipt.sourceKind)",
        "- Prompt artifact: $($receipt.promptArtifact)",
        "- Prompt SHA-256: $($receipt.promptSha256)",
        "- Prompt characters: $($receipt.promptCharacters)",
        "- Preflight exit: $($receipt.preflight.exitCode)",
        "- Execution requested: $($receipt.execution.requested)",
        "- Execution exit: $($receipt.execution.exitCode)",
        "- Proof level: $($receipt.proofLevel)",
        '',
        '## Proof ceiling',
        '',
        $receipt.proofCeiling
    )
    if ($receipt.error) {
        $lines += @('', '## Error', '', [string]$receipt.error)
    }
    $lines -join [Environment]::NewLine | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM
}

function Invoke-ExistingOpenCodeLauncher {
    param([switch]$PlanOnly)

    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @(
        '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', $launcher,
        '-RepoPath', $RepoPath,
        '-PromptPath', $promptArtifact,
        '-Name', $Name,
        '-MaxIterations', [string]$MaxIterations,
        '-MaxTokens', [string]$MaxTokens,
        '-StopWhen', $StopWhen
    )) {
        [void]$arguments.Add([string]$argument)
    }
    if ($PushBranch) { [void]$arguments.Add('-PushBranch') }
    if ($PlanOnly) { [void]$arguments.Add('-PlanOnly') }

    $childOutput = & $childPowerShell @arguments 2>&1
    $childExitCode = $LASTEXITCODE
    foreach ($line in @($childOutput)) { Write-Host ([string]$line) }
    return [int]$childExitCode
}

$failure = $null
try {
    Write-Host '=== AgentSwitchboard Prompt Handoff ===' -ForegroundColor Cyan
    Write-Host "Repo:       $RepoPath"
    Write-Host "Prompt:     $promptArtifact"
    Write-Host "SHA-256:    $initialHash"
    Write-Host "Preflight:  required"
    Write-Host "Execute:    $(-not $PreflightOnly)"
    Write-Host "Evidence:   $receiptPath"

    $receipt.status = 'preflight-running'
    $receipt.preflight.attempted = $true
    Save-Receipt
    $preflightExit = Invoke-ExistingOpenCodeLauncher -PlanOnly
    $receipt.preflight.exitCode = $preflightExit
    $receipt.preflight.promptSha256After = Get-Sha256 -Path $promptArtifact
    if ($receipt.preflight.promptSha256After -ne $initialHash) {
        throw 'Prompt artifact changed during preflight; refusing to execute a different prompt.'
    }
    if ($preflightExit -ne 0) {
        throw "OpenCode preflight failed with exit code $preflightExit."
    }

    if ($PreflightOnly) {
        $receipt.status = 'preflight-passed'
        $receipt.proofLevel = 'same-artifact-preflight-passed'
        Write-Host '[PASS] Preflight passed against the materialized prompt artifact. Execution was not requested.' -ForegroundColor Green
    }
    else {
        $receipt.status = 'execution-running'
        $receipt.execution.attempted = $true
        Save-Receipt
        $executionExit = Invoke-ExistingOpenCodeLauncher
        $receipt.execution.exitCode = $executionExit
        $receipt.execution.promptSha256After = Get-Sha256 -Path $promptArtifact
        if ($receipt.execution.promptSha256After -ne $initialHash) {
            throw 'Prompt artifact changed between preflight and execution; continuity proof failed.'
        }
        if ($executionExit -ne 0) {
            throw "OpenCode bounded sprint failed with exit code $executionExit."
        }
        $receipt.status = 'success'
        $receipt.proofLevel = 'same-artifact-preflight-and-execution-completed'
        Write-Host '[PASS] Preflight and execution used the same materialized prompt artifact.' -ForegroundColor Green
    }
}
catch {
    $failure = $_
    $receipt.status = 'failed'
    $receipt.error = $_.Exception.Message
    $receipt.proofLevel = 'handoff-failed'
    Write-Error -ErrorRecord $_ -ErrorAction Continue
}
finally {
    Save-Receipt
    Write-Host "Receipt:    $receiptPath" -ForegroundColor Cyan
    Write-Host "Report:     $reportPath" -ForegroundColor Cyan
    Write-Host "Prompt:     $promptArtifact" -ForegroundColor Cyan
}

if ($failure) { exit 1 }
exit 0
