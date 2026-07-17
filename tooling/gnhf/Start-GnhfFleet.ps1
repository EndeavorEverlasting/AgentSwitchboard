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

$pathHelpersPath = Join-Path $PSScriptRoot "GnhfFleet.Paths.ps1"
if (-not (Test-Path -LiteralPath $pathHelpersPath -PathType Leaf)) {
    throw "Path helper library not found: $pathHelpersPath"
}
. $pathHelpersPath

if ($Wait -and $KeepWindowsOpen) {
    throw "-Wait and -KeepWindowsOpen are mutually exclusive. Use -Wait for automation or -KeepWindowsOpen for interactive inspection."
}

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

$ManifestPath = Resolve-GnhfFleetFile -Path $ManifestPath -Description "fleet manifest"
$manifestDirectory = Split-Path -Parent $ManifestPath
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if (-not $manifest.sprints) {
    throw "Manifest contains no sprints: $ManifestPath"
}

$InstallRoot = Get-GnhfFleetAbsolutePath -Path $InstallRoot
$statePath = Resolve-GnhfFleetFile -Path (Join-Path $InstallRoot "state.json") -Description "fleet state"
$workerScript = Resolve-GnhfFleetFile -Path (Join-Path $InstallRoot "Start-GnhfSprint.ps1") -Description "bounded sprint launcher"
$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
$reportsRoot = Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "reports")

$defaults = $manifest.defaults
$launches = [System.Collections.Generic.List[object]]::new()
$processes = [System.Collections.Generic.List[object]]::new()
$sprintIndex = 0

foreach ($sprint in $manifest.sprints) {
    $sprintIndex++
    if ($sprint.PSObject.Properties["enabled"] -and -not [bool]$sprint.enabled) {
        continue
    }

    $name = [string]$sprint.name
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = "unnamed-sprint-$sprintIndex"
    }
    $agent = [string]$sprint.agent

    $maxIterations = if ($sprint.PSObject.Properties["maxIterations"]) {
        [int]$sprint.maxIterations
    }
    elseif ($defaults -and $defaults.PSObject.Properties["maxIterations"]) {
        [int]$defaults.maxIterations
    }
    else {
        6
    }

    $maxTokens = if ($sprint.PSObject.Properties["maxTokens"]) {
        [int]$sprint.maxTokens
    }
    elseif ($defaults -and $defaults.PSObject.Properties["maxTokens"]) {
        [int]$defaults.maxTokens
    }
    else {
        500000
    }

    $stopWhen = [string]$sprint.stopWhen
    if ([string]::IsNullOrWhiteSpace($stopWhen)) {
        Write-Warning "Skipping '$name': observable stopWhen condition is missing."
        [void]$launches.Add([pscustomobject]@{
            name = $name
            agent = $agent
            status = "skipped-invalid-config"
            evidence = "Observable stopWhen condition is missing."
        })
        continue
    }

    if ([string]::IsNullOrWhiteSpace($agent)) {
        Write-Warning "Skipping '$name': agent is missing."
        [void]$launches.Add([pscustomobject]@{
            name = $name
            agent = $null
            status = "skipped-invalid-config"
            evidence = "Agent is missing."
        })
        continue
    }

    $agentProperty = $state.agents.PSObject.Properties[$agent.ToLowerInvariant()]
    if (-not $agentProperty) {
        Write-Warning "Skipping '$name': agent '$agent' has no readiness record."
        [void]$launches.Add([pscustomobject]@{
            name = $name
            agent = $agent
            status = "skipped-unknown-agent"
            evidence = "No readiness record exists in $statePath."
        })
        continue
    }
    if (-not [bool]$agentProperty.Value.available) {
        Write-Warning "Skipping '$name': agent '$agent' is blocked. $($agentProperty.Value.evidence)"
        [void]$launches.Add([pscustomobject]@{
            name = $name
            agent = $agent
            status = "skipped-agent-blocked"
            evidence = $agentProperty.Value.evidence
        })
        continue
    }

    try {
        $repoPath = Resolve-GnhfFleetDirectory -Path ([string]$sprint.repoPath) -BaseDirectory $manifestDirectory -Description "repository for sprint '$name'"
        $promptPath = Resolve-GnhfFleetFile -Path ([string]$sprint.promptPath) -BaseDirectory $manifestDirectory -Description "prompt for sprint '$name'"
    }
    catch {
        Write-Warning "Skipping '$name': $($_.Exception.Message)"
        [void]$launches.Add([pscustomobject]@{
            name = $name
            agent = $agent
            status = "skipped-invalid-path"
            evidence = $_.Exception.Message
        })
        continue
    }

    $arguments = [System.Collections.Generic.List[string]]::new()
    [void]$arguments.Add("-NoLogo")
    [void]$arguments.Add("-NoProfile")
    if ($KeepWindowsOpen) {
        [void]$arguments.Add("-NoExit")
    }
    foreach ($argument in @(
        "-File", $workerScript,
        "-RepoPath", $repoPath,
        "-Agent", $agent,
        "-PromptPath", $promptPath,
        "-Name", $name,
        "-MaxIterations", [string]$maxIterations,
        "-MaxTokens", [string]$maxTokens,
        "-StopWhen", $stopWhen,
        "-InstallRoot", $InstallRoot
    )) {
        [void]$arguments.Add($argument)
    }
    if ($PushBranches) {
        [void]$arguments.Add("-PushBranch")
    }

    try {
        $process = Start-PwshProcess -Arguments $arguments.ToArray()
        $launchRecord = [pscustomobject]@{
            name = $name
            agent = $agent
            repoPath = $repoPath
            promptPath = $promptPath
            maxIterations = $maxIterations
            maxTokens = $maxTokens
            stopWhen = $stopWhen
            processId = $process.Id
            status = "launched"
            exitCode = $null
            evidence = $null
        }
        [void]$launches.Add($launchRecord)
        [void]$processes.Add([pscustomobject]@{ Process = $process; Record = $launchRecord })
        Write-Host ("Launched {0} with {1} as PID {2}" -f $name, $agent, $process.Id) -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to launch '$name': $($_.Exception.Message)"
        [void]$launches.Add([pscustomobject]@{
            name = $name
            agent = $agent
            repoPath = $repoPath
            promptPath = $promptPath
            status = "launch-failed"
            evidence = $_.Exception.Message
        })
    }
}

if ($Wait -and $processes.Count -gt 0) {
    Write-Host "Waiting for $($processes.Count) sprint process(es)..." -ForegroundColor Cyan
    foreach ($item in $processes) {
        $item.Process.WaitForExit()
        $item.Record.exitCode = $item.Process.ExitCode
        $item.Record.status = if ($item.Process.ExitCode -eq 0) { "completed" } else { "failed" }
        Write-Host "PID $($item.Process.Id) exited with code $($item.Process.ExitCode)"
    }
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$launchReportPath = Join-Path $reportsRoot "fleet-launch-$timestamp.json"
[pscustomobject]@{
    schemaVersion = 1
    launchedAt = (Get-Date).ToString("o")
    manifestPath = $ManifestPath
    pushBranches = [bool]$PushBranches
    keepWindowsOpen = [bool]$KeepWindowsOpen
    waitForCompletion = [bool]$Wait
    launches = @($launches)
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $launchReportPath -Encoding utf8NoBOM

Write-Host "`nFleet launch report: $launchReportPath" -ForegroundColor Cyan
if (-not $Wait) {
    Write-Host "Fleet processes continue independently. No branch is pushed unless -PushBranches was supplied." -ForegroundColor Yellow
}
