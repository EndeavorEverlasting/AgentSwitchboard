[CmdletBinding()]
param(
    [ValidateSet("Core", "GnhfNative", "All", "None")]
    [string]$InstallProfile = "Core",
    [ValidateSet("goose", "opencode", "agy", "copilot", "claude", "codex", "pi", "gemini")]
    [string[]]$InstallAgent = @(),
    [string]$GnhfRepoPath,
    [string]$DefaultRepoPath,
    [string]$DevRoot = "$HOME\Desktop\dev",
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [string]$AgyAcpCommand,
    [switch]$SkipGnhfBuild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 is required. Run this script with pwsh."
}

function Write-Section {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host "`n=== $Text ===" -ForegroundColor Cyan
}

function Refresh-CurrentPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $npmPath = Join-Path $env:APPDATA "npm"
    $localBin = Join-Path $HOME ".local\bin"
    $env:Path = (@($machinePath, $userPath, $npmPath, $localBin) | Where-Object { $_ }) -join ";"
}

function Add-UserPathEntry {
    param([Parameter(Mandatory)][string]$Path)

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $entries = @($userPath -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (-not ($entries | Where-Object { $_.TrimEnd("\") -ieq $Path.TrimEnd("\") })) {
        [Environment]::SetEnvironmentVariable("Path", ((@($entries) + $Path) -join ";"), "User")
    }
    Refresh-CurrentPath
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
            Set-Location -LiteralPath $WorkingDirectory
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

function Invoke-DownloadedPowerShellInstaller {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][uri]$Uri,
        [hashtable]$Environment = @{}
    )

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("AgentSwitchboard-{0}-{1}" -f $Name, [guid]::NewGuid().ToString("N"))
    $scriptPath = Join-Path $tempRoot "install.ps1"
    $previousEnvironment = @{}

    try {
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
        Write-Host "Downloading official $Name installer from $Uri" -ForegroundColor Yellow
        Invoke-WebRequest -Uri $Uri -OutFile $scriptPath -UseBasicParsing

        foreach ($entry in $Environment.GetEnumerator()) {
            $previousEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, "Process")
            [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, "Process")
        }

        Invoke-Checked -FilePath (Get-Command pwsh -ErrorAction Stop).Source -ArgumentList @(
            "-NoLogo",
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $scriptPath
        ) -WorkingDirectory $tempRoot
    }
    finally {
        foreach ($entry in $previousEnvironment.GetEnumerator()) {
            [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
        }
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-NpmAgent {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Package
    )

    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if (-not $npm) {
        throw "$Name requires Node.js and npm. Install Node.js 20 or newer, then rerun."
    }
    Write-Host "Installing $Name from '$Package'..." -ForegroundColor Yellow
    Invoke-Checked -FilePath $npm.Source -ArgumentList @("install", "--global", $Package)
}

function Get-CommandEvidence {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$VersionArguments = @("--version")
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        return [ordered]@{
            installed = $false
            commandPath = $null
            version = $null
            evidence = "$Name command not found."
        }
    }

    $LASTEXITCODE = 0
    $output = & $command.Source @VersionArguments 2>&1
    $exitCode = $LASTEXITCODE
    $firstLine = ($output | Select-Object -First 1) -as [string]
    $version = if ($exitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($firstLine)) { $firstLine.Trim() } elseif ($exitCode -eq 0) { "detected" } else { $null }
    return [ordered]@{
        installed = ($exitCode -eq 0)
        commandPath = $command.Source
        version = $version
        evidence = if ($exitCode -eq 0) { "$Name version probe exited successfully." } else { "$Name version probe failed with exit code $exitCode. $($output -join ' ')" }
    }
}

$profileAgents = switch ($InstallProfile) {
    "None" { @() }
    "Core" { @("goose", "opencode", "agy") }
    "GnhfNative" { @("opencode", "copilot", "claude", "codex", "pi") }
    "All" { @("goose", "opencode", "agy", "copilot", "claude", "codex", "pi") }
}

$requestedAgents = [System.Collections.Generic.List[string]]::new()
foreach ($agentName in @($profileAgents) + @($InstallAgent)) {
    if (-not [string]::IsNullOrWhiteSpace($agentName)) {
        $normalized = $agentName.ToLowerInvariant()
        if (-not $requestedAgents.Contains($normalized)) {
            [void]$requestedAgents.Add($normalized)
        }
    }
}

Write-Section "AgentSwitchboard workstation bootstrap"
Write-Host "Profile: $InstallProfile"
Write-Host "Agents:  $($requestedAgents -join ', ')"
Refresh-CurrentPath

$actions = [System.Collections.Generic.List[object]]::new()
foreach ($agentName in $requestedAgents) {
    $existing = Get-Command $agentName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "$agentName already present at $($existing.Source)" -ForegroundColor Green
        [void]$actions.Add([ordered]@{ agent = $agentName; action = "already-present"; commandPath = $existing.Source })
        continue
    }

    Write-Section "Install $agentName"
    switch ($agentName) {
        "goose" {
            $gooseBin = Join-Path $HOME ".local\bin"
            Add-UserPathEntry -Path $gooseBin
            Invoke-DownloadedPowerShellInstaller `
                -Name "goose" `
                -Uri "https://github.com/aaif-goose/goose/releases/download/stable/download_cli.ps1" `
                -Environment @{ CONFIGURE = "false"; GOOSE_BIN_DIR = $gooseBin }
        }
        "agy" {
            Invoke-DownloadedPowerShellInstaller `
                -Name "agy" `
                -Uri "https://antigravity.google/cli/install.ps1"
        }
        "claude" {
            Invoke-DownloadedPowerShellInstaller `
                -Name "claude" `
                -Uri "https://claude.ai/install.ps1"
        }
        "codex" {
            Invoke-DownloadedPowerShellInstaller `
                -Name "codex" `
                -Uri "https://chatgpt.com/codex/install.ps1"
        }
        "opencode" { Install-NpmAgent -Name "OpenCode" -Package "opencode-ai@latest" }
        "copilot" { Install-NpmAgent -Name "GitHub Copilot CLI" -Package "@github/copilot@latest" }
        "pi" { Install-NpmAgent -Name "Pi coding agent" -Package "@earendil-works/pi-coding-agent@latest" }
        "gemini" { Install-NpmAgent -Name "Gemini CLI" -Package "@google/gemini-cli@latest" }
        default { throw "No allowlisted installer exists for '$agentName'." }
    }

    Refresh-CurrentPath
    $installed = Get-Command $agentName -ErrorAction SilentlyContinue
    if (-not $installed) {
        throw "$agentName installation completed, but the command is not visible on PATH. Open a new PowerShell session and rerun with -InstallProfile None."
    }
    [void]$actions.Add([ordered]@{ agent = $agentName; action = "installed"; commandPath = $installed.Source })
}

Write-Section "Install and detect GNHF fleet"
$fleetInstaller = Join-Path $PSScriptRoot "Install-AgentSwitchboardGnhf.ps1"
if (-not (Test-Path -LiteralPath $fleetInstaller)) {
    throw "Required fleet installer is missing: $fleetInstaller"
}

$fleetArguments = [System.Collections.Generic.List[string]]::new()
[void]$fleetArguments.Add("-NoLogo")
[void]$fleetArguments.Add("-NoProfile")
[void]$fleetArguments.Add("-ExecutionPolicy")
[void]$fleetArguments.Add("Bypass")
[void]$fleetArguments.Add("-File")
[void]$fleetArguments.Add($fleetInstaller)
[void]$fleetArguments.Add("-DevRoot")
[void]$fleetArguments.Add($DevRoot)
[void]$fleetArguments.Add("-InstallRoot")
[void]$fleetArguments.Add($InstallRoot)
if ($GnhfRepoPath) {
    [void]$fleetArguments.Add("-GnhfRepoPath")
    [void]$fleetArguments.Add($GnhfRepoPath)
}
if ($DefaultRepoPath) {
    [void]$fleetArguments.Add("-DefaultRepoPath")
    [void]$fleetArguments.Add($DefaultRepoPath)
}
if ($AgyAcpCommand) {
    [void]$fleetArguments.Add("-AgyAcpCommand")
    [void]$fleetArguments.Add($AgyAcpCommand)
}
if ($SkipGnhfBuild) {
    [void]$fleetArguments.Add("-SkipGnhfBuild")
}

Invoke-Checked -FilePath (Get-Command pwsh -ErrorAction Stop).Source -ArgumentList $fleetArguments.ToArray()

Write-Section "Record workstation install evidence"
$statePath = Join-Path $InstallRoot "state.json"
if (-not (Test-Path -LiteralPath $statePath)) {
    throw "Fleet installer did not produce state: $statePath"
}

$state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable
$evidence = [ordered]@{}
foreach ($commandName in @("goose", "opencode", "agy", "copilot", "claude", "codex", "pi", "gemini", "acli")) {
    $evidence[$commandName] = Get-CommandEvidence -Name $commandName
}

$state["workstationInstall"] = [ordered]@{
    schemaVersion = 1
    completedAt = (Get-Date).ToString("o")
    profile = $InstallProfile
    requestedAgents = @($requestedAgents)
    actions = @($actions)
    evidence = $evidence
    remoteInstallerPolicy = "official allowlist only; temporary download and cleanup"
    modelConfiguration = "not stored; authenticate and choose providers inside each agent CLI"
    agyBoundary = "installed for interactive use; GNHF requires a separately verified ACP server command"
}
$state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM

Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $InstallRoot "Install-AgentSwitchboardWorkstation.ps1") -Force

$reportPath = Join-Path $InstallRoot "workstation-install-report.json"
$state["workstationInstall"] | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM

Write-Section "Workstation bootstrap complete"
Write-Host "State:  $statePath" -ForegroundColor Green
Write-Host "Report: $reportPath" -ForegroundColor Green
Write-Host ""
Write-Host "Agent CLIs are installed. Models, subscriptions, and provider credentials are configured inside each CLI." -ForegroundColor Yellow
Write-Host "Run the tools you plan to use once to complete authentication:"
Write-Host "  goose | opencode | agy | copilot | claude | codex | pi"
Write-Host ""
Write-Host "AGY is installed for direct interactive use. It is not marked GNHF-ready unless ACP is separately verified." -ForegroundColor Yellow
