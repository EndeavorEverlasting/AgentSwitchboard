[CmdletBinding()]
param(
    [string]$RepoPath = (Get-Location).Path,
    [ValidateSet("opencode", "goose", "agy", "copilot", "hermes")]
    [string]$Agent = "opencode",
    [string]$PromptPath,
    [string]$Prompt,
    [string]$Name,
    [ValidateRange(1, 100)]
    [int]$MaxIterations = 4,
    [ValidateRange(1, 1000000000)]
    [int]$MaxTokens = 250000,
    [string]$StopWhen = "The bounded sprint is committed in the isolated worktree, targeted validation passes, and no unrelated files changed.",
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [switch]$Bootstrap,
    [switch]$InstallOpenCodeAndCopilot,
    [switch]$SkipHermesInstall,
    [switch]$PushBranch,
    [switch]$ListAgents
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pathHelpersPath = Join-Path $PSScriptRoot "GnhfFleet.Paths.ps1"
if (-not (Test-Path -LiteralPath $pathHelpersPath -PathType Leaf)) {
    throw "Path helper library not found: $pathHelpersPath"
}
. $pathHelpersPath

function Write-Section {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host "`n=== $Text ===" -ForegroundColor Cyan
}

function Show-AgentReadiness {
    param([Parameter(Mandatory)]$State)

    Write-Host "Agent readiness:" -ForegroundColor Cyan
    foreach ($agentName in @("opencode", "goose", "agy", "copilot", "hermes")) {
        $property = $State.agents.PSObject.Properties[$agentName]
        if (-not $property) {
            Write-Host ("  {0,-9} UNKNOWN  no state record" -f $agentName) -ForegroundColor Yellow
            continue
        }

        $record = $property.Value
        $status = if ($record.available) { "READY" } else { "BLOCKED" }
        $color = if ($record.available) { "Green" } else { "Yellow" }
        Write-Host ("  {0,-9} {1,-7} {2}" -f $agentName, $status, $record.evidence) -ForegroundColor $color
    }
}

function Install-OperatorLauncher {
    param([Parameter(Mandatory)][string]$DestinationRoot)

    $DestinationRoot = Ensure-GnhfFleetDirectory -Path $DestinationRoot
    $destinationScript = Join-Path $DestinationRoot "Start-AgentSwitchboard.ps1"
    $sourceScript = [IO.Path]::GetFullPath($PSCommandPath)
    $destinationFullPath = [IO.Path]::GetFullPath($destinationScript)
    if (-not $sourceScript.Equals($destinationFullPath, [StringComparison]::OrdinalIgnoreCase)) {
        Copy-Item -LiteralPath $sourceScript -Destination $destinationScript -Force
    }

    $cmdLauncher = @'
@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-AgentSwitchboard.ps1" %*
set "_code=%ERRORLEVEL%"
endlocal & exit /b %_code%
'@
    Set-Content -LiteralPath (Join-Path $DestinationRoot "agent-switchboard.cmd") -Value $cmdLauncher -Encoding ascii
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "AgentSwitchboard requires PowerShell 7. Open pwsh and rerun this command."
}
if ($Prompt -and $PromptPath) {
    throw "Use either -Prompt or -PromptPath, not both."
}
if ([string]::IsNullOrWhiteSpace($StopWhen)) {
    throw "-StopWhen must describe an observable completion condition."
}

$RepoPath = Resolve-GnhfFleetDirectory -Path $RepoPath -Description "target repository"
$repoName = Split-Path -Leaf $RepoPath
$InstallRoot = Get-GnhfFleetAbsolutePath -Path $InstallRoot
$statePath = Join-Path $InstallRoot "state.json"

if ($Bootstrap) {
    Write-Section "Bootstrap or repair AgentSwitchboard"
    $setupPath = Resolve-GnhfFleetFile -Path (Join-Path $PSScriptRoot "Setup-AgentSwitchboard.ps1") -Description "robust setup orchestrator"

    $setupParameters = @{
        DefaultRepoPath = $RepoPath
        InstallRoot = $InstallRoot
    }
    if ($InstallOpenCodeAndCopilot) {
        $setupParameters["InstallOpenCodeAndCopilot"] = $true
    }
    if ($SkipHermesInstall) {
        $setupParameters["SkipHermesInstall"] = $true
    }

    # Robust setup owns installation, Hermes ACP probing, transcript/summary evidence,
    # and contract validation. Delegating here prevents a core-only bootstrap from
    # overwriting the Hermes readiness record.
    & $setupPath @setupParameters
}

if (-not (Test-Path -LiteralPath $statePath)) {
    $bootstrapCommand = "pwsh -File `"$PSCommandPath`" -RepoPath `"$RepoPath`" -Bootstrap -ListAgents"
    throw "Fleet state not found: $statePath. Run the bootstrap/readiness probe:`n$bootstrapCommand"
}
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
    throw "Expected fleet state to be a file, but found a directory: $statePath"
}

