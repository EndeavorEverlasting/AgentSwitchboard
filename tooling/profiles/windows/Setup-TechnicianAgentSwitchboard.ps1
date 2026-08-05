[CmdletBinding()]
param(
    [ValidateSet('shell', 'agy', 'opencode', 'setup', 'hermes')]
    [string]$Mode = 'shell',

    [Parameter(Mandatory)]
    [string]$RepoRoot,

    [string]$GitRef = 'main',

    [string]$Distribution = 'Ubuntu',

    [ValidateRange(30, 1800)]
    [int]$HermesTimeoutSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path
$enginePath = Join-Path $RepoRoot 'tooling\profiles\windows\Invoke-TechnicianAgentSwitchboardReady.ps1'
if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw "Canonical technician readiness engine is missing: $enginePath"
}

& $enginePath `
    -Mode $Mode `
    -RepoRoot $RepoRoot `
    -GitRef $GitRef `
    -Distribution $Distribution `
    -TimeoutSeconds $HermesTimeoutSeconds

exit $LASTEXITCODE
