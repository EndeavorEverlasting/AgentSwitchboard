[CmdletBinding()]
param(
    [string]$RepairId = 'Command-Shims',
    [string]$RunId,
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Repairing AgentSwitchboard command shims through the canonical technician setup...' -ForegroundColor Yellow

$setupScript = Join-Path $RepoRoot 'tooling\profiles\windows\Setup-TechnicianAgentSwitchboard.ps1'
if (-not (Test-Path -LiteralPath $setupScript -PathType Leaf)) {
    throw "Canonical technician setup script is missing: $setupScript"
}

$pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
$proc = Start-Process -FilePath $pwshPath -ArgumentList @(
    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', ('"{0}"' -f $setupScript),
    '-Mode', 'setup',
    '-RepoRoot', ('"{0}"' -f $RepoRoot)
) -Wait -NoNewWindow -PassThru

if ($proc.ExitCode -ne 0) {
    throw "Canonical setup could not rebuild/verify the command shims. Exit code: $($proc.ExitCode)"
}

$shimDir = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\bin'
$missing = @()
foreach ($commandName in @('wezterm', 'tmux', 'agy', 'opencode')) {
    $shim = Join-Path $shimDir "$commandName.cmd"
    if (-not (Test-Path -LiteralPath $shim -PathType Leaf)) {
        $missing += $commandName
    }
}
if ($missing.Count -gt 0) {
    throw "Canonical setup completed but required shims are still missing: $($missing -join ', ')."
}

Write-Host 'Command-shim repair completed using canonical setup. Rerun P03 to prove all four version probes.' -ForegroundColor Green
return 0
