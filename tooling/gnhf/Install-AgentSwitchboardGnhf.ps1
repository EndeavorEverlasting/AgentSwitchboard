[CmdletBinding()]
param(
    [string]$GnhfRepoPath,
    [string]$DevRoot = "$HOME\Desktop\dev",
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [string]$DefaultRepoPath,
    [string]$AgyAcpCommand,
    [switch]$SkipGnhfBuild,
    [switch]$RebuildGnhf,
    [switch]$InstallOpenCodeAndCopilot,
    [switch]$ResetManifest,
    [bool]$DisableGnhfTelemetry = $true
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

function Refresh-CurrentPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $npmPath = Join-Path $env:APPDATA "npm"
    $localBin = Join-Path $HOME ".local\bin"
    $env:Path = "$machinePath;$userPath;$npmPath;$localBin"
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory
    )

    $oldLocation = Get-Location
    try {
        if ($WorkingDirectory) {
            $resolvedWorkingDirectory = Resolve-GnhfFleetDirectory -Path $WorkingDirectory -Description "command working directory"
            Set-Location -LiteralPath $resolvedWorkingDirectory
        }

        Write-Host ("+ {0} {1}" -f $FilePath, ($ArgumentList -join " ")) -ForegroundColor DarkGray
        & $FilePath @ArgumentList
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($ArgumentList -join ' ')"
        }
    }
    finally {
        Set-Location -LiteralPath $oldLocation.Path
    }
}

function Invoke-Probe {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [int]$TimeoutSeconds = 15
    )

    $result = [ordered]@{
        FilePath = $FilePath
        Arguments = $ArgumentList
        ExitCode = $null
        TimedOut = $false
        Output = ""
    }

    try {
        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $FilePath
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true

        foreach ($argument in $ArgumentList) {
            [void]$psi.ArgumentList.Add($argument)
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $psi
        [void]$process.Start()

        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $result.TimedOut = $true
            try {
                $process.Kill($true)
                $process.WaitForExit()
            }
            catch {}
        }
        else {
            $result.ExitCode = $process.ExitCode
        }

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $result.Output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
    catch {
        $result.Output = $_.Exception.Message
    }

    return [pscustomobject]$result
}

function Resolve-GnhfClone {
    param(
        [string]$ExplicitPath,
        [string]$SearchRoot
    )

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($ExplicitPath) {
        [void]$candidates.Add((Get-GnhfFleetAbsolutePath -Path $ExplicitPath))
    }

    foreach ($candidate in @(
        (Join-Path $SearchRoot "agents\gnhf"),
        (Join-Path $SearchRoot "gnhf"),
        (Join-Path $HOME "source\repos\gnhf")
    )) {
        if ($candidate) {
            [void]$candidates.Add((Get-GnhfFleetAbsolutePath -Path $candidate))
        }
    }

    if (Test-Path -LiteralPath $SearchRoot -PathType Container) {
        Get-ChildItem -LiteralPath $SearchRoot -Directory -Filter "gnhf" -Recurse -Depth 4 -ErrorAction SilentlyContinue |
            ForEach-Object { [void]$candidates.Add($_.FullName) }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
            continue
        }

        $packageJson = Join-Path $candidate "package.json"
        if (-not (Test-Path -LiteralPath $packageJson -PathType Leaf)) {
            continue
        }

        try {
            $package = Get-Content -LiteralPath $packageJson -Raw | ConvertFrom-Json
            if ($package.name -eq "gnhf") {
                return (Get-Item -LiteralPath $candidate -Force).FullName
            }
        }
        catch {
            continue
        }
    }

    return $null
}

