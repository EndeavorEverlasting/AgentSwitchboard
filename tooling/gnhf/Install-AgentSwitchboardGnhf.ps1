[CmdletBinding()]
param(
    [string]$GnhfRepoPath,
    [string]$DevRoot = "$HOME\Desktop\dev",
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [string]$DefaultRepoPath,
    [string]$AgyAcpCommand,
    [switch]$SkipGnhfBuild,
    [switch]$InstallOpenCodeAndCopilot,
    [bool]$DisableGnhfTelemetry = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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
        [Parameter()][string[]]$ArgumentList = @(),
        [Parameter()][string]$WorkingDirectory
    )

    $oldLocation = Get-Location
    try {
        if ($WorkingDirectory) {
            Set-Location -LiteralPath $WorkingDirectory
        }

        Write-Host ("+ {0} {1}" -f $FilePath, ($ArgumentList -join " ")) -ForegroundColor DarkGray
        & $FilePath @ArgumentList
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed with exit code $LASTEXITCODE: $FilePath $($ArgumentList -join ' ')"
        }
    }
    finally {
        Set-Location -LiteralPath $oldLocation.Path
    }
}

function Invoke-Probe {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter()][string[]]$ArgumentList = @(),
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

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $result.TimedOut = $true
            try { $process.Kill($true) } catch {}
        }
        else {
            $result.ExitCode = $process.ExitCode
        }

        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
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
        [void]$candidates.Add($ExplicitPath)
    }

    foreach ($candidate in @(
        (Join-Path $SearchRoot "agents\gnhf"),
        (Join-Path $SearchRoot "gnhf"),
        (Join-Path $HOME "source\repos\gnhf")
    )) {
        if ($candidate) {
            [void]$candidates.Add($candidate)
        }
    }

    if (Test-Path -LiteralPath $SearchRoot) {
        Get-ChildItem -LiteralPath $SearchRoot -Directory -Filter "gnhf" -Recurse -Depth 4 -ErrorAction SilentlyContinue |
            ForEach-Object { [void]$candidates.Add($_.FullName) }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        $packageJson = Join-Path $candidate "package.json"
        if (-not (Test-Path -LiteralPath $packageJson)) {
            continue
        }

        try {
            $package = Get-Content -LiteralPath $packageJson -Raw | ConvertFrom-Json
            if ($package.name -eq "gnhf") {
                return (Resolve-Path -LiteralPath $candidate).Path
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
        }
    }

    $probe = Invoke-Probe -FilePath $command.Source -ArgumentList $VersionArguments
    $version = if ($probe.Output) {
        ($probe.Output -split "\r?\n" | Select-Object -First 1).Trim()
    } else {
        "detected"
    }

    return [pscustomobject]@{
        Name = $Name
        Available = $true
        Path = $command.Source
        Version = $version
    }
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

    $subcommandProbe = Invoke-Probe -FilePath $AgyPath -ArgumentList @("acp", "--help")
    if (-not $subcommandProbe.TimedOut -and $subcommandProbe.ExitCode -eq 0) {
        return [pscustomobject]@{
            Ready = $true
            Command = "agy acp"
            Evidence = "agy acp --help exited successfully."
        }
    }

    $flagProbe = Invoke-Probe -FilePath $AgyPath -ArgumentList @("--acp", "--help")
    if (-not $flagProbe.TimedOut -and $flagProbe.ExitCode -eq 0) {
        return [pscustomobject]@{
            Ready = $true
            Command = "agy --acp"
            Evidence = "agy --acp --help exited successfully."
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

Write-Section "AgentSwitchboard GNHF Fleet Setup"
Refresh-CurrentPath

$resolvedGnhfRepo = Resolve-GnhfClone -ExplicitPath $GnhfRepoPath -SearchRoot $DevRoot

if ($resolvedGnhfRepo) {
    Write-Host "GNHF source clone: $resolvedGnhfRepo" -ForegroundColor Green
}
else {
    Write-Warning "No GNHF source clone was found under '$DevRoot'. An existing global gnhf command can still be used."
}

Write-Section "Build or locate GNHF"

$gnhfCommand = Get-Command gnhf -ErrorAction SilentlyContinue

if (-not $SkipGnhfBuild -and $resolvedGnhfRepo) {
    $node = Get-Command node -ErrorAction SilentlyContinue
    $npm = Get-Command npm -ErrorAction SilentlyContinue

    if (-not $node -or -not $npm) {
        throw "Node.js and npm are required to build the cloned GNHF repository."
    }

    $nodeVersion = (& node --version).TrimStart("v")
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
    Invoke-Checked -FilePath $pnpm -ArgumentList @("install", "--frozen-lockfile") -WorkingDirectory $resolvedGnhfRepo
    Invoke-Checked -FilePath $pnpm -ArgumentList @("run", "build") -WorkingDirectory $resolvedGnhfRepo
    Invoke-Checked -FilePath $pnpm -ArgumentList @("link", "--global") -WorkingDirectory $resolvedGnhfRepo
    Refresh-CurrentPath
    $gnhfCommand = Get-Command gnhf -ErrorAction SilentlyContinue
}

if (-not $gnhfCommand) {
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
        throw "gnhf is not available and npm is unavailable. Build the clone manually, then rerun."
    }

    Write-Host "Installing the published GNHF package because no command is currently available..." -ForegroundColor Yellow
    Invoke-Checked -FilePath (Get-Command npm).Source -ArgumentList @("install", "--global", "gnhf")
    Refresh-CurrentPath
    $gnhfCommand = Get-Command gnhf -ErrorAction SilentlyContinue
}

if (-not $gnhfCommand) {
    throw "GNHF installation completed but the gnhf command is still not visible."
}

$gnhfProbe = Invoke-Probe -FilePath $gnhfCommand.Source -ArgumentList @("--version")
Write-Host "GNHF: $($gnhfProbe.Output)" -ForegroundColor Green

if ($InstallOpenCodeAndCopilot) {
    Write-Section "Install missing native agents"

    if (-not (Get-Command opencode -ErrorAction SilentlyContinue)) {
        $npm = Get-Command npm -ErrorAction Stop
        Invoke-Checked -FilePath $npm.Source -ArgumentList @("install", "--global", "opencode-ai")
        Refresh-CurrentPath
    }

    if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Invoke-Checked -FilePath (Get-Command winget).Source -ArgumentList @(
                "install",
                "--id", "GitHub.Copilot",
                "--exact",
                "--source", "winget",
                "--accept-source-agreements",
                "--accept-package-agreements"
            )
        }
        else {
            $npm = Get-Command npm -ErrorAction Stop
            Invoke-Checked -FilePath $npm.Source -ArgumentList @("install", "--global", "@github/copilot")
        }
        Refresh-CurrentPath
    }
}