$InstallRoot = Ensure-GnhfFleetDirectory -Path $InstallRoot
Install-OperatorLauncher -DestinationRoot $InstallRoot
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

if ($ListAgents) {
    Show-AgentReadiness -State $state
    Write-Host "`nLauncher: $(Join-Path $InstallRoot 'agent-switchboard.cmd')" -ForegroundColor Cyan
    Write-Host "Setup logs: $(Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\setup-logs')" -ForegroundColor Cyan
    return
}

$agentProperty = $state.agents.PSObject.Properties[$Agent]
if (-not $agentProperty) {
    throw "Agent '$Agent' has no adapter record in $statePath. Rerun with -Bootstrap -ListAgents to refresh detection."
}

$agentRecord = $agentProperty.Value
if (-not $agentRecord.available) {
    throw "Agent '$Agent' is blocked. Evidence: $($agentRecord.evidence)"
}

$defaultPromptByAgent = @{
    opencode = "opencode-implementation.md"
    goose = "goose-validation.md"
    agy = "agy-architecture.md"
    copilot = "copilot-tests.md"
    hermes = "hermes-implementation.md"
}

$runtimePromptPath = $null
if ($Prompt) {
    if ([string]::IsNullOrWhiteSpace($Prompt)) {
        throw "-Prompt cannot be blank."
    }

    $runtimePromptRoot = Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "runtime-prompts")
    $runtimePromptPath = Join-Path $runtimePromptRoot ("operator-{0}.md" -f (Get-Date -Format "yyyyMMdd-HHmmss-fff"))
    Set-Content -LiteralPath $runtimePromptPath -Value $Prompt -Encoding utf8NoBOM
    $PromptPath = $runtimePromptPath
}
elseif ($PromptPath) {
    $PromptPath = Resolve-GnhfFleetFile -Path $PromptPath -Description "sprint prompt"
}
else {
    if (-not $repoName.Equals("AgentSwitchboard", [StringComparison]::OrdinalIgnoreCase)) {
        throw "No sprint prompt was supplied for '$repoName'. Copy a bounded sprint prompt and pass -Prompt (Get-Clipboard -Raw), or pass -PromptPath. Bundled default prompts are scoped specifically to AgentSwitchboard."
    }

    $sourcePromptPath = Join-Path $PSScriptRoot (Join-Path "prompts" $defaultPromptByAgent[$Agent])
    $installedPromptPath = Join-Path $InstallRoot (Join-Path "prompts" $defaultPromptByAgent[$Agent])
    if (Test-Path -LiteralPath $sourcePromptPath -PathType Leaf) {
        $PromptPath = (Get-Item -LiteralPath $sourcePromptPath -Force).FullName
    }
    elseif (Test-Path -LiteralPath $installedPromptPath -PathType Leaf) {
        $PromptPath = (Get-Item -LiteralPath $installedPromptPath -Force).FullName
    }
    else {
        throw "Default prompt not found for '$Agent'. Supply -PromptPath explicitly or rerun -Bootstrap to repair installed prompts."
    }
}

if (-not $Name) {
    $Name = "$repoName-$Agent"
}

$sprintLauncher = Resolve-GnhfFleetFile -Path (Join-Path $InstallRoot "Start-GnhfSprint.ps1") -Description "bounded sprint launcher"
$arguments = [System.Collections.Generic.List[string]]::new()
foreach ($argument in @(
    "-NoLogo",
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $sprintLauncher,
    "-RepoPath", $RepoPath,
    "-Agent", $Agent,
    "-PromptPath", $PromptPath,
    "-Name", $Name,
    "-MaxIterations", [string]$MaxIterations,
    "-MaxTokens", [string]$MaxTokens,
    "-StopWhen", $StopWhen
)) {
    [void]$arguments.Add($argument)
}
if ($PushBranch) {
    [void]$arguments.Add("-PushBranch")
}

Write-Section "Launch coding sprint"
Write-Host "Repo:       $RepoPath"
Write-Host "Agent:      $Agent"
Write-Host "Prompt:     $PromptPath"
Write-Host "Iterations: $MaxIterations"
Write-Host "Token cap:  $MaxTokens"
Write-Host "Push:       $([bool]$PushBranch)"
Write-Host "Launcher:   $sprintLauncher"

$exitCode = 1
try {
    & pwsh @arguments
    $exitCode = $LASTEXITCODE
}
finally {
    if ($runtimePromptPath -and (Test-Path -LiteralPath $runtimePromptPath -PathType Leaf)) {
        Remove-Item -LiteralPath $runtimePromptPath -Force
    }
}

if ($exitCode -ne 0) {
    throw "AgentSwitchboard sprint failed with exit code $exitCode. Review the launcher summary under '$InstallRoot\logs'."
}

Write-Host "`nSprint completed successfully. Review the generated GNHF worktree and launcher summary before merging." -ForegroundColor Green
