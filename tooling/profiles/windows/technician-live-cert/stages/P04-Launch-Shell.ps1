[CmdletBinding()]
param(
    [string]$StageId = 'P04',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Running P04-Launch-Shell stage...' -ForegroundColor Yellow

$setupScript = Join-Path $RepoRoot 'tooling\profiles\windows\Setup-TechnicianAgentSwitchboard.ps1'
if (-not (Test-Path -LiteralPath $setupScript -PathType Leaf)) {
    throw "Canonical technician setup/launcher script is missing: $setupScript"
}

$pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
$startedAt = (Get-Date).ToUniversalTime().ToString('o')
$proc = Start-Process -FilePath $pwshPath -ArgumentList @(
    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', ('"{0}"' -f $setupScript),
    '-Mode', 'shell',
    '-RepoRoot', ('"{0}"' -f $RepoRoot)
) -Wait -NoNewWindow -PassThru

$ack = [ordered]@{
    schema = 'agentswitchboard.technician-live-cert-launch-ack.v1'
    mode = 'shell'
    startedAt = $startedAt
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
    exitCode = $proc.ExitCode
    commandAcknowledged = ($proc.ExitCode -eq 0)
    proofCeiling = 'Launcher command acknowledgement only. Visible WezTerm behavior and tmux attachment require the separate manual observation gate.'
}
$ack | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $StageDir 'shell-launch-ack.json') -Encoding utf8NoBOM

if ($proc.ExitCode -ne 0) {
    throw "Canonical shell launch failed with exit code $($proc.ExitCode)."
}

Write-Host 'P04 shell launch command was acknowledged. Manual visible-window proof is still required.' -ForegroundColor Green
return 0
