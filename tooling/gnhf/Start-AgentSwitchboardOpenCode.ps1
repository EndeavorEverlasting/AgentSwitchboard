[CmdletBinding()]
param(
    [string]$RepoPath,
    [string]$PromptPath,
    [AllowEmptyString()][string]$Prompt,
    [string]$Name,
    [ValidateRange(1, 100)][int]$MaxIterations = 4,
    [ValidateRange(1, 1000000000)][int]$MaxTokens = 250000,
    [string]$StopWhen = 'The bounded sprint is committed in the isolated worktree, targeted validation passes, and no unrelated files changed.',
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [switch]$PushBranch,
    [switch]$PlanOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') {
    throw 'The clickable AgentSwitchboard OpenCode launcher is a Windows operator surface.'
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'AgentSwitchboard OpenCode requires PowerShell 7.'
}
if ($PromptPath -and $PSBoundParameters.ContainsKey('Prompt')) {
    throw 'Use either -PromptPath or -Prompt, not both.'
}
if ([string]::IsNullOrWhiteSpace($StopWhen)) {
    throw '-StopWhen must describe an observable completion condition.'
}

$repoOwnedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    $RepoPath = $repoOwnedRoot
}
$RepoPath = (Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).Path
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)

$runId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runRoot = Join-Path $InstallRoot "logs\opencode-click\$runId"
$null = New-Item -ItemType Directory -Path $runRoot -Force
$summaryPath = Join-Path $runRoot 'opencode-click-launch.json'
$temporaryPromptPath = $null
$failure = $null

$summary = [ordered]@{
    schema = 'agentswitchboard.opencode-click-launch.v1'
    runId = $runId
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    completedAt = $null
    status = 'preflight'
    requestedRepoPath = $RepoPath
    resolvedRepoPath = $null
    branch = $null
    agent = 'opencode'
    promptSource = $null
    promptCharacters = 0
    maxIterations = $MaxIterations
    maxTokens = $MaxTokens
    stopWhen = $StopWhen
    pushBranch = [bool]$PushBranch
    planOnly = [bool]$PlanOnly
    sprintLauncher = $null
    childPowerShell = $null
    childExitCode = $null
    error = $null
    proofLevel = 'not-proven'
    proofCeiling = 'No OpenCode or GNHF runtime proof has been observed yet.'
    evidencePath = $summaryPath
}

