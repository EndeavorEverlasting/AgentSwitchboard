[CmdletBinding()]
param(
    [ValidateSet('Plan', 'Apply')]
    [string]$Mode = 'Apply',

    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (Get-Item $scriptDir).Parent.Parent.Parent.FullName
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path

$desktopPath = [Environment]::GetFolderPath('Desktop')
if ([string]::IsNullOrWhiteSpace($desktopPath)) {
    throw 'The current Windows profile does not expose a Desktop folder.'
}

$definitions = @(
    [pscustomobject]@{
        Name = 'Run Technician Live Cert.lnk'
        Target = Join-Path $RepoRoot 'Run-Technician-LiveCert.cmd'
        Description = 'AgentSwitchboard technician clickable live-certification runner'
    },
    [pscustomobject]@{
        Name = 'AgentSwitchboard.lnk'
        Target = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\bin\AgentSwitchboard.cmd'
        Description = 'AgentSwitchboard local readiness and bounded agent launcher'
    },
    [pscustomobject]@{
        Name = 'AgentSwitchboard Technician Ready.lnk'
        Target = Join-Path $RepoRoot 'Technician-AgentSwitchboard-Ready.cmd'
        Description = 'Install, repair, validate, and open the technician AgentSwitchboard surface'
    }
)

Write-Host 'Technician AgentSwitchboard Shortcuts Installer' -ForegroundColor Cyan
Write-Host "Mode:       $Mode"
Write-Host "Repository: $RepoRoot"

foreach ($definition in $definitions) {
    if (-not (Test-Path -LiteralPath $definition.Target -PathType Leaf)) {
        throw "Shortcut target does not exist: $($definition.Target)"
    }
    $definition | Add-Member -NotePropertyName ShortcutPath -NotePropertyValue (Join-Path $desktopPath $definition.Name)
}

if ($Mode -eq 'Plan') {
    foreach ($definition in $definitions) {
        Write-Host "[PLAN] $($definition.ShortcutPath) -> $($definition.Target)" -ForegroundColor Yellow
    }
    exit 20
}

$wshShell = New-Object -ComObject WScript.Shell
foreach ($definition in $definitions) {
    $shortcut = $wshShell.CreateShortcut($definition.ShortcutPath)
    $shortcut.TargetPath = $definition.Target
    $shortcut.WorkingDirectory = $RepoRoot
    $shortcut.Description = $definition.Description
    $shortcut.Save()

    if (-not (Test-Path -LiteralPath $definition.ShortcutPath -PathType Leaf)) {
        throw "Shortcut was not created: $($definition.ShortcutPath)"
    }
    Write-Host "Created: $($definition.ShortcutPath)" -ForegroundColor Green
}

exit 0
