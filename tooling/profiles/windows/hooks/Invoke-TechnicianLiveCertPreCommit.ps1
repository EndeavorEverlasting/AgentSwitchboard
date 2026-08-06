[CmdletBinding()]
param(
    [string]$RootPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw 'Unable to resolve hook directory. Supply -RootPath explicitly.'
    }
    $RootPath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
}
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$operatorValidator = Join-Path $RootPath 'scripts\Test-OperatorCommandEnvelope.ps1'
& $operatorValidator -RootPath $RootPath
if ($LASTEXITCODE -ne 0) {
    throw "Operator command envelope validation failed with exit code $LASTEXITCODE."
}

$validator = Join-Path $RootPath 'scripts\Test-TechnicianLiveCertHarness.ps1'
& $validator -RootPath $RootPath
if ($LASTEXITCODE -ne 0) {
    throw "Technician live-cert harness validation failed with exit code $LASTEXITCODE."
}

& git -C $RootPath --no-pager diff --cached --check
if ($LASTEXITCODE -ne 0) {
    throw "Staged diff hygiene failed with exit code $LASTEXITCODE."
}

$staged = @(& git -C $RootPath --no-pager diff --cached --name-only --diff-filter=ACMRTUXB)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect staged paths; git exited with $LASTEXITCODE."
}

$forbidden = @(
    $staged | Where-Object {
        $_ -match '(^|/)(runs|evidence|logs?)/' -or
        $_ -match 'technician-live-cert-harness-status\.(json|md)$' -or
        $_ -match 'operator-command-envelope-report\.(json|md)$' -or
        $_ -match 'preflight-summary\.json$' -or
        $_ -match 'stage-result\.json$'
    }
)
if ($forbidden.Count -gt 0) {
    throw "Generated technician evidence must not be committed: $($forbidden -join ', ')"
}

Write-Host 'Technician live-cert opt-in pre-commit checks passed.' -ForegroundColor Green
exit 0