function Get-CommandRecord {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$VersionArguments = @("--version")
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        return [pscustomobject]@{
            Name = $Name
            Available = $false
            Path = $null
            Version = $null
            Evidence = "$Name command not found."
        }
    }

    $commandPath = $command.Source
    $probe = Invoke-Probe -FilePath $commandPath -ArgumentList $VersionArguments
    $probeSucceeded = (-not $probe.TimedOut -and $probe.ExitCode -eq 0)
    $version = if ($probeSucceeded -and $probe.Output) {
        ($probe.Output -split "\r?\n" | Select-Object -First 1).Trim()
    }
    elseif ($probeSucceeded) {
        "detected"
    }
    else {
        $null
    }

    $evidence = if ($probeSucceeded) {
        "$Name version probe exited successfully."
    }
    elseif ($probe.TimedOut) {
        "$Name command was found at '$commandPath', but its version probe timed out after 15 seconds."
    }
    else {
        "$Name command was found at '$commandPath', but its version probe failed with exit code $($probe.ExitCode). Output: $($probe.Output)"
    }

    return [pscustomobject]@{
        Name = $Name
        Available = $probeSucceeded
        Path = $commandPath
        Version = $version
        Evidence = $evidence
    }
}

function Install-GnhfSource {
    param([Parameter(Mandatory)][string]$RepoPath)

    $node = Get-Command node -ErrorAction SilentlyContinue
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $node -or -not $npm) {
        throw "Node.js and npm are required to build the cloned GNHF repository."
    }

    $nodeVersion = (& $node.Source --version).TrimStart("v")
    $nodeMajor = [int]($nodeVersion.Split(".")[0])
    if ($nodeMajor -lt 20) {
        throw "GNHF requires Node.js 20 or newer. Detected: $nodeVersion"
    }

    if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
        Write-Host "Installing pnpm 11.1.1 required by the current GNHF checkout..." -ForegroundColor Yellow
        Invoke-Checked -FilePath $npm.Source -ArgumentList @("install", "--global", "pnpm@11.1.1")
        Refresh-CurrentPath
    }

    $pnpm = (Get-Command pnpm -ErrorAction Stop).Source
    Invoke-Checked -FilePath $pnpm -ArgumentList @("install", "--frozen-lockfile") -WorkingDirectory $RepoPath
    Invoke-Checked -FilePath $pnpm -ArgumentList @("run", "build") -WorkingDirectory $RepoPath
    Invoke-Checked -FilePath $pnpm -ArgumentList @("link", "--global") -WorkingDirectory $RepoPath
    Refresh-CurrentPath
}

function Install-PublishedGnhf {
    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        throw "GNHF is unavailable and npm is not installed. Install Node.js 20 or newer, then rerun."
    }

    Write-Host "Installing or repairing the published GNHF package..." -ForegroundColor Yellow
    Invoke-Checked -FilePath $npm.Source -ArgumentList @("install", "--global", "gnhf")
    Refresh-CurrentPath
}

function Test-AgyAcp {
    param(
        [Parameter(Mandatory)][string]$AgyPath,
        [string]$ExplicitCommand
    )

    if ($ExplicitCommand) {
        return [pscustomobject]@{
            Ready = $true
            Command = $ExplicitCommand
            Evidence = "Explicit -AgyAcpCommand supplied by user."
        }
    }

    foreach ($candidate in @(
        @{ Arguments = @("acp", "--help"); Command = "agy acp" },
        @{ Arguments = @("--acp", "--help"); Command = "agy --acp" }
    )) {
        $probe = Invoke-Probe -FilePath $AgyPath -ArgumentList $candidate.Arguments
        if (-not $probe.TimedOut -and $probe.ExitCode -eq 0) {
            return [pscustomobject]@{
                Ready = $true
                Command = $candidate.Command
                Evidence = "$($candidate.Command) --help exited successfully."
            }
        }
    }

    $helpProbe = Invoke-Probe -FilePath $AgyPath -ArgumentList @("--help")
    return [pscustomobject]@{
        Ready = $false
        Command = $null
        Evidence = "No verified ACP launch form. Inspect 'agy --help' and rerun with -AgyAcpCommand '<exact ACP server command>'. Probe output: $($helpProbe.Output)"
    }
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "This bootstrap requires PowerShell 7 because it uses safe process ArgumentList handling. Run it from pwsh."
}
if ($SkipGnhfBuild -and $RebuildGnhf) {
    throw "-SkipGnhfBuild and -RebuildGnhf are mutually exclusive."
}

