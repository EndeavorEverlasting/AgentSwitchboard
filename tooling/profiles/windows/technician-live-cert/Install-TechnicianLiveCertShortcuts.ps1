[CmdletBinding()]
param(
    [ValidateSet('Plan', 'Apply')]
    [string]$Mode = 'Apply',
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $RepoRoot) {
    $RepoRoot = (Get-Item $scriptDir).Parent.Parent.Parent.FullName
}

$desktopPath = [Environment]::GetFolderPath('Desktop')
$targetCmd = Join-Path $RepoRoot 'Run-Technician-LiveCert.cmd'

Write-Host "Technician Live-Cert Shortcuts Installer" -ForegroundColor Cyan
Write-Host "Mode: $Mode" -ForegroundColor White
Write-Host "Target CMD: $targetCmd" -ForegroundColor Gray

if (-not (Test-Path -LiteralPath $targetCmd)) {
    throw "Target root CMD does not exist: $targetCmd"
}

$shortcutPath = Join-Path $desktopPath "Run Technician Live Cert.lnk"

if ($Mode -eq 'Plan') {
    Write-Host "[PLAN] Would create shortcut at: $shortcutPath" -ForegroundColor Yellow
    exit 20
}

$wshShell = New-Object -ComObject WScript.Shell
$shortcut = $wshShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $targetCmd
$shortcut.WorkingDirectory = $RepoRoot
$shortcut.Description = "Technician Clickable Live Certification Runner"
$shortcut.Save()

Write-Host "Successfully created shortcut: $shortcutPath" -ForegroundColor Green
exit 0
