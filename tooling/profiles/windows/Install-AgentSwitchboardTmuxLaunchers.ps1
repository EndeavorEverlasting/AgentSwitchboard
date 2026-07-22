[CmdletBinding()]
param(
    [ValidateSet('Plan', 'Apply')]
    [string]$Mode = 'Apply',

    [string]$ManifestPath = (Join-Path $PSScriptRoot 'windows-tmux-launch.json'),

    [string]$InstallRoot,

    [string]$DesktopDirectory,

    [string]$PwshPath,

    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-Pwsh {
    param([string]$RequestedPath)

    if ($RequestedPath) { return (Resolve-Path -LiteralPath $RequestedPath -ErrorAction Stop).Path }
    $command = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if (-not $command) { $command = Get-Command pwsh -ErrorAction SilentlyContinue }
    if ($command) { return $command.Source }

    $candidate = if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe' } else { $null }
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    throw 'PowerShell 7 was not found.'
}

function Copy-FileAtomically {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force
    $temporary = "$Destination.$([guid]::NewGuid().ToString('N')).tmp"
    Copy-Item -LiteralPath $Source -Destination $temporary -Force
    Move-Item -LiteralPath $temporary -Destination $Destination -Force
}

function Write-JsonArtifact {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][string]$Path
    )

    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

$manifestPathResolved = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$manifest = Get-Content -LiteralPath $manifestPathResolved -Raw | ConvertFrom-Json
if ($manifest.schema -ne 'agentswitchboard.windows-tmux-launch.v1') {
    throw "Unsupported manifest schema: $($manifest.schema)"
}

$launcherSource = Join-Path $PSScriptRoot 'Invoke-AgentSwitchboardTmuxLaunch.ps1'
if (-not (Test-Path -LiteralPath $launcherSource -PathType Leaf)) {
    throw "Canonical launcher missing: $launcherSource"
}

$resolvedInstallRoot = if ($InstallRoot) {
    [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($InstallRoot))
}
else {
    [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$manifest.installRoot))
}

$resolvedDesktop = if ($DesktopDirectory) {
    [System.IO.Path]::GetFullPath($DesktopDirectory)
}
else {
    [Environment]::GetFolderPath('Desktop')
}
if (-not $resolvedDesktop) { throw 'Windows Desktop could not be resolved.' }

$installedLauncher = Join-Path $resolvedInstallRoot 'Invoke-AgentSwitchboardTmuxLaunch.ps1'
$installedManifest = Join-Path $resolvedInstallRoot 'windows-tmux-launch.json'
$continueCmd = Join-Path $resolvedDesktop ([string]$manifest.desktopLaunchers.continue)
$newCmd = Join-Path $resolvedDesktop ([string]$manifest.desktopLaunchers.new)
$stateRoot = Join-Path $resolvedInstallRoot 'state'

