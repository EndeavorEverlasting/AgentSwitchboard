[CmdletBinding()]
param(
    [switch]$Apply,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [string]$RequiredGnhfVersion = "0.1.42",
    [string]$GnhfRepoPath,
    [string]$DevRoot = "$HOME\Desktop\dev"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 is required."
}

function Refresh-ProviderRoutePath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath;$(Join-Path $env:APPDATA 'npm');$(Join-Path $HOME '.local\bin')"
}

function Get-GnhfCommandState {
    $command = Get-Command gnhf -ErrorAction SilentlyContinue
    $version = $null
    $hasModelFlag = $false
    if (-not $command) {
        return [pscustomobject]@{
            Command = $null
            Version = $null
            HasModelFlag = $false
        }
    }

    $versionText = (& $command.Source --version 2>&1 | Out-String).Trim()
    $match = [regex]::Match($versionText, '(?<!\d)(\d+\.\d+\.\d+)(?!\d)')
    if ($match.Success) {
        $version = [version]$match.Groups[1].Value
    }
    $helpText = (& $command.Source --help 2>&1 | Out-String)
    $hasModelFlag = $helpText -match '(?m)^\s*(-m,\s*)?--model\b'
    return [pscustomobject]@{
        Command = $command
        Version = $version
        HasModelFlag = $hasModelFlag
    }
}

function Resolve-ProviderRouteGnhfClone {
    param(
        [string]$ExplicitPath,
        [string]$SearchRoot
    )

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($ExplicitPath) {
        [void]$candidates.Add([IO.Path]::GetFullPath($ExplicitPath))
    }

    foreach ($candidate in @(
        (Join-Path $SearchRoot "agents\gnhf"),
        (Join-Path $SearchRoot "gnhf\gnhf"),
        (Join-Path $SearchRoot "gnhf")
    )) {
        [void]$candidates.Add([IO.Path]::GetFullPath($candidate))
    }

    if (Test-Path -LiteralPath $SearchRoot -PathType Container) {
        Get-ChildItem -LiteralPath $SearchRoot -Directory -Filter "gnhf" -Recurse -Depth 4 -ErrorAction SilentlyContinue |
            ForEach-Object { [void]$candidates.Add($_.FullName) }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
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

function Install-ProviderRouteGnhfFromSource {
    param(
        [Parameter(Mandatory)][string]$RepoPath,
        [Parameter(Mandatory)][version]$RequiredVersion
    )

    $packageJson = Join-Path $RepoPath "package.json"
    $package = Get-Content -LiteralPath $packageJson -Raw | ConvertFrom-Json
    $sourceVersion = [version]$package.version
    if ($sourceVersion -lt $RequiredVersion) {
        throw "Local GNHF clone at $RepoPath is $sourceVersion; provider route requires $RequiredVersion or newer."
    }

    $npm = Get-Command npm -ErrorAction Stop
    if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
        Write-Host "Installing pnpm 11.1.1 required by the GNHF source checkout..." -ForegroundColor Yellow
        & $npm.Source install --global "pnpm@11.1.1"
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install pnpm for local GNHF build."
        }
        Refresh-ProviderRoutePath
    }

    $pnpm = (Get-Command pnpm -ErrorAction Stop).Source
    $oldLocation = Get-Location
    try {
        Set-Location -LiteralPath $RepoPath
        Write-Host "Building GNHF $sourceVersion from $RepoPath..." -ForegroundColor Yellow
        & $pnpm install --frozen-lockfile
        if ($LASTEXITCODE -ne 0) { throw "pnpm install failed in $RepoPath." }
        & $pnpm run build
        if ($LASTEXITCODE -ne 0) { throw "pnpm build failed in $RepoPath." }

        $cli = Join-Path $RepoPath "dist\cli.mjs"
        if (-not (Test-Path -LiteralPath $cli -PathType Leaf)) {
            throw "GNHF build did not produce dist/cli.mjs in $RepoPath."
        }

        # Prefer npm global install of the built package. pnpm link --global often fails on
        # Windows when the pnpm global bin directory is absent from PATH.
        Write-Host "Installing built GNHF globally with npm..." -ForegroundColor Yellow
        & $npm.Source install --global .
        if ($LASTEXITCODE -ne 0) {
            throw "npm install --global . failed after building GNHF in $RepoPath."
        }
    }
    finally {
        Set-Location -LiteralPath $oldLocation.Path
    }

    Refresh-ProviderRoutePath
}

