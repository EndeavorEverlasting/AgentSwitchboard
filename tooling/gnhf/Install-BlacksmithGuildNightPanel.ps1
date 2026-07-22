[CmdletBinding()]
param(
    [string]$RepoPath = "$env:USERPROFILE\Desktop\dev\Mods\Bannerlord\BlacksmithGuild",
    [string]$WezTermConfigPath = "$env:USERPROFILE\.wezterm.lua",
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [string]$ProviderInstallerPath = (Join-Path $PSScriptRoot 'Install-ProviderRoutedGnhf.ps1'),
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$beginMarker = '-- BEGIN AgentSwitchboard BlacksmithGuild GNHF Night Panel'
$endMarker = '-- END AgentSwitchboard BlacksmithGuild GNHF Night Panel'
$includeFileName = '.wezterm-blacksmithguild-night.lua'

function Get-ManagedBlock {
    @"
$beginMarker
local tbg_night_panel = dofile(wezterm.config_dir .. '/$includeFileName')
tbg_night_panel.apply(config)
$endMarker
"@
}

function Read-TextFilePreservingEncoding {
    param([Parameter(Mandatory = $true)][string]$Path)

    $bytes = [IO.File]::ReadAllBytes($Path)
    $encoding = [Text.UTF8Encoding]::new($false)
    $preamble = [byte[]]@()
    $offset = 0

    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $encoding = [Text.UTF8Encoding]::new($true)
        $preamble = [byte[]]@(0xEF, 0xBB, 0xBF)
        $offset = 3
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $encoding = [Text.UnicodeEncoding]::new($false, $true)
        $preamble = [byte[]]@(0xFF, 0xFE)
        $offset = 2
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $encoding = [Text.UnicodeEncoding]::new($true, $true)
        $preamble = [byte[]]@(0xFE, 0xFF)
        $offset = 2
    }

    $text = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    return [pscustomobject]@{
        Text = $text
        Encoding = $encoding
        Preamble = $preamble
        Newline = $newline
    }
}

function Write-TextFilePreservingEncoding {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][Text.Encoding]$Encoding,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Preamble
    )

    $body = $Encoding.GetBytes($Text)
    $output = [byte[]]::new($Preamble.Length + $body.Length)
    if ($Preamble.Length -gt 0) {
        [Array]::Copy($Preamble, 0, $output, 0, $Preamble.Length)
    }
    [Array]::Copy($body, 0, $output, $Preamble.Length, $body.Length)
    [IO.File]::WriteAllBytes($Path, $output)
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'The BlacksmithGuild night-panel installer requires PowerShell 7 (pwsh).'
}

$RepoPath = [IO.Path]::GetFullPath($RepoPath)
$WezTermConfigPath = [IO.Path]::GetFullPath($WezTermConfigPath)
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)
$ProviderInstallerPath = [IO.Path]::GetFullPath($ProviderInstallerPath)

$sourceControlLauncher = Join-Path $PSScriptRoot 'Start-AgentSwitchboard.ps1'
$sourceNightLauncher = Join-Path $PSScriptRoot 'Start-BlacksmithGuildNightShift.ps1'
$sourceProviderInstaller = $ProviderInstallerPath
$sourceInclude = Join-Path $PSScriptRoot 'templates\wezterm-blacksmithguild-night.lua'
$destinationControlLauncher = Join-Path $InstallRoot 'Start-AgentSwitchboard.ps1'
$destinationNightLauncher = Join-Path $InstallRoot 'Start-BlacksmithGuildNightShift.ps1'
$destinationProviderLauncher = Join-Path $InstallRoot 'Start-ProviderRoutedGnhfSprint.ps1'
$destinationProviderProcess = Join-Path $InstallRoot 'Gnhf.Process.ps1'
$destinationInclude = Join-Path (Split-Path -Parent $WezTermConfigPath) $includeFileName

foreach ($source in @($sourceControlLauncher, $sourceNightLauncher, $sourceProviderInstaller, $sourceInclude)) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required source file is missing: $source"
    }
}

$plan = [ordered]@{
    schema = 'agentswitchboard.blacksmithguild-night-panel.install-plan.v2'
    apply = [bool]$Apply
    repoPath = $RepoPath
    wezTermConfigPath = $WezTermConfigPath
    providerInstallerPath = $sourceProviderInstaller
    installedControlLauncher = $destinationControlLauncher
    installedNightLauncher = $destinationNightLauncher
    installedProviderLauncher = $destinationProviderLauncher
    installedProviderProcess = $destinationProviderProcess
    installedInclude = $destinationInclude
    requiredCapabilitySchema = 'agentswitchboard.gnhf-runtime-capability.v1'
    configExists = Test-Path -LiteralPath $WezTermConfigPath -PathType Leaf
    managedBlockPresent = $false
    backupPath = $null
    action = 'plan_only'
}

$configFile = $null
$configText = ''
if ($plan.configExists) {
    $configFile = Read-TextFilePreservingEncoding -Path $WezTermConfigPath
    $configText = $configFile.Text
    $hasBegin = $configText.Contains($beginMarker)
    $hasEnd = $configText.Contains($endMarker)
    if ($hasBegin -xor $hasEnd) {
        throw 'The WezTerm configuration contains only one managed marker. Preserve the file and repair the incomplete block manually before rerunning.'
    }
    $plan.managedBlockPresent = $hasBegin -and $hasEnd
}

