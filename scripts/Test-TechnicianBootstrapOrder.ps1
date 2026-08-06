[CmdletBinding()]
param(
    [string]$RootPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw 'Unable to resolve validator directory. Supply -RootPath explicitly.'
    }
    $RootPath = Split-Path -Parent $PSScriptRoot
}
$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path

$contractPath = Join-Path $RootPath 'tooling\profiles\windows\harness\technician-ready\bootstrap-order.contract.json'
$enginePath = Join-Path $RootPath 'tooling\profiles\windows\Invoke-TechnicianAgentSwitchboardReady.ps1'
$pythonTestPath = Join-Path $RootPath 'tests\test_technician_bootstrap_order.py'
$docPath = Join-Path $RootPath 'docs\harness\technician-bootstrap-order.md'
$cmdPath = Join-Path $RootPath 'Test-TechnicianBootstrapOrder.cmd'
$failures = [Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory)][string]$Message)
    [void]$failures.Add($Message)
    Write-Host "FAIL: $Message" -ForegroundColor Red
}

foreach ($path in @($contractPath, $enginePath, $pythonTestPath, $docPath, $cmdPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Required file is missing: $path"
    }
}

if ($failures.Count -eq 0) {
    try {
        $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    }
    catch {
        Add-Failure "Bootstrap-order contract is not valid JSON: $($_.Exception.Message)"
    }
}

if ($failures.Count -eq 0) {
    if ([int]$contract.schemaVersion -ne 1) {
        Add-Failure 'Bootstrap-order contract must use schemaVersion 1.'
    }
    if ([string]$contract.contractId -ne 'agentswitchboard.technician-bootstrap-order.v1') {
        Add-Failure 'Bootstrap-order contract ID is incorrect.'
    }
    if ([bool]$contract.generatedEvidence.tracked) {
        Add-Failure 'Generated bootstrap-order evidence must remain untracked.'
    }

    $engine = Get-Content -LiteralPath $enginePath -Raw
    $positions = @{}
    $seenTokens = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $previousId = $null
    $previousPosition = -1

    foreach ($gate in @($contract.orderedGates)) {
        $id = [string]$gate.id
        $token = [string]$gate.token
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($token)) {
            Add-Failure 'Each ordered gate requires a non-empty id and token.'
            continue
        }
        if (-not $seenTokens.Add($token)) {
            Add-Failure "Duplicate ordered-gate token: $token"
            continue
        }

        $position = $engine.IndexOf($token, [StringComparison]::Ordinal)
        if ($position -lt 0) {
            Add-Failure "Readiness engine is missing gate '$id': $token"
            continue
        }
        if ($engine.IndexOf($token, $position + $token.Length, [StringComparison]::Ordinal) -ge 0) {
            Add-Failure "Readiness engine contains gate token more than once: $id"
        }
        if ($previousPosition -ge 0 -and $position -le $previousPosition) {
            Add-Failure "Bootstrap order regressed: '$previousId' must precede '$id'."
        }
        $positions[$id] = $position
        $previousId = $id
        $previousPosition = $position
    }

    foreach ($relation in @($contract.requiredRelations)) {
        $before = [string]$relation.before
        $after = [string]$relation.after
        if (-not $positions.ContainsKey($before) -or -not $positions.ContainsKey($after)) {
            Add-Failure "Required relation references an unknown gate: $before -> $after"
            continue
        }
        if ([int]$positions[$before] -ge [int]$positions[$after]) {
            Add-Failure "Required relation violated: $before -> $after"
        }
    }

    $tokens = $null
    $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        $enginePath,
        [ref]$tokens,
        [ref]$parseErrors
    )
    foreach ($parseError in $parseErrors) {
        Add-Failure "PowerShell parse error at line $($parseError.Extent.StartLineNumber): $($parseError.Message)"
    }
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host "Technician bootstrap-order validation failed with $($failures.Count) issue(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'PASS: WezTerm, WSL/Ubuntu, and tmux are deterministically gated before agent CLIs, GNHF setup, and launcher execution.' -ForegroundColor Green
exit 0