$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ".git"))) {
    throw "AgentSwitchboard repository not found from installer: $RepoRoot"
}

# Directory first: installation and validation begin only after entering AgentSwitchboard.
Set-Location -LiteralPath $RepoRoot

$required = [version]$RequiredGnhfVersion
$gnhfState = Get-GnhfCommandState
$detectedVersion = $gnhfState.Version
$hasModelFlag = [bool]$gnhfState.HasModelFlag
$gnhfCommand = $gnhfState.Command
$needsRepair = ($null -eq $detectedVersion -or $detectedVersion -lt $required)
$resolvedSource = Resolve-ProviderRouteGnhfClone -ExplicitPath $GnhfRepoPath -SearchRoot $DevRoot

Write-Host "`n=== Provider-routed GNHF installation plan ===" -ForegroundColor Cyan
Write-Host "Repository:       $RepoRoot"
Write-Host "Install root:     $InstallRoot"
Write-Host "Required GNHF:    $required"
Write-Host "Detected GNHF:    $(if ($detectedVersion) { $detectedVersion } else { '<unavailable>' })"
Write-Host "GNHF --model CLI: $hasModelFlag"
Write-Host "Exact model route: OpenCode preflight + OPENCODE_CONFIG_CONTENT"
Write-Host "Local GNHF source: $(if ($resolvedSource) { $resolvedSource } else { '<not found>' })"
Write-Host "GNHF repair:      $needsRepair"
Write-Host "Apply:            $([bool]$Apply)"

if (-not $Apply) {
    Write-Host "`nPlan only. Rerun with -Apply to install the pinned runtime and launchers." -ForegroundColor Yellow
    return
}

if ($needsRepair) {
    $npm = Get-Command npm -ErrorAction Stop
    $npmSucceeded = $false
    Write-Host "Installing gnhf@$required from npm..." -ForegroundColor Yellow
    & $npm.Source install --global "gnhf@$required" 2>&1 | Tee-Object -Variable npmOutput | Out-Host
    if ($LASTEXITCODE -eq 0) {
        $npmSucceeded = $true
    }
    else {
        $npmText = ($npmOutput | Out-String)
        if ($npmText -notmatch 'ETARGET|No matching version found') {
            throw "npm failed to install gnhf@$required.`n$npmText"
        }
        Write-Host "npm does not publish gnhf@$required yet; falling back to a local GNHF source clone." -ForegroundColor Yellow
        if (-not $resolvedSource) {
            throw @"
npm package gnhf@$required is unavailable, and no local GNHF clone was found.
Clone https://github.com/kunchenguid/gnhf (release $required or newer) under '$DevRoot' or pass -GnhfRepoPath.
"@
        }
        Install-ProviderRouteGnhfFromSource -RepoPath $resolvedSource -RequiredVersion $required
    }

    Refresh-ProviderRoutePath
    $gnhfState = Get-GnhfCommandState
    $gnhfCommand = $gnhfState.Command
    $detectedVersion = $gnhfState.Version
    $hasModelFlag = [bool]$gnhfState.HasModelFlag
    if (-not $gnhfCommand -or $null -eq $detectedVersion -or $detectedVersion -lt $required) {
        $sourceNote = if ($npmSucceeded) { "npm" } else { "local source $resolvedSource" }
        throw "GNHF repair via $sourceNote completed but required version $required was not observed."
    }
}