if (-not $OutputDirectory) {
    $OutputDirectory = if ($Mode -eq 'Apply') { $stateRoot } else { Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard/windows-tmux-launch-plan' }
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

$resolvedPwsh = if ($Mode -eq 'Apply') { Resolve-Pwsh -RequestedPath $PwshPath } else { '<resolved during apply>' }

$continueArguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$installedLauncher`" -Mode continue -Operation Launch -ManifestPath `"$installedManifest`""
$newArguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$installedLauncher`" -Mode new -Operation Launch -ManifestPath `"$installedManifest`""

$legacyObserved = @()
foreach ($legacyName in @($manifest.legacySurfaces)) {
    $legacyPath = Join-Path $resolvedDesktop ([string]$legacyName)
    if (Test-Path -LiteralPath $legacyPath) { $legacyObserved += $legacyPath }
}

$plan = [ordered]@{
    schema = 'agentswitchboard.windows-tmux-launch-install-plan.v1'
    mode = $Mode
    installRoot = $resolvedInstallRoot
    installedLauncher = $installedLauncher
    installedManifest = $installedManifest
    desktopDirectory = $resolvedDesktop
    continueLauncher = $continueCmd
    newLauncher = $newCmd
    continueArguments = $continueArguments
    newArguments = $newArguments
    legacySurfacesObserved = $legacyObserved
    legacySurfacesModified = $false
    launchesDuringInstall = $false
    generatedEvidenceTracked = $false
    proofCeiling = 'Installed-file and launcher-content proof only. Runtime behavior requires the separate live certificate.'
}
Write-JsonArtifact -Value $plan -Path (Join-Path $OutputDirectory 'windows-tmux-launch-install-plan.json')

if ($Mode -eq 'Plan') {
    $plan | ConvertTo-Json -Depth 10
    exit 0
}
if ($env:OS -ne 'Windows_NT') { throw 'Apply mode is supported only on Windows.' }

$null = New-Item -ItemType Directory -Path $resolvedInstallRoot -Force
$null = New-Item -ItemType Directory -Path $resolvedDesktop -Force
$null = New-Item -ItemType Directory -Path $stateRoot -Force

Copy-FileAtomically -Source $launcherSource -Destination $installedLauncher
Copy-FileAtomically -Source $manifestPathResolved -Destination $installedManifest

$continueBody = @"
@echo off
setlocal
`"$resolvedPwsh`" $continueArguments
set `"_code=%ERRORLEVEL%`"
endlocal & exit /b %_code%
"@
$newBody = @"
@echo off
setlocal
`"$resolvedPwsh`" $newArguments
set `"_code=%ERRORLEVEL%`"
endlocal & exit /b %_code%
"@

Set-Content -LiteralPath $continueCmd -Value $continueBody -Encoding ascii
Set-Content -LiteralPath $newCmd -Value $newBody -Encoding ascii

$continueReadback = Get-Content -LiteralPath $continueCmd -Raw
$newReadback = Get-Content -LiteralPath $newCmd -Raw
if ($continueReadback -notmatch '-Mode continue' -or $continueReadback -match '-Mode new') {
    throw 'Continue launcher readback violated the mode contract.'
}
if ($newReadback -notmatch '-Mode new' -or $newReadback -match '-Mode continue') {
    throw 'New-instance launcher readback violated the mode contract.'
}

$receipt = [ordered]@{
    schema = 'agentswitchboard.windows-tmux-launch-install-receipt.v1'
    status = 'installed'
    installedAt = (Get-Date).ToUniversalTime().ToString('o')
    installRoot = $resolvedInstallRoot
    launcher = $installedLauncher
    manifest = $installedManifest
    continueLauncher = $continueCmd
    newLauncher = $newCmd
    legacySurfacesObserved = $legacyObserved
    legacySurfacesModified = $false
    runtimeExecuted = $false
    proofLevel = 'installed-launcher-readback'
    proofCeiling = [string]$plan.proofCeiling
}
$receiptPath = Join-Path $stateRoot 'windows-tmux-launch-install-receipt.json'
Write-JsonArtifact -Value $receipt -Path $receiptPath

@(
    '# AgentSwitchboard Windows tmux launchers',
    '',
    '- Continue Work: activates the marked continue frontend when present; otherwise attaches one frontend to `dev`.',
    '- New Instance: allocates the first unused `dev-N` session and starts one separate WezTerm process.',
    '- Legacy launchers: observed and preserved; they are not authoritative.',
    ('- Continue launcher: `{0}`' -f $continueCmd),
    ('- New launcher: `{0}`' -f $newCmd),
    ('- Receipt: `{0}`' -f $receiptPath),
    '',
    'Runtime was not executed by installation. Run the repository live certificate before claiming visible-window behavior.'
) | Set-Content -LiteralPath (Join-Path $stateRoot 'windows-tmux-launch-operator-report.md') -Encoding utf8NoBOM

$receipt | ConvertTo-Json -Depth 10