function Invoke-GitLines {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & git -C $RepoPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code ${exitCode}:`n$($output -join [Environment]::NewLine)"
    }
    return @($output)
}

try {
    $gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
    if (-not $gitCommand) {
        $gitCommand = Get-Command git -ErrorAction Stop
    }

    $insideLines = @(Invoke-GitLines -Arguments @('rev-parse', '--is-inside-work-tree'))
    $insideWorkTree = if ($insideLines.Count -gt 0) { [string]$insideLines[0] } else { '' }
    if (-not $insideWorkTree.Trim().Equals('true', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Target path is not a Git working tree: $RepoPath"
    }

    $dirty = @(Invoke-GitLines -Arguments @('status', '--porcelain=v1') | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($dirty.Count -gt 0) {
        throw "AgentSwitchboard requires a clean target checkout before creating an isolated GNHF worktree. Existing changes:`n$($dirty -join [Environment]::NewLine)"
    }

    $branchLines = @(Invoke-GitLines -Arguments @('branch', '--show-current'))
    $branch = if ($branchLines.Count -gt 0) { [string]$branchLines[0] } else { '' }
    $branch = $branch.Trim()
    if ([string]::IsNullOrWhiteSpace($branch)) {
        throw "Detached HEAD is not a valid sprint base. This is commonly a verification worktree. Open a clean attached repository checkout, or drag that repository folder onto Start-AgentSwitchboard-OpenCode.cmd. No agent or provider was launched."
    }
    if ($branch.StartsWith('gnhf/', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Do not launch a new sprint from an existing GNHF worktree. Current branch: $branch"
    }

    $statePath = Join-Path $InstallRoot 'state.json'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "AgentSwitchboard fleet state is missing: $statePath. Run Setup-AgentSwitchboard.cmd once, then click Start-AgentSwitchboard-OpenCode.cmd again."
    }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $openCodeProperty = $state.agents.PSObject.Properties['opencode']
    if (-not $openCodeProperty -or -not $openCodeProperty.Value.available) {
        $evidence = if ($openCodeProperty) { [string]$openCodeProperty.Value.evidence } else { 'no OpenCode state record' }
        throw "OpenCode is not adapter-ready in AgentSwitchboard state. Evidence: $evidence"
    }

    $effectivePromptPath = $null
    if ($PromptPath) {
        $effectivePromptPath = (Resolve-Path -LiteralPath $PromptPath -ErrorAction Stop).Path
        if (-not (Test-Path -LiteralPath $effectivePromptPath -PathType Leaf)) {
            throw "Prompt file is not a file: $effectivePromptPath"
        }
        $promptText = Get-Content -LiteralPath $effectivePromptPath -Raw
        $summary.promptSource = 'prompt-file'
    }
    else {
        if ($PSBoundParameters.ContainsKey('Prompt')) {
            $promptText = $Prompt
            $summary.promptSource = 'argument'
        }
        else {
            $promptText = Get-Clipboard -Raw -ErrorAction Stop
            $summary.promptSource = 'clipboard'
        }
        if ([string]::IsNullOrWhiteSpace($promptText)) {
            throw 'No bounded sprint prompt was found. Copy the sprint prompt to the Windows clipboard, then double-click Start-AgentSwitchboard-OpenCode.cmd again.'
        }
        $temporaryPromptPath = Join-Path $runRoot 'runtime-prompt.md'
        Set-Content -LiteralPath $temporaryPromptPath -Value $promptText -Encoding utf8NoBOM
        $effectivePromptPath = $temporaryPromptPath
    }

    if ([string]::IsNullOrWhiteSpace($promptText)) {
        throw 'The bounded sprint prompt is empty.'
    }

    $sprintLauncher = Join-Path $PSScriptRoot 'Start-GnhfSprint.ps1'
    if (-not (Test-Path -LiteralPath $sprintLauncher -PathType Leaf)) {
        throw "Repository-owned bounded sprint launcher is missing: $sprintLauncher"
    }
    $childPowerShell = Join-Path $PSHOME 'pwsh.exe'
    if (-not (Test-Path -LiteralPath $childPowerShell -PathType Leaf)) {
        throw "The current PowerShell 7 child executable cannot be resolved: $childPowerShell"
    }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        $Name = '{0}-opencode' -f (Split-Path -Leaf $RepoPath)
    }

    $summary.resolvedRepoPath = $RepoPath
    $summary.branch = $branch
    $summary.promptCharacters = $promptText.Length
    $summary.sprintLauncher = $sprintLauncher
    $summary.childPowerShell = $childPowerShell

    Write-Host '=== AgentSwitchboard OpenCode ===' -ForegroundColor Cyan
    Write-Host "Repo:       $RepoPath"
    Write-Host "Branch:     $branch"
    Write-Host 'Agent:      opencode'
    Write-Host "Prompt:     $($summary.promptSource) ($($summary.promptCharacters) characters)"
    Write-Host "Iterations: $MaxIterations"
    Write-Host "Token cap:  $MaxTokens"
    Write-Host "Push:       $([bool]$PushBranch)"
    Write-Host "Evidence:   $summaryPath"

    if ($PlanOnly) {
        $summary.status = 'planned'
        $summary.proofLevel = 'launch-preflight'
        $summary.proofCeiling = 'Proves only that the target checkout is clean and attached, OpenCode is adapter-ready in local AgentSwitchboard state, and the repo-owned bounded sprint launcher is present. No GNHF or provider process was started.'
        Write-Host '[PLAN] Preflight passed. No GNHF or provider process was started.' -ForegroundColor Green
    }
    else {
        $arguments = [System.Collections.Generic.List[string]]::new()
        foreach ($argument in @(
            '-NoLogo',
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', $sprintLauncher,
            '-RepoPath', $RepoPath,
            '-Agent', 'opencode',
            '-PromptPath', $effectivePromptPath,
            '-Name', $Name,
            '-MaxIterations', [string]$MaxIterations,
            '-MaxTokens', [string]$MaxTokens,
            '-StopWhen', $StopWhen,
            '-InstallRoot', $InstallRoot
        )) {
            [void]$arguments.Add([string]$argument)
        }
        if ($PushBranch) {
            [void]$arguments.Add('-PushBranch')
        }

        & $childPowerShell @arguments
        $summary.childExitCode = $LASTEXITCODE
        if ($summary.childExitCode -ne 0) {
            throw "The bounded OpenCode sprint failed with exit code $($summary.childExitCode). Review the GNHF launcher summary printed above and $summaryPath."
        }

        $summary.status = 'child-completed'
        $summary.proofLevel = 'bounded-sprint-process-completed'
        $summary.proofCeiling = 'Proves the repo-owned bounded GNHF/OpenCode child process returned zero. Repository delivery, validation quality, provider behavior, push, merge, deployment, and operator acceptance require their owning evidence.'
        Write-Host '[PASS] Bounded OpenCode child process completed. Review the generated worktree and validation evidence before accepting delivery.' -ForegroundColor Green
    }
}
catch {
    $failure = $_
    $summary.status = 'failed'
    $summary.error = $_.Exception.Message
    $summary.proofLevel = 'launch-failed'
    $summary.proofCeiling = 'The click launcher failed before it could prove the requested OpenCode sprint outcome. Use the recorded error and downstream artifact paths for repair.'
}
finally {
    if ($temporaryPromptPath -and (Test-Path -LiteralPath $temporaryPromptPath -PathType Leaf)) {
        Remove-Item -LiteralPath $temporaryPromptPath -Force -ErrorAction SilentlyContinue
    }
    $summary.completedAt = (Get-Date).ToUniversalTime().ToString('o')
    $summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding utf8NoBOM
    Write-Host "Launch evidence: $summaryPath" -ForegroundColor Cyan
}

if ($failure) {
    throw $failure.Exception
}
