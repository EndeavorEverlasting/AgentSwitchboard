[CmdletBinding()]
param(
    [string]$ConfigPath = "$env:LOCALAPPDATA\AgentSwitchboard\Nap\nap-sprint.json",
    [string]$RepoPath,
    [ValidateSet("clipboard", "file")]
    [string]$PromptSource = "clipboard",
    [string]$PromptPath,
    [string[]]$PreferredAgents = @("hermes", "opencode", "goose", "copilot"),
    [string]$Name = "nap-sprint",
    [ValidateRange(1, 100)]
    [int]$MaxIterations = 4,
    [ValidateRange(1, 1000000000)]
    [int]$MaxTokens = 250000,
    [string]$StopWhen = "The bounded sprint is committed in the isolated GNHF worktree, targeted validation passes, no unrelated files changed, and the branch contains at least one useful commit.",
    [bool]$BootstrapIfMissing = $true,
    [bool]$InstallOpenCodeAndCopilotDuringBootstrap = $true,
    [bool]$PushBranch = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 is required. Run this configuration wizard with pwsh."
}

function Resolve-GitRepository {
    param([Parameter(Mandatory)][string]$Path)

    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "Repository path is not a directory: $resolved"
    }

    $inside = & git -C $resolved rev-parse --is-inside-work-tree 2>&1
    if ($LASTEXITCODE -ne 0 -or ($inside | Select-Object -First 1) -ne "true") {
        throw "Path is not a Git working tree: $resolved"
    }
    return $resolved
}

if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    $RepoPath = Read-Host "Target Git repository path"
}
if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    throw "A target repository path is required."
}

$RepoPath = Resolve-GitRepository -Path $RepoPath
$allowedAgents = @("hermes", "opencode", "goose", "copilot", "agy")
$normalizedAgents = [System.Collections.Generic.List[string]]::new()
foreach ($agent in $PreferredAgents) {
    if ([string]::IsNullOrWhiteSpace($agent)) {
        continue
    }
    $normalized = $agent.Trim().ToLowerInvariant()
    if ($allowedAgents -notcontains $normalized) {
        throw "Unsupported preferred agent '$agent'. Allowed: $($allowedAgents -join ', ')."
    }
    if (-not $normalizedAgents.Contains($normalized)) {
        [void]$normalizedAgents.Add($normalized)
    }
}
if ($normalizedAgents.Count -eq 0) {
    throw "At least one preferred agent is required."
}
if ([string]::IsNullOrWhiteSpace($Name)) {
    throw "The nap sprint name cannot be blank."
}
if ([string]::IsNullOrWhiteSpace($StopWhen)) {
    throw "The stop condition cannot be blank."
}

$resolvedPromptPath = $null
if ($PromptSource -eq "file") {
    if ([string]::IsNullOrWhiteSpace($PromptPath)) {
        $PromptPath = Read-Host "Prompt file path"
    }
    if ([string]::IsNullOrWhiteSpace($PromptPath)) {
        throw "promptSource=file requires promptPath."
    }
    $resolvedPromptPath = (Resolve-Path -LiteralPath $PromptPath -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolvedPromptPath -PathType Leaf)) {
        throw "Prompt path is not a file: $resolvedPromptPath"
    }
}

$configParent = Split-Path -Parent ([IO.Path]::GetFullPath($ConfigPath))
if ([string]::IsNullOrWhiteSpace($configParent)) {
    throw "ConfigPath must include a parent directory."
}
New-Item -ItemType Directory -Path $configParent -Force | Out-Null
$ConfigPath = Join-Path $configParent (Split-Path -Leaf $ConfigPath)

$config = [ordered]@{
    schemaVersion = 1
    repoPath = $RepoPath
    preferredAgents = @($normalizedAgents)
    promptSource = $PromptSource
    promptPath = $resolvedPromptPath
    name = $Name
    maxIterations = $MaxIterations
    maxTokens = $MaxTokens
    stopWhen = $StopWhen
    bootstrapIfMissing = $BootstrapIfMissing
    installOpenCodeAndCopilotDuringBootstrap = $InstallOpenCodeAndCopilotDuringBootstrap
    pushBranch = $PushBranch
}

$config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ConfigPath -Encoding utf8NoBOM

Write-Host "`nNap sprint configuration written:" -ForegroundColor Green
Write-Host "  $ConfigPath"
Write-Host "Repository: $RepoPath"
Write-Host "Agents:     $($normalizedAgents -join ' -> ')"
Write-Host "Prompt:     $PromptSource"
Write-Host "Iterations: $MaxIterations"
Write-Host "Token cap:  $MaxTokens"
Write-Host "Push:       $PushBranch"
Write-Host "`nCopy a bounded sprint prompt to the clipboard, then double-click Start-NapSprint.cmd." -ForegroundColor Cyan
