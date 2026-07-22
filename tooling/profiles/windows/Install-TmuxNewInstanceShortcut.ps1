[CmdletBinding()]
param(
    [ValidateSet('Plan', 'Apply')]
    [string]$Mode = 'Apply',

    [string]$ManifestPath = (Join-Path $PSScriptRoot 'tmux-new-instance-shortcut.example.json'),

    [string]$InstallRoot,

    [string]$DesktopDirectory,

    [string]$PwshPath,

    [string]$WezTermPath,

    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-Executable {
    param(
        [string]$RequestedPath,
        [string[]]$CommandNames,
        [string[]]$Candidates,
        [string]$DisplayName
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        return (Resolve-Path -LiteralPath $RequestedPath -ErrorAction Stop).Path
    }

    foreach ($name in $CommandNames) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($command) { return $command.Source }
    }

    foreach ($candidate in $Candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw "$DisplayName was not found."
}

function Write-JsonArtifact {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][string]$Path
    )

    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force
    $Value | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Copy-FileAtomically {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $directory = Split-Path -Parent $Destination
    $null = New-Item -ItemType Directory -Path $directory -Force
    $temporary = "$Destination.$([guid]::NewGuid().ToString('N')).tmp"
    Copy-Item -LiteralPath $Source -Destination $temporary -Force
    Move-Item -LiteralPath $temporary -Destination $Destination -Force
}

$resolvedManifestPath = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
if ($manifest.schema -ne 'agentswitchboard.tmux-new-instance-shortcut-manifest.v1') {
    throw "Unsupported manifest schema: $($manifest.schema)"
}
if ($manifest.profileId -ne 'windows' -or $manifest.runtimeMode -ne 'new-instance') {
    throw 'The shortcut manifest must target the Windows Profile new-instance mode.'
}
if ($manifest.instanceId -ne 'auto') {
    throw 'The desktop shortcut must use automatic unique instance allocation.'
}

$launcherSource = Join-Path $PSScriptRoot 'Invoke-AgentSwitchboardOpenOrActivate.ps1'
if (-not (Test-Path -LiteralPath $launcherSource -PathType Leaf)) {
    throw "Canonical Windows Profile launcher is missing: $launcherSource"
}

$resolvedInstallRoot = if (-not [string]::IsNullOrWhiteSpace($InstallRoot)) {
    [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($InstallRoot))
}
else {
    [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$manifest.installRoot))
}

$resolvedDesktop = if (-not [string]::IsNullOrWhiteSpace($DesktopDirectory)) {
    [System.IO.Path]::GetFullPath($DesktopDirectory)
}
else {
    [Environment]::GetFolderPath('Desktop')
}
if ([string]::IsNullOrWhiteSpace($resolvedDesktop)) {
    throw 'The Windows desktop directory could not be resolved.'
}

$installedLauncherPath = Join-Path $resolvedInstallRoot ([string]$manifest.installedLauncherName)
$installedManifestPath = Join-Path $resolvedInstallRoot ([string]$manifest.installedManifestName)
$shortcutPath = Join-Path $resolvedDesktop ("{0}.lnk" -f [string]$manifest.shortcutName)
$stateRoot = Join-Path $resolvedInstallRoot 'state'