# Pin GNHF to the native OpenCode executable so Windows shell:true serve spawn works.
$processHelpers = Join-Path $PSScriptRoot "Gnhf.Process.ps1"
. $processHelpers
$openCodeNative = $null
$gnhfPathPin = $null
try {
    $openCodeNative = Resolve-OpenCodeNativeExecutable
    $gnhfPathPin = Set-GnhfOpenCodeNativePathOverride -OpenCodeExePath $openCodeNative
    Write-Host "OpenCode native: $openCodeNative"
    Write-Host "GNHF path pin:   $($gnhfPathPin.configPath) ($($gnhfPathPin.action))"
}
catch {
    Write-Host "OpenCode native path pin skipped: $($_.Exception.Message)" -ForegroundColor Yellow
}

[void](New-Item -ItemType Directory -Path $InstallRoot -Force)
foreach ($file in @("Gnhf.Process.ps1", "Start-ProviderRoutedGnhfSprint.ps1")) {
    $source = Join-Path $PSScriptRoot $file
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required provider-route file is missing: $source"
    }
    Copy-Item -LiteralPath $source -Destination (Join-Path $InstallRoot $file) -Force
}

$launcher = @'
@echo off
setlocal
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-ProviderRoutedGnhfSprint.ps1" %*
set "_code=%ERRORLEVEL%"
endlocal & exit /b %_code%
'@
Set-Content -LiteralPath (Join-Path $InstallRoot "agent-switchboard-provider.cmd") -Value $launcher -Encoding ascii

$statePath = Join-Path $InstallRoot "state.json"
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $state.gnhf.commandPath = $gnhfCommand.Source
    $state.gnhf.versionOutput = $detectedVersion.ToString()
    if (-not $state.gnhf.PSObject.Properties["requiredProviderRouteVersion"]) {
        $state.gnhf | Add-Member -NotePropertyName requiredProviderRouteVersion -NotePropertyValue $required.ToString()
    }
    else {
        $state.gnhf.requiredProviderRouteVersion = $required.ToString()
    }
    if (-not $state.gnhf.PSObject.Properties["modelFlagVerified"]) {
        $state.gnhf | Add-Member -NotePropertyName modelFlagVerified -NotePropertyValue $true
    }
    else {
        # Exact model selection is enforced by OpenCode preflight and OPENCODE_CONFIG_CONTENT.
        $state.gnhf.modelFlagVerified = $true
    }
    if (-not $state.gnhf.PSObject.Properties["gnhfCliModelFlag"]) {
        $state.gnhf | Add-Member -NotePropertyName gnhfCliModelFlag -NotePropertyValue $hasModelFlag
    }
    else {
        $state.gnhf.gnhfCliModelFlag = $hasModelFlag
    }
    if ($resolvedSource) {
        if (-not $state.gnhf.PSObject.Properties["sourceRepoPath"]) {
            $state.gnhf | Add-Member -NotePropertyName sourceRepoPath -NotePropertyValue $resolvedSource
        }
        else {
            $state.gnhf.sourceRepoPath = $resolvedSource
        }
    }
    if ($openCodeNative -and $state.agents -and $state.agents.opencode) {
        $state.agents.opencode.commandPath = $openCodeNative
        if (-not $state.agents.opencode.PSObject.Properties["nativeExecutable"]) {
            $state.agents.opencode | Add-Member -NotePropertyName nativeExecutable -NotePropertyValue $true
        }
        else {
            $state.agents.opencode.nativeExecutable = $true
        }
    }
    if ($gnhfPathPin) {
        if (-not $state.PSObject.Properties["gnhfOpenCodePathOverride"]) {
            $state | Add-Member -NotePropertyName gnhfOpenCodePathOverride -NotePropertyValue $gnhfPathPin.configPath
        }
        else {
            $state.gnhfOpenCodePathOverride = $gnhfPathPin.configPath
        }
    }
    $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath -Encoding utf8NoBOM
}

Write-Host "`nProvider-routed GNHF installed." -ForegroundColor Green
Write-Host "GNHF:            $detectedVersion"
Write-Host "GNHF --model CLI: $hasModelFlag"
Write-Host "Model authority: OpenCode preflight + OPENCODE_CONFIG_CONTENT"
Write-Host "Launcher:        $(Join-Path $InstallRoot 'agent-switchboard-provider.cmd')"
Write-Host "Script:          $(Join-Path $InstallRoot 'Start-ProviderRoutedGnhfSprint.ps1')"
