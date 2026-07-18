[CmdletBinding()]
param(
    [string]$RepoPath = "$env:USERPROFILE\Desktop\dev\Mods\Bannerlord\BlacksmithGuild",
    [ValidateSet('Auto', 'Compile', 'Repair', 'Closeout')]
    [string]$Stage = 'Auto',
    [ValidateSet('deepseek', 'opencode', 'goose', 'agy', 'copilot', 'hermes')]
    [string]$Agent = 'deepseek',
    [ValidatePattern('^deepseek/[^\s/]+$')]
    [string]$DeepSeekModel = 'deepseek/deepseek-v4-pro',
    [ValidateRange(5, 120)]
    [int]$ProbeTimeoutSeconds = 20,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GitText {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    $output = & git -C $RepoPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($output -join [Environment]::NewLine)"
    }
    return (($output -join "`n").Trim())
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'BlacksmithGuild GNHF night shift requires native Windows PowerShell 7 (pwsh).'
}

$RepoPath = [IO.Path]::GetFullPath($RepoPath)
if (-not (Test-Path -LiteralPath (Join-Path $RepoPath '.git'))) {
    throw "BlacksmithGuild repository not found: $RepoPath"
}

$dirty = Invoke-GitText -Arguments @('status', '--porcelain=v1')
if (-not [string]::IsNullOrWhiteSpace($dirty)) {
    throw "The source checkout must be clean before GNHF worktree mode starts:`n$dirty"
}

$branch = Invoke-GitText -Arguments @('branch', '--show-current')
if ([string]::IsNullOrWhiteSpace($branch)) {
    throw 'Detached HEAD is not allowed for the unattended night shift.'
}
if ($branch.StartsWith('gnhf/', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Run the panel from a non-GNHF base branch. Current branch: $branch"
}

$contractPath = Join-Path $RepoPath '.tbg\workflows\gnhf-night-shift.contract.json'
if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    throw "BlacksmithGuild night-shift contract is missing: $contractPath. Update the repository before launching the panel."
}
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
if ([string]$contract.schema -ne 'tbg.gnhf-night-shift.contract.v1') {
    throw "Unsupported BlacksmithGuild night-shift contract schema: $($contract.schema)"
}

$queuePath = Join-Path $RepoPath (([string]$contract.paths.queue) -replace '/', [IO.Path]::DirectorySeparatorChar)
$selectedStage = $Stage.ToLowerInvariant()
if ($Stage -eq 'Auto') {
    if (-not (Test-Path -LiteralPath $queuePath -PathType Leaf)) {
        $selectedStage = 'compile'
    }
    else {
        try {
            $queue = Get-Content -LiteralPath $queuePath -Raw | ConvertFrom-Json
        }
        catch {
            throw "Night queue is not valid JSON: $queuePath. Preserve it and repair explicitly; do not overwrite unknown partial state."
        }
        if ([string]$queue.schema -ne [string]$contract.queue.schema) {
            throw "Night queue schema '$($queue.schema)' does not match '$($contract.queue.schema)'."
        }
        $readyCount = @($queue.items | Where-Object { [string]$_.state -eq 'ready' }).Count
        $selectedStage = if ($readyCount -gt 0) { 'repair' } else { 'closeout' }
    }
}

$stageRecord = @($contract.stageSelection | Where-Object { [string]$_.stage -eq $selectedStage } | Select-Object -First 1)
if ($stageRecord.Count -ne 1) {
    throw "Stage '$selectedStage' is not defined by $contractPath."
}
$stageRecord = $stageRecord[0]
$promptPath = Join-Path $RepoPath (([string]$stageRecord.promptPath) -replace '/', [IO.Path]::DirectorySeparatorChar)
if (-not (Test-Path -LiteralPath $promptPath -PathType Leaf)) {
    throw "Stage prompt is missing: $promptPath"
}

$agentSwitchboardPath = Join-Path $InstallRoot 'Start-AgentSwitchboard.ps1'
if (-not (Test-Path -LiteralPath $agentSwitchboardPath -PathType Leaf)) {
    throw "Installed AgentSwitchboard launcher is missing: $agentSwitchboardPath. Run Setup-AgentSwitchboard.cmd first."
}

Write-Host "`n=== BLACKSMITHGUILD GNHF NIGHT SHIFT ===" -ForegroundColor Cyan
Write-Host "Execution:  WezTerm -> native Windows PowerShell 7 -> AgentSwitchboard -> GNHF"
Write-Host "Repository: $RepoPath"
Write-Host "Base:       $branch"
Write-Host "Stage:      $selectedStage"
Write-Host "Agent:      $Agent"
Write-Host "Prompt:     $promptPath"
Write-Host "Iterations: $($stageRecord.maxIterations)"
Write-Host "Token cap:  $($stageRecord.maxTokens)"
Write-Host "Push:       false"

$parameters = @{
    RepoPath = $RepoPath
    Agent = $Agent
    PromptPath = $promptPath
    Name = "blacksmithguild-night-$selectedStage"
    MaxIterations = [int]$stageRecord.maxIterations
    MaxTokens = [int]$stageRecord.maxTokens
    StopWhen = [string]$stageRecord.stopWhen
    InstallRoot = $InstallRoot
}
if ($Agent -eq 'deepseek') {
    $parameters.DeepSeekModel = $DeepSeekModel
    $parameters.ProbeTimeoutSeconds = $ProbeTimeoutSeconds
}

& $agentSwitchboardPath @parameters
if ($LASTEXITCODE -ne 0) {
    throw "BlacksmithGuild night stage '$selectedStage' failed. Review operator-local AgentSwitchboard logs under '$InstallRoot\logs'."
}

Write-Host "`nNight stage '$selectedStage' completed. Review the generated GNHF worktree and commit evidence before another stage." -ForegroundColor Green