$pwshCandidates = @()
if ($env:ProgramFiles) {
    $pwshCandidates += (Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe')
}
$wezTermCandidates = @()
if ($env:ProgramFiles) {
    $wezTermCandidates += (Join-Path $env:ProgramFiles 'WezTerm\wezterm.exe')
}
if ($env:LOCALAPPDATA) {
    $wezTermCandidates += (Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm.exe')
}

$resolvedPwsh = $null
$resolvedWezTerm = $null
if ($Mode -eq 'Apply') {
    $resolvedPwsh = Resolve-Executable -RequestedPath $PwshPath -CommandNames @('pwsh.exe', 'pwsh') -Candidates $pwshCandidates -DisplayName 'PowerShell 7'
    $resolvedWezTerm = Resolve-Executable -RequestedPath $WezTermPath -CommandNames @('wezterm.exe', 'wezterm') -Candidates $wezTermCandidates -DisplayName 'WezTerm CLI'
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = if ($Mode -eq 'Apply') {
        $stateRoot
    }
    else {
        Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard/tmux-new-instance-shortcut-plan'
    }
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

$plan = [ordered]@{
    schema = 'agentswitchboard.tmux-new-instance-shortcut-install-plan.v1'
    mode = $Mode
    repositoryLauncher = $launcherSource
    manifest = $resolvedManifestPath
    installRoot = $resolvedInstallRoot
    installedLauncher = $installedLauncherPath
    installedManifest = $installedManifestPath
    desktopDirectory = $resolvedDesktop
    shortcut = $shortcutPath
    shortcutTarget = if ($resolvedPwsh) { $resolvedPwsh } else { '<resolved during apply>' }
    shortcutArguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$installedLauncherPath`" -Mode new-instance -InstanceId auto -Operation Launch -ManifestPath `"$installedManifestPath`""
    icon = if ($resolvedWezTerm) { "$resolvedWezTerm,0" } else { '<resolved during apply>' }
    lifecycleOwner = 'tooling/profiles/windows/Invoke-AgentSwitchboardOpenOrActivate.ps1'
    overwritesForeignShortcut = $false
    launchesDuringInstall = $false
    generatedEvidenceTracked = $false
    proofCeiling = 'Installer plan and shortcut delegation only. No tmux session or WezTerm window is launched by installation.'
}
$planPath = Join-Path $OutputDirectory 'tmux-new-instance-shortcut-install-plan.json'
Write-JsonArtifact -Value $plan -Path $planPath

if ($Mode -eq 'Plan') {
    $plan | ConvertTo-Json -Depth 10
    exit 20
}

if ($env:OS -ne 'Windows_NT') {
    throw 'Shortcut apply mode is supported only on Windows.'
}

$null = New-Item -ItemType Directory -Path $resolvedInstallRoot -Force
$null = New-Item -ItemType Directory -Path $resolvedDesktop -Force
$null = New-Item -ItemType Directory -Path $stateRoot -Force

Copy-FileAtomically -Source $launcherSource -Destination $installedLauncherPath
Copy-FileAtomically -Source $resolvedManifestPath -Destination $installedManifestPath

$shell = New-Object -ComObject WScript.Shell
if (Test-Path -LiteralPath $shortcutPath -PathType Leaf) {
    $existing = $shell.CreateShortcut($shortcutPath)
    $expectedMarker = [string]$manifest.shortcutDescription
    $owned = ($existing.Description -eq $expectedMarker -and $existing.Arguments -like "*$installedLauncherPath*")
    if (-not $owned) {
        throw "Existing foreign shortcut was preserved: $shortcutPath"
    }
}

$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $resolvedPwsh
$shortcut.Arguments = [string]$plan.shortcutArguments
$shortcut.WorkingDirectory = $HOME
$shortcut.IconLocation = "$resolvedWezTerm,0"
$shortcut.Description = [string]$manifest.shortcutDescription
$shortcut.WindowStyle = 7
$shortcut.Save()

$readBack = $shell.CreateShortcut($shortcutPath)
if ($readBack.TargetPath -ne $resolvedPwsh) {
    throw 'Shortcut target readback does not match PowerShell 7.'
}
if ($readBack.Arguments -notlike "*$installedLauncherPath*" -or $readBack.Arguments -notlike '*-Mode new-instance*' -or $readBack.Arguments -notlike '*-InstanceId auto*') {
    throw 'Shortcut argument readback does not delegate to the canonical new-instance launcher.'
}

$receipt = [ordered]@{
    schema = 'agentswitchboard.tmux-new-instance-shortcut-install-receipt.v1'
    status = 'installed'
    installedAt = (Get-Date).ToUniversalTime().ToString('o')
    installRoot = $resolvedInstallRoot
    launcher = $installedLauncherPath
    manifest = $installedManifestPath
    shortcut = $shortcutPath
    target = $readBack.TargetPath
    arguments = $readBack.Arguments
    icon = $readBack.IconLocation
    description = $readBack.Description
    runtimeExecuted = $false
    generatedEvidenceTracked = $false
    proofLevel = 'installed-shortcut-readback'
    proofCeiling = 'The owned shortcut and installed launcher were written and read back. Double-click runtime behavior remains workstation evidence.'
}
$receiptPath = Join-Path $stateRoot 'tmux-new-instance-shortcut-install-receipt.json'
Write-JsonArtifact -Value $receipt -Path $receiptPath

$reportPath = Join-Path $stateRoot 'tmux-new-instance-shortcut-operator-report.md'
@(
    '# AgentSwitchboard tmux New-Instance Shortcut',
    '',
    '- Status: installed',
    ('- Shortcut: `{0}`' -f $shortcutPath),
    ('- Canonical launcher: `{0}`' -f $installedLauncherPath),
    ('- Manifest: `{0}`' -f $installedManifestPath),
    '- Runtime mode: `new-instance`',
    '- Instance policy: smallest available positive integer (`dev-1`, `dev-2`, ...)',
    '- WezTerm process policy: `start --always-new-process`',
    '- Runtime executed during install: no',
    '',
    '## Next action',
    '',
    'Double-click the desktop shortcut once. The first click allocates the first unused named tmux session and requests one separate WezTerm process.',
    '',
    '## Proof ceiling',
    '',
    $receipt.proofCeiling
) | Set-Content -LiteralPath $reportPath -Encoding utf8

$receipt | ConvertTo-Json -Depth 10
exit 0
