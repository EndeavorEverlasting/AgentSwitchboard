[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [switch]$PushBranches,
    [switch]$Wait,
    [switch]$KeepWindowsOpen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Start-PwshProcess {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $pwsh
    $psi.UseShellExecute = $true

    foreach ($argument in $Arguments) {
        [void]$psi.ArgumentList.Add($argument)
    }

    return [System.Diagnostics.Process]::Start($psi)
}

function Resolve-ManifestPath {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][string]$BaseDirectory
    )

    if ([System.IO.Path]::IsPathRooted($Value)) {
        return (Resolve-Path -LiteralPath $Value).Path
    }

    return (Resolve-Path -LiteralPath (Join-Path $BaseDirectory $Value)).Path
}

$ManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path
$manifestDirectory = Split-Path -Parent $ManifestPath
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

if (-not $manifest.sprints) {
    throw "Manifest contains no sprints: $ManifestPath"
}

$statePath = Join-Path $InstallRoot "state.json"
if (-not (Test-Path -LiteralPath $statePath)) {
    throw "Fleet state not found: $statePath"
}
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json

$workerScript = Join-Path $InstallRoot "Start-GnhfSprint.ps1"
if (-not (Test-Path -LiteralPath $workerScript)) {
    throw "Worker script missing: $workerScript"
}

$defaults = $manifest.defaults
$launches = [System.Collections.Generic.List[object]]::new()
$processes = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()

foreach ($sprint in $manifest.sprints) {
    if ($sprint.PSObject.Properties["enabled"] -and -not [bool]$sprint.enabled) {
        continue
    }

    $repoPath = Resolve-ManifestPath -Value ([string]$sprint.repoPath) -BaseDirectory $manifestDirectory
    $promptPath = Resolve-ManifestPath -Value ([string]$sprint.promptPath) -BaseDirectory $manifestDirectory
    $name = [string]$sprint.name
    $agent = [string]$sprint.agent

    $maxIterations = if ($sprint.PSObject.Properties["maxIterations"]) {
        [int]$sprint.maxIterations
    } elseif ($defaults -and $defaults.PSObject.Properties["maxIterations"]) {
        [int]$defaults.maxIterations
    } else {
        6
    }

    $maxTokens = if ($sprint.PSObject.Properties["maxTokens"]) {
        [int]$sprint.maxTokens
    } elseif ($defaults -and $defaults.PSObject.Properties["maxTokens"]) {
        [int]$defaults.maxTokens
    } else {
        500000
    }

    $stopWhen = [string]$sprint.stopWhen
    if ([string]::IsNullOrWhiteSpace($stopWhen)) {
        throw "Sprint '$name' has no observable stopWhen condition."
    }

    $agentProperty = $state.agents.PSObject.Properties[$agent.ToLowerInvariant()]
    if ($agentProperty -and -not [bool]$agentProperty.Value.available) {
        Write-Warning "Skipping '$name': agent '$agent' is blocked. $($agentProperty.Value.evidence)"
        [void]$launches.Add([pscustomobject]@{
            name = $name
            agent = $agent
            status = "skipped-agent-blocked"
            evidence = $agentProperty.Value.evidence
        })
        continue
    }

    $arguments = [System.Collections.Generic.List[string]]::new()
    [void]$arguments.Add("-NoLogo")
    [void]$arguments.Add("-NoProfile")
    if ($KeepWindowsOpen) {
        [void]$arguments.Add("-NoExit")
    }
    [void]$arguments.Add("-File")
    [void]$arguments.Add($workerScript)
    [void]$arguments.Add("-RepoPath")
    [void]$arguments.Add($repoPath)
    [void]$arguments.Add("-Agent")
    [void]$arguments.Add($agent)
    [void]$arguments.Add("-PromptPath")
    [void]$arguments.Add($promptPath)
    [void]$arguments.Add("-Name")
    [void]$arguments.Add($name)
    [void]$arguments.Add("-MaxIterations")
    [void]$arguments.Add([string]$maxIterations)
    [void]$arguments.Add("-MaxTokens")
    [void]$arguments.Add([string]$maxTokens)
    [void]$arguments.Add("-StopWhen")
    [void]$arguments.Add($stopWhen)
    [void]$arguments.Add("-InstallRoot")
    [void]$arguments.Add($InstallRoot)
    if ($PushBranches) {
        [void]$arguments.Add("-PushBranch")
    }

    $process = Start-PwshProcess -Arguments $arguments.ToArray()
    [void]$processes.Add($process)
    [void]$launches.Add([pscustomobject]@{
        name = $name
        agent = $agent
        repoPath = $repoPath
        promptPath = $promptPath
        maxIterations = $maxIterations
        maxTokens = $maxTokens
        stopWhen = $stopWhen
        processId = $process.Id
        status = "launched"
    })

    Write-Host ("Launched {0} with {1} as PID {2}" -f $name, $agent, $process.Id) -ForegroundColor Green
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$launchReportPath = Join-Path $InstallRoot "reports\fleet-launch-$timestamp.json"
[pscustomobject]@{
    schemaVersion = 1
    launchedAt = (Get-Date).ToString("o")
    manifestPath = $ManifestPath
    pushBranches = [bool]$PushBranches
    keepWindowsOpen = [bool]$KeepWindowsOpen
    launches = @($launches)
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $launchReportPath -Encoding utf8NoBOM

Write-Host "`nFleet launch report: $launchReportPath" -ForegroundColor Cyan

if ($Wait -and $processes.Count -gt 0) {
    Write-Host "Waiting for $($processes.Count) sprint process(es)..." -ForegroundColor Cyan
    foreach ($process in $processes) {
        $process.WaitForExit()
        Write-Host "PID $($process.Id) exited with code $($process.ExitCode)"
    }
}
else {
    Write-Host "Fleet is running in separate PowerShell processes. No branch is pushed unless -PushBranches was supplied." -ForegroundColor Yellow
}