Write-Section "AgentSwitchboard GNHF Fleet Setup"
Refresh-CurrentPath

$resolvedGnhfRepo = Resolve-GnhfClone -ExplicitPath $GnhfRepoPath -SearchRoot $DevRoot
if ($resolvedGnhfRepo) {
    Write-Host "GNHF source clone: $resolvedGnhfRepo" -ForegroundColor Green
}
else {
    Write-Host "No GNHF source clone found. A healthy global install will be reused, or the published package will be installed." -ForegroundColor DarkGray
}

Write-Section "Reuse, build, or install GNHF"
$gnhf = Get-CommandRecord -Name "gnhf"

if ($gnhf.Available -and -not $RebuildGnhf) {
    Write-Host "Using existing GNHF installation: $($gnhf.Path)" -ForegroundColor Green
}
else {
    if ($RebuildGnhf -and -not $resolvedGnhfRepo) {
        throw "-RebuildGnhf requires a valid GNHF source clone. Supply -GnhfRepoPath or place the clone under '$DevRoot'."
    }

    if ($resolvedGnhfRepo -and -not $SkipGnhfBuild) {
        Write-Host "Building and linking GNHF from the existing source clone..." -ForegroundColor Yellow
        Install-GnhfSource -RepoPath $resolvedGnhfRepo
        $gnhf = Get-CommandRecord -Name "gnhf"
    }

    if (-not $gnhf.Available) {
        Install-PublishedGnhf
        $gnhf = Get-CommandRecord -Name "gnhf"
    }
}

if (-not $gnhf.Available) {
    throw "GNHF installation or repair completed, but readiness validation still failed. $($gnhf.Evidence)"
}
Write-Host "GNHF: $($gnhf.Version)" -ForegroundColor Green

if ($InstallOpenCodeAndCopilot) {
    Write-Section "Reuse or repair native agents"

    $openCodeBefore = Get-CommandRecord -Name "opencode"
    if (-not $openCodeBefore.Available) {
        $npm = Get-Command npm -ErrorAction Stop
        Write-Host "Installing or repairing OpenCode..." -ForegroundColor Yellow
        Invoke-Checked -FilePath $npm.Source -ArgumentList @("install", "--global", "opencode-ai")
        Refresh-CurrentPath
    }
    else {
        Write-Host "Using existing OpenCode installation: $($openCodeBefore.Path)" -ForegroundColor Green
    }

    $copilotBefore = Get-CommandRecord -Name "copilot"
    if (-not $copilotBefore.Available) {
        $existingCopilotCommand = Get-Command copilot -ErrorAction SilentlyContinue
        if (-not $existingCopilotCommand -and (Get-Command winget -ErrorAction SilentlyContinue)) {
            Write-Host "Installing GitHub Copilot CLI with WinGet..." -ForegroundColor Yellow
            Invoke-Checked -FilePath (Get-Command winget).Source -ArgumentList @(
                "install", "--id", "GitHub.Copilot", "--exact", "--source", "winget",
                "--accept-source-agreements", "--accept-package-agreements"
            )
        }
        else {
            $npm = Get-Command npm -ErrorAction Stop
            Write-Host "Installing or repairing GitHub Copilot CLI with npm..." -ForegroundColor Yellow
            Invoke-Checked -FilePath $npm.Source -ArgumentList @("install", "--global", "@github/copilot")
        }
        Refresh-CurrentPath
    }
    else {
        Write-Host "Using existing Copilot CLI installation: $($copilotBefore.Path)" -ForegroundColor Green
    }
}

