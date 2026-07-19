<#
.SYNOPSIS
    Installs the canonical AgentSwitchboard WezTerm launcher.
.DESCRIPTION
    Copies the launcher script and template to the user's profile,
    creates a managed block in .wezterm.lua, and generates a desktop shortcut.
.PARAMETER Distro
    WSL distribution. Default: 'Ubuntu'.
.PARAMETER TmuxSession
    tmux session. Default: 'dev'.
.PARAMETER Workspace
    WezTerm workspace name. Default: 'agent-switchboard'.
.PARAMETER Apply
    Actually perform the installation. Without this flag, shows the plan.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$Distro = 'Ubuntu',
    [string]$TmuxSession = 'dev',
    [string]$Workspace = 'agent-switchboard',
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'
$installRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\wezterm-launcher'
$launcherScript = Join-Path $installRoot 'Invoke-AgentSwitchboardWezTermLauncher.ps1'
$templateDir = Join-Path $installRoot 'templates'
$userLuaPath = Join-Path $env:USERPROFILE '.wezterm.lua'
$launcherCmdPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'AgentSwitchboard WezTerm.lnk'
$managedStart = '-- BEGIN AGENTSWITCHBOARD WEZTERM LAUNCHER'
$managedEnd = '-- END AGENTSWITCHBOARD WEZTERM LAUNCHER'

function Get-ManagedBlock {
    $launcherEscaped = $launcherScript -replace '\\', '\\\\' -replace "'", "\'"
    @"
$managedStart
local as_launcher = dofile('$($launcherEscaped -replace '\\', '\\')')
-- AgentSwitchboard managed workspace: $Workspace
$managedEnd
"@
}

$plan = [pscustomobject]@{
    action = 'install'
    install_root = $installRoot
    launcher_script = $launcherScript
    template_dir = $templateDir
    user_lua = $userLuaPath
    shortcut = $launcherCmdPath
    workspace = $Workspace
    distro = $Distro
    tmux_session = $TmuxSession
}

Write-Host "AgentSwitchboard WezTerm Launcher Install Plan:" -ForegroundColor Cyan
$plan | Format-List

if (-not $Apply) {
    Write-Host "Run with -Apply to execute." -ForegroundColor Yellow
    return
}

if (-not $PSCmdlet.ShouldProcess($installRoot, 'Install AgentSwitchboard WezTerm launcher')) { return }

# Create install directory
New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
New-Item -ItemType Directory -Path $templateDir -Force | Out-Null

# Copy launcher script
$sourceScript = Join-Path $PSScriptRoot 'Invoke-AgentSwitchboardWezTermLauncher.ps1'
if (-not (Test-Path -LiteralPath $sourceScript)) {
    $sourceScript = Join-Path (Split-Path $PSScriptRoot) 'Invoke-AgentSwitchboardWezTermLauncher.ps1'
}
if (Test-Path -LiteralPath $sourceScript) {
    Copy-Item -LiteralPath $sourceScript -Destination $launcherScript -Force
} else {
    Write-Warning "Source launcher script not found at $sourceScript. Skipping copy."
}

# Copy template
$sourceTemplate = Join-Path $PSScriptRoot 'templates\wezterm-tmux.lua'
if (-not (Test-Path -LiteralPath $sourceTemplate)) {
    $sourceTemplate = Join-Path (Split-Path $PSScriptRoot) 'templates\wezterm-tmux.lua'
}
if (Test-Path -LiteralPath $sourceTemplate) {
    Copy-Item -LiteralPath $sourceTemplate -Destination (Join-Path $templateDir 'wezterm-tmux.lua') -Force
}

# Update .wezterm.lua managed block
$existing = if (Test-Path -LiteralPath $userLuaPath) { Get-Content -Raw -LiteralPath $userLuaPath } else { '' }
$block = Get-ManagedBlock
if ($existing.Contains($managedStart) -and $existing.Contains($managedEnd)) {
    $pattern = '(?s)' + [regex]::Escape($managedStart) + '.*?' + [regex]::Escape($managedEnd)
    $existing = [regex]::Replace($existing, $pattern, $block)
} elseif ($existing.Contains('return config')) {
    $existing = $existing.Replace('return config', "$block`n`nreturn config")
} else {
    $existing = "local wezterm = require 'wezterm'`nlocal config = wezterm.config_builder()`n`n$block`n`nreturn config`n"
}
[System.IO.File]::WriteAllText($userLuaPath, $existing, [System.Text.UTF8Encoding]::new($false))

# Create desktop shortcut
$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if (-not $pwsh) { $pwsh = Get-Command powershell.exe -ErrorAction Stop }
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($launcherCmdPath)
$shortcut.TargetPath = $pwsh.Source
$shortcut.Arguments = "-NoProfile -WindowStyle Hidden -File `"$launcherScript`" -Workspace $Workspace -Distro $Distro -TmuxSession $TmuxSession"
$shortcut.WorkingDirectory = $installRoot
$shortcut.Description = 'AgentSwitchboard WezTerm open-or-activate launcher'
$shortcut.Save()

Write-Host "Installation complete." -ForegroundColor Green
Write-Host "  Launcher: $launcherScript"
Write-Host "  Shortcut: $launcherCmdPath"
Write-Host "  .wezterm.lua: updated with managed block"
