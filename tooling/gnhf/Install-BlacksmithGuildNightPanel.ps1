[CmdletBinding()]
param(
    [string]$RepoPath = "$env:USERPROFILE\Desktop\dev\Mods\Bannerlord\BlacksmithGuild",
    [string]$WezTermConfigPath = "$env:USERPROFILE\.wezterm.lua",
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
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

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'The BlacksmithGuild night-panel installer requires PowerShell 7 (pwsh).'
}

$RepoPath = [IO.Path]::GetFullPath($RepoPath)
$WezTermConfigPath = [IO.Path]::GetFullPath($WezTermConfigPath)
$InstallRoot = [IO.Path]::GetFullPath($InstallRoot)

$sourceControlLauncher = Join-Path $PSScriptRoot 'Start-AgentSwitchboard.ps1'
$sourceNightLauncher = Join-Path $PSScriptRoot 'Start-BlacksmithGuildNightShift.ps1'
$sourceInclude = Join-Path $PSScriptRoot 'templates\wezterm-blacksmithguild-night.lua'
$destinationControlLauncher = Join-Path $InstallRoot 'Start-AgentSwitchboard.ps1'
$destinationNightLauncher = Join-Path $InstallRoot 'Start-BlacksmithGuildNightShift.ps1'
$destinationInclude = Join-Path (Split-Path -Parent $WezTermConfigPath) $includeFileName

foreach ($source in @($sourceControlLauncher, $sourceNightLauncher, $sourceInclude)) {
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required source file is missing: $source"
    }
}

$plan = [ordered]@{
    schema = 'agentswitchboard.blacksmithguild-night-panel.install-plan.v1'
    apply = [bool]$Apply
    repoPath = $RepoPath
    wezTermConfigPath = $WezTermConfigPath
    installedControlLauncher = $destinationControlLauncher
    installedNightLauncher = $destinationNightLauncher
    installedInclude = $destinationInclude
    configExists = Test-Path -LiteralPath $WezTermConfigPath -PathType Leaf
    managedBlockPresent = $false
    backupPath = $null
    action = 'plan_only'
}

$configText = ''
if ($plan.configExists) {
    $configText = Get-Content -LiteralPath $WezTermConfigPath -Raw
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
Copy-Item -LiteralPath $sourceControlLauncher -Destination $destinationControlLauncher -Force
Copy-Item -LiteralPath $sourceNightLauncher -Destination $destinationNightLauncher -Force
Copy-Item -LiteralPath $sourceInclude -Destination $destinationInclude -Force

if (-not $plan.configExists) {
    $configText = @"
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

$(Get-ManagedBlock)

return config
"@
    Set-Content -LiteralPath $WezTermConfigPath -Value $configText -Encoding utf8NoBOM
    $plan.action = 'created_config_and_installed_panel'
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

    $managedBlock = (Get-ManagedBlock).TrimEnd()
    $match = $matches[0]
    $newConfig = $configText.Substring(0, $match.Index).TrimEnd() + "`r`n`r`n" + $managedBlock + "`r`n`r`n" + $configText.Substring($match.Index)
    Set-Content -LiteralPath $WezTermConfigPath -Value $newConfig -Encoding utf8NoBOM
    $plan.action = 'installed_panel_and_patched_config'
}
else {
    $plan.action = 'refreshed_installed_files_existing_config_wiring_preserved'
}

$verificationText = Get-Content -LiteralPath $WezTermConfigPath -Raw
if (-not $verificationText.Contains($beginMarker) -or -not $verificationText.Contains($endMarker)) {
    throw 'The managed WezTerm panel block was not observed after installation.'
}
foreach ($installed in @($destinationControlLauncher, $destinationNightLauncher, $destinationInclude)) {
    if (-not (Test-Path -LiteralPath $installed -PathType Leaf)) {
        throw "Installed panel file is missing: $installed"
    }
}

$installedControlText = Get-Content -LiteralPath $destinationControlLauncher -Raw
if ($installedControlText -notmatch 'ValidateSet\("opencode",\s*"deepseek"') {
    throw 'The installed AgentSwitchboard launcher does not contain the explicit DeepSeek route. Refresh AgentSwitchboard main and rerun this installer.'
}

$evidenceRoot = Join-Path $InstallRoot 'panel-install'
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$plan.completedUtc = [DateTime]::UtcNow.ToString('o')
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidenceRoot 'blacksmithguild-night-panel.install.json') -Encoding utf8NoBOM

Write-Host "`nInstalled. In WezTerm, open the launch menu and select:" -ForegroundColor Green
Write-Host '  BlacksmithGuild — GNHF Night Shift' -ForegroundColor Green
Write-Host 'The Auto stage starts at queue compilation when no night queue exists, repair when ready items exist, and closeout when none remain.' -ForegroundColor Cyan
if ($plan.backupPath) {
    Write-Host "WezTerm config backup: $($plan.backupPath)" -ForegroundColor Cyan
}