Write-Section "Detect agent adapters"
$openCode = Get-CommandRecord -Name "opencode"
$copilot = Get-CommandRecord -Name "copilot"
$goose = Get-CommandRecord -Name "goose"
$agy = Get-CommandRecord -Name "agy"

$gooseAcpReady = $false
$gooseEvidence = $goose.Evidence
if ($goose.Available) {
    $gooseAcpProbe = Invoke-Probe -FilePath $goose.Path -ArgumentList @("acp", "--help")
    $gooseAcpReady = (-not $gooseAcpProbe.TimedOut -and $gooseAcpProbe.ExitCode -eq 0)
    $gooseEvidence = if ($gooseAcpReady) {
        "goose acp --help exited successfully."
    }
    else {
        "goose was found, but 'goose acp --help' did not succeed. $($gooseAcpProbe.Output)"
    }
}

$agyAcp = [pscustomobject]@{ Ready = $false; Command = $null; Evidence = $agy.Evidence }
if ($agy.Available) {
    $agyAcp = Test-AgyAcp -AgyPath $agy.Path -ExplicitCommand $AgyAcpCommand
}

$agents = [ordered]@{
    opencode = [ordered]@{
        available = $openCode.Available
        commandPath = $openCode.Path
        version = $openCode.Version
        agentSpec = "opencode"
        integration = "native"
        evidence = if ($openCode.Available) { "Native GNHF adapter. $($openCode.Evidence)" } else { $openCode.Evidence }
    }
    copilot = [ordered]@{
        available = $copilot.Available
        commandPath = $copilot.Path
        version = $copilot.Version
        agentSpec = "copilot"
        integration = "native"
        evidence = if ($copilot.Available) { "Native GNHF adapter. $($copilot.Evidence)" } else { $copilot.Evidence }
    }
    goose = [ordered]@{
        available = ($goose.Available -and $gooseAcpReady)
        commandPath = $goose.Path
        version = $goose.Version
        agentSpec = "acp:goose acp"
        integration = "acp"
        evidence = $gooseEvidence
    }
    agy = [ordered]@{
        available = ($agy.Available -and $agyAcp.Ready)
        commandPath = $agy.Path
        version = $agy.Version
        agentSpec = if ($agyAcp.Ready) { "acp:$($agyAcp.Command)" } else { $null }
        integration = "acp-capability-gated"
        evidence = $agyAcp.Evidence
    }
}

foreach ($entry in $agents.GetEnumerator()) {
    $status = if ($entry.Value.available) { "READY" } else { "BLOCKED" }
    $color = if ($entry.Value.available) { "Green" } else { "Yellow" }
    Write-Host ("{0,-8} {1,-8} {2}" -f $entry.Key, $status, $entry.Value.evidence) -ForegroundColor $color
}

Write-Section "Install or refresh fleet scripts"
$InstallRoot = Ensure-GnhfFleetDirectory -Path $InstallRoot
$promptsRoot = Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "prompts")
[void](Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "logs"))
[void](Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "reports"))
[void](Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "runtime-prompts"))

$filesToCopy = @(
    "GnhfFleet.Paths.ps1",
    "Start-AgentSwitchboard.ps1",
    "Start-GnhfSprint.ps1",
    "Start-GnhfFleet.ps1",
    "Get-GnhfFleetStatus.ps1",
    "Test-GnhfFleetContracts.ps1",
    "Install-AgentSwitchboardGnhf.ps1",
    "README.md"
)

foreach ($file in $filesToCopy) {
    $source = Resolve-GnhfFleetFile -Path (Join-Path $PSScriptRoot $file) -Description "bundle file"
    Copy-Item -LiteralPath $source -Destination (Join-Path $InstallRoot $file) -Force
}