Write-Section "Detect agent adapters"

$openCode = Get-CommandRecord -Name "opencode"
$copilot = Get-CommandRecord -Name "copilot"
$goose = Get-CommandRecord -Name "goose"
$agy = Get-CommandRecord -Name "agy"

$gooseAcpReady = $false
$gooseEvidence = "goose command not found."
if ($goose.Available) {
    $gooseAcpProbe = Invoke-Probe -FilePath $goose.Path -ArgumentList @("acp", "--help")
    $gooseAcpReady = (-not $gooseAcpProbe.TimedOut -and $gooseAcpProbe.ExitCode -eq 0)
    $gooseEvidence = if ($gooseAcpReady) {
        "goose acp --help exited successfully."
    } else {
        "goose was found, but 'goose acp --help' did not succeed. $($gooseAcpProbe.Output)"
    }
}

$agyAcp = [pscustomobject]@{
    Ready = $false
    Command = $null
    Evidence = "agy command not found."
}
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
        evidence = if ($openCode.Available) { "Native GNHF adapter." } else { "opencode command not found." }
    }
    copilot = [ordered]@{
        available = $copilot.Available
        commandPath = $copilot.Path
        version = $copilot.Version
        agentSpec = "copilot"
        integration = "native"
        evidence = if ($copilot.Available) { "Native GNHF adapter." } else { "copilot command not found." }
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

Write-Section "Install fleet scripts"

New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallRoot "prompts") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallRoot "logs") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallRoot "reports") -Force | Out-Null

$filesToCopy = @(
    "Start-GnhfSprint.ps1",
    "Start-GnhfFleet.ps1",
    "Get-GnhfFleetStatus.ps1",
    "Install-AgentSwitchboardGnhf.ps1",
    "README.md"
)

foreach ($file in $filesToCopy) {
    $source = Join-Path $PSScriptRoot $file
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Bundle file missing: $source"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $InstallRoot $file) -Force
}

Copy-Item -Path (Join-Path $PSScriptRoot "prompts\*") -Destination (Join-Path $InstallRoot "prompts") -Recurse -Force

$manifestSource = Join-Path $PSScriptRoot "gnhf-fleet.example.json"
$manifestTarget = Join-Path $InstallRoot "gnhf-fleet.json"
$manifestText = Get-Content -LiteralPath $manifestSource -Raw
if ($DefaultRepoPath) {
    $resolvedDefaultRepo = (Resolve-Path -LiteralPath $DefaultRepoPath).Path
    $manifestText = $manifestText.Replace('__REPO_PATH__', $resolvedDefaultRepo.Replace('\', '\\'))
}
Set-Content -LiteralPath $manifestTarget -Value $manifestText -Encoding utf8NoBOM

$state = [ordered]@{
    schemaVersion = 1
    installedAt = (Get-Date).ToString("o")
    installRoot = $InstallRoot
    gnhf = [ordered]@{
        commandPath = $gnhfCommand.Source
        sourceRepoPath = $resolvedGnhfRepo
        versionOutput = $gnhfProbe.Output
    }
    agents = $agents
    safety = [ordered]@{
        worktreeByDefault = $true
        pushByDefault = $false
        maxIterationsRequired = $true
        cleanTreeRequired = $true
        directMainWritesForbidden = $true
    }
}

$statePath = Join-Path $InstallRoot "state.json"
$state | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM

if ($DisableGnhfTelemetry) {
    $env:GNHF_TELEMETRY = "0"
    [Environment]::SetEnvironmentVariable("GNHF_TELEMETRY", "0", "User")
}

$cmdLauncher = @'
@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-GnhfFleet.ps1" %*
endlocal
'@
Set-Content -LiteralPath (Join-Path $InstallRoot "Start-GnhfFleet.cmd") -Value $cmdLauncher -Encoding ascii

Write-Section "Setup complete"
Write-Host "Install root: $InstallRoot" -ForegroundColor Green
Write-Host "State:        $statePath"
Write-Host "Manifest:     $manifestTarget"
Write-Host ""
Write-Host "One-time authentication still happens inside each agent's own CLI." -ForegroundColor Yellow
Write-Host "Then launch with:"
Write-Host "  pwsh -File `"$InstallRoot\Start-GnhfFleet.ps1`" -ManifestPath `"$manifestTarget`"" -ForegroundColor Cyan
Write-Host ""
Write-Host "Morning review:"
Write-Host "  pwsh -File `"$InstallRoot\Get-GnhfFleetStatus.ps1`" -ManifestPath `"$manifestTarget`"" -ForegroundColor Cyan