Write-Host "`n=== BLACKSMITHGUILD NIGHT PANEL INSTALL PLAN ===" -ForegroundColor Cyan
Write-Host "Repository:       $RepoPath"
Write-Host "WezTerm config:   $WezTermConfigPath"
Write-Host "Control launcher: $destinationControlLauncher"
Write-Host "Night launcher:   $destinationNightLauncher"
Write-Host "Provider route:   $destinationProviderLauncher"
Write-Host "Provider route:   capability-driven (OpenCode model authority)"
Write-Host "Lua include:      $destinationInclude"
Write-Host "Config exists:    $($plan.configExists)"
Write-Host "Already wired:    $($plan.managedBlockPresent)"
Write-Host "Apply:            $([bool]$Apply)"

if (-not $Apply) {
    Write-Host "`nManaged block that will be inserted before the final 'return config':" -ForegroundColor Yellow
    Write-Host (Get-ManagedBlock)
    Write-Host "`nNo files were changed. Rerun with -Apply to install." -ForegroundColor Cyan
    return
}

New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Split-Path -Parent $WezTermConfigPath) -Force | Out-Null

# Install or repair the shared provider route first. The dependency is the
# installed capability contract (not a guessed npm version or fictional GNHF
# --model flag). Tests may inject a deterministic fixture installer.
try {
    & $sourceProviderInstaller -Apply -InstallRoot $InstallRoot
}
catch {
    throw "Provider-routed GNHF installation failed: $($_.Exception.Message)"
}

Copy-Item -LiteralPath $sourceControlLauncher -Destination $destinationControlLauncher -Force
Copy-Item -LiteralPath $sourceNightLauncher -Destination $destinationNightLauncher -Force
Copy-Item -LiteralPath $sourceInclude -Destination $destinationInclude -Force

if (-not $plan.configExists) {
    $newline = "`r`n"
    $configText = @(
        "local wezterm = require 'wezterm'",
        'local config = wezterm.config_builder()',
        '',
        ((Get-ManagedBlock) -replace "`r?`n", $newline).TrimEnd(),
        '',
        'return config',
        ''
    ) -join $newline
    Write-TextFilePreservingEncoding -Path $WezTermConfigPath -Text $configText -Encoding ([Text.UTF8Encoding]::new($false)) -Preamble ([byte[]]@())
    $plan.action = 'created_config_and_installed_strict_panel'
}
elseif (-not $plan.managedBlockPresent) {
    $matches = [regex]::Matches($configText, '(?m)^\s*return\s+config\s*$')
    if ($matches.Count -ne 1) {
        throw "Expected exactly one standalone 'return config' line in $WezTermConfigPath, found $($matches.Count). Installed launcher files were preserved, but the config was not modified."
    }

    $backupRoot = Join-Path $InstallRoot 'panel-install\backups'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    $backupPath = Join-Path $backupRoot ('.wezterm.lua.{0}.bak' -f (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    Copy-Item -LiteralPath $WezTermConfigPath -Destination $backupPath
    $plan.backupPath = $backupPath

    $newline = $configFile.Newline
    $managedBlock = ((Get-ManagedBlock) -replace "`r?`n", $newline).TrimEnd()
    $match = $matches[0]
    $newConfig = $configText.Substring(0, $match.Index).TrimEnd() + $newline + $newline + $managedBlock + $newline + $newline + $configText.Substring($match.Index)
    Write-TextFilePreservingEncoding -Path $WezTermConfigPath -Text $newConfig -Encoding $configFile.Encoding -Preamble $configFile.Preamble
    $plan.action = 'installed_strict_panel_and_patched_config'
}
else {
    $plan.action = 'refreshed_strict_runtime_and_preserved_existing_config_wiring'
}

$verificationText = (Read-TextFilePreservingEncoding -Path $WezTermConfigPath).Text
if (-not $verificationText.Contains($beginMarker) -or -not $verificationText.Contains($endMarker)) {
    throw 'The managed WezTerm panel block was not observed after installation.'
}
foreach ($installed in @(
    $destinationControlLauncher,
    $destinationNightLauncher,
    $destinationProviderLauncher,
    $destinationProviderProcess,
    $destinationInclude
)) {
    if (-not (Test-Path -LiteralPath $installed -PathType Leaf)) {
        throw "Installed panel file is missing: $installed"
    }
}

$installedProviderText = Get-Content -LiteralPath $destinationProviderLauncher -Raw
foreach ($required in @(
    'Process exit zero is not delivery proof',
    'DeepSeek provider probe failed; GNHF was not started',
    'OPENCODE_CONFIG_CONTENT',
    'gnhf-runtime-capability.json'
)) {
    if (-not $installedProviderText.Contains($required)) {
        throw "Installed provider launcher is missing strict delivery contract text: $required"
    }
}

$evidenceRoot = Join-Path $InstallRoot 'panel-install'
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$plan.completedUtc = [DateTime]::UtcNow.ToString('o')
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidenceRoot 'blacksmithguild-night-panel.install.json') -Encoding utf8NoBOM

Write-Host "`nInstalled. In WezTerm, open the launch menu and select:" -ForegroundColor Green
Write-Host '  BlacksmithGuild — GNHF Night Shift' -ForegroundColor Green
Write-Host 'DeepSeek now uses the strict provider route: shell-correct OpenCode dispatch, capability-driven GNHF selection, OpenCode model authority, provider preflight, and committed-delivery proof.' -ForegroundColor Cyan
if ($plan.backupPath) {
    Write-Host "WezTerm config backup: $($plan.backupPath)" -ForegroundColor Cyan
}
