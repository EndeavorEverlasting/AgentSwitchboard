[CmdletBinding()]
param(
    [string]$RootPath,
    [string]$OutputRoot,
    [string]$CandidatePath,
    [ValidateSet('interactive-copy-paste', 'script-file')]
    [string]$CandidateDeliveryMode = 'interactive-copy-paste'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw 'Unable to resolve repository root. Supply -RootPath.'
    }
    $RootPath = Split-Path -Parent $PSScriptRoot
}
$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
    $OutputRoot = Join-Path $base 'AgentSwitchboard\skill-factoring'
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command python3 -ErrorAction SilentlyContinue
}
if (-not $python) {
    throw 'Python 3 was not found on PATH.'
}

$validator = Join-Path $RootPath 'tooling\skills\skill_factoring_contracts.py'
if (-not (Test-Path -LiteralPath $validator -PathType Leaf)) {
    throw "Skill factoring validator is missing: $validator"
}

$arguments = @(
    $validator,
    '--root', $RootPath,
    '--output-root', $OutputRoot,
    '--candidate-delivery-mode', $CandidateDeliveryMode
)
if (-not [string]::IsNullOrWhiteSpace($CandidatePath)) {
    $arguments += @('--candidate-path', $CandidatePath)
}

& $python.Source @arguments
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    throw "Skill factoring validation failed with exit code $exitCode."
}

$report = Join-Path $OutputRoot 'skill-factoring-report.md'
if (-not (Test-Path -LiteralPath $report -PathType Leaf)) {
    throw "Skill factoring validation passed without producing its Markdown report: $report"
}
Get-Content -LiteralPath $report
