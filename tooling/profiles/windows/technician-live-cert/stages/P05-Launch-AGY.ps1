[CmdletBinding()]
param(
    [string]$StageId = 'P05',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Running P05-Launch-AGY stage...' -ForegroundColor Yellow

$setupScript = Join-Path $RepoRoot 'tooling\profiles\windows\Setup-TechnicianAgentSwitchboard.ps1'
if (-not (Test-Path -LiteralPath $setupScript -PathType Leaf)) {
    throw "Canonical technician setup/launcher script is missing: $setupScript"
}

$pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
$startedAt = (Get-Date).ToUniversalTime().ToString('o')
$proc = Start-Process -FilePath $pwshPath -ArgumentList @(
    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', ('"{0}"' -f $setupScript),
    '-Mode', 'agy',
    '-RepoRoot', ('"{0}"' -f $RepoRoot)
) -Wait -NoNewWindow -PassThru

$ack = [ordered]@{
    schema = 'agentswitchboard.technician-live-cert-launch-ack.v1'
    mode = 'agy'
    startedAt = $startedAt
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
    exitCode = $proc.ExitCode
    commandAcknowledged = ($proc.ExitCode -eq 0)
    authentication = 'unproven-unless-observed'
    providerResponse = 'unproven-unless-observed'
    proofCeiling = 'AGY launch command acknowledgement. TUI visibility, authentication, and provider response are separate runtime observations.'
}
$ack | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $StageDir 'agy-launch-ack.json') -Encoding utf8NoBOM

if ($proc.ExitCode -ne 0) {
    throw "Canonical AGY launch failed with exit code $($proc.ExitCode)."
}

Write-Host 'P05 AGY launch command was acknowledged. Manual TUI observation remains required.' -ForegroundColor Green
return 0
