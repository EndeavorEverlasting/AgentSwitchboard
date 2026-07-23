[CmdletBinding()]
param(
    [string]$StageId = 'P09',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Running P09-Hermes-Optional stage...' -ForegroundColor Yellow

$setupScript = Join-Path $RepoRoot 'tooling\profiles\windows\Setup-TechnicianAgentSwitchboard.ps1'
if (-not (Test-Path -LiteralPath $setupScript -PathType Leaf)) {
    throw "Canonical technician setup/launcher script is missing: $setupScript"
}

$pwshPath = (Get-Command pwsh.exe -ErrorAction Stop).Source
$proc = Start-Process -FilePath $pwshPath -ArgumentList @(
    '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass',
    '-File', ('"{0}"' -f $setupScript),
    '-Mode', 'hermes',
    '-RepoRoot', ('"{0}"' -f $RepoRoot)
) -Wait -NoNewWindow -PassThru

$ack = [ordered]@{
    schema = 'agentswitchboard.technician-live-cert-launch-ack.v1'
    mode = 'hermes'
    exitCode = $proc.ExitCode
    commandAcknowledged = ($proc.ExitCode -eq 0)
    optional = $true
    coreCertificateImpact = 'none'
}
$ack | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $StageDir 'hermes-launch-ack.json') -Encoding utf8NoBOM

if ($proc.ExitCode -ne 0) {
    throw "Optional Hermes launch/setup failed with exit code $($proc.ExitCode). Core P00-P08 proof remains unchanged."
}

Write-Host 'P09 Hermes command was acknowledged. This optional result does not alter the core certificate.' -ForegroundColor Green
return 0
