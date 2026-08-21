[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$RepoPath,
    [string]$ModelId = 'opencode/nemotron-3-ultra-free'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

if ($env:OS -ne 'Windows_NT') {
    throw 'OpenCode runtime recovery is Windows-only.'
}
if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'OpenCode runtime recovery requires PowerShell 7.'
}

$RepoPath = (Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).Path
$repairCmd = Join-Path $RepoPath 'Repair-Technician-Command-Shims.cmd'
$runnerPath = Join-Path $RepoPath 'tooling\harness\operational\opencode-lsp-setup\Invoke-OpenCodeLspWorkstationSetup.ps1'
$canonicalShim = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\bin\opencode.cmd'

foreach ($requiredPath in @($repairCmd, $runnerPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required runtime-recovery entrypoint is missing: $requiredPath"
    }
}

$priorNoPause = $env:AGENT_SWITCHBOARD_NO_PAUSE
try {
    $env:AGENT_SWITCHBOARD_NO_PAUSE = '1'
    & $repairCmd
    $repairCode = $LASTEXITCODE
}
finally {
    $env:AGENT_SWITCHBOARD_NO_PAUSE = $priorNoPause
}

if ($repairCode -ne 0) {
    throw "Canonical command-shim repair failed with exit code $repairCode."
}
if (-not (Test-Path -LiteralPath $canonicalShim -PathType Leaf)) {
    throw "Command-shim repair returned success but the canonical OpenCode shim is missing: $canonicalShim"
}

Write-Host "OPENCODE_RUNTIME_RECOVERY_SHIM=$canonicalShim"
Write-Host 'OpenCode command-shim repair passed; re-entering the owning LSP Inspect gate.'

& pwsh -NoLogo -NoProfile -File $runnerPath -Mode Inspect -RepoPath $RepoPath -ModelId $ModelId
exit $LASTEXITCODE