$sourcePromptsRoot = Resolve-GnhfFleetDirectory -Path (Join-Path $PSScriptRoot "prompts") -Description "bundle prompts directory"
$promptFiles = @(Get-ChildItem -LiteralPath $sourcePromptsRoot -File)
if ($promptFiles.Count -eq 0) {
    throw "Bundle prompts directory contains no prompt files: $sourcePromptsRoot"
}
foreach ($promptFile in $promptFiles) {
    Copy-Item -LiteralPath $promptFile.FullName -Destination (Join-Path $promptsRoot $promptFile.Name) -Force
}

$manifestSource = Resolve-GnhfFleetFile -Path (Join-Path $PSScriptRoot "gnhf-fleet.example.json") -Description "fleet manifest template"
$manifestTarget = Join-Path $InstallRoot "gnhf-fleet.json"
if (Test-Path -LiteralPath $manifestTarget) {
    if (-not (Test-Path -LiteralPath $manifestTarget -PathType Leaf)) {
        throw "Expected the fleet manifest path to be a file, but found a directory: $manifestTarget"
    }

    if (-not $ResetManifest) {
        Write-Host "Preserving existing customized fleet manifest: $manifestTarget" -ForegroundColor Green
    }
}

if ($ResetManifest -or -not (Test-Path -LiteralPath $manifestTarget -PathType Leaf)) {
    $manifestText = Get-Content -LiteralPath $manifestSource -Raw
    if ($DefaultRepoPath) {
        $resolvedDefaultRepo = Resolve-GnhfFleetDirectory -Path $DefaultRepoPath -Description "default repository"
        $manifestText = $manifestText.Replace('__REPO_PATH__', $resolvedDefaultRepo.Replace('\', '\\'))
    }
    Set-Content -LiteralPath $manifestTarget -Value $manifestText -Encoding utf8NoBOM
    Write-Host "Wrote fleet manifest: $manifestTarget" -ForegroundColor Green
}

$state = [ordered]@{
    schemaVersion = 1
    installedAt = (Get-Date).ToString("o")
    installRoot = $InstallRoot
    gnhf = [ordered]@{
        commandPath = $gnhf.Path
        sourceRepoPath = $resolvedGnhfRepo
        versionOutput = $gnhf.Version
    }
    agents = $agents
    safety = [ordered]@{
        worktreeByDefault = $true
        pushByDefault = $false
        maxIterationsRequired = $true
        cleanTreeRequired = $true
        directMainWritesForbidden = $true
        preservesExistingManifest = (-not $ResetManifest)
    }
}

$statePath = Join-Path $InstallRoot "state.json"
$state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM

if ($DisableGnhfTelemetry) {
    $env:GNHF_TELEMETRY = "0"
    [Environment]::SetEnvironmentVariable("GNHF_TELEMETRY", "0", "User")
}

$cmdLaunchers = @{
    "Start-GnhfFleet.cmd" = 'pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-GnhfFleet.ps1" %*'
    "agent-switchboard.cmd" = 'pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-AgentSwitchboard.ps1" %*'
}
foreach ($launcher in $cmdLaunchers.GetEnumerator()) {
    $content = "@echo off`r`nsetlocal`r`n$($launcher.Value)`r`nset `_code=%ERRORLEVEL%`r`nendlocal & exit /b %_code%`r`n"
    Set-Content -LiteralPath (Join-Path $InstallRoot $launcher.Key) -Value $content -Encoding ascii
}

Write-Section "Setup complete"
Write-Host "Install root: $InstallRoot" -ForegroundColor Green
Write-Host "State:        $statePath"
Write-Host "Manifest:     $manifestTarget"
Write-Host ""
Write-Host "Existing healthy tools were reused. Missing or unhealthy requested tools were installed or repaired." -ForegroundColor Cyan
Write-Host "Run readiness:"
Write-Host "  pwsh -File `"$InstallRoot\Start-AgentSwitchboard.ps1`" -ListAgents" -ForegroundColor Cyan
Write-Host "Morning review:"
Write-Host "  pwsh -File `"$InstallRoot\Get-GnhfFleetStatus.ps1`" -ManifestPath `"$manifestTarget`"" -ForegroundColor Cyan
