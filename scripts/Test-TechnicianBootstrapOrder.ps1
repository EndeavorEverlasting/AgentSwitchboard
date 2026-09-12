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
$bootstrapPath = Join-Path $RootPath 'tooling\profiles\windows\Invoke-TechnicianBootstrapPrerequisites.ps1'
$enginePath = Join-Path $RootPath 'tooling\profiles\windows\Invoke-TechnicianAgentSwitchboardReady.ps1'
$frontDoorPath = Join-Path $RootPath 'Technician-AgentSwitchboard-Ready.cmd'
$pythonTestPath = Join-Path $RootPath 'tests\test_technician_bootstrap_order.py'
$docPath = Join-Path $RootPath 'docs\harness\technician-bootstrap-order.md'
$cmdPath = Join-Path $RootPath 'Test-TechnicianBootstrapOrder.cmd'
$failures = [Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory)][string]$Message)
    [void]$failures.Add($Message)
    Write-Host "FAIL: $Message" -ForegroundColor Red
}

function Test-OrderedTokens {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][object[]]$Gates,
        [Parameter(Mandatory)][string]$Label
    )

    $seenIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $seenTokens = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $previousId = $null
    $previousPosition = -1

    foreach ($gate in $Gates) {
        $id = [string]$gate.id
        $token = [string]$gate.token
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($token)) {
            Add-Failure "$Label gates require non-empty ids and tokens."
            continue
        }
        if (-not $seenIds.Add($id)) {
            Add-Failure "Duplicate $Label gate id: $id"
            continue
        }
        if (-not $seenTokens.Add($token)) {
            Add-Failure "Duplicate $Label gate token: $token"
            continue
        }

        $position = $Text.IndexOf($token, [StringComparison]::Ordinal)
        if ($position -lt 0) {
            Add-Failure "$Label source is missing gate '$id': $token"
            continue
        }
        if ($Text.IndexOf($token, $position + $token.Length, [StringComparison]::Ordinal) -ge 0) {
            Add-Failure "$Label source contains gate token more than once: $id"
        }
        if ($previousPosition -ge 0 -and $position -le $previousPosition) {
            Add-Failure "$Label order regressed: '$previousId' must precede '$id'."
        }
        $previousId = $id
        $previousPosition = $position
    }
}

foreach ($path in @($contractPath, $bootstrapPath, $enginePath, $frontDoorPath, $pythonTestPath, $docPath, $cmdPath)) {
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
    if ([int]$contract.schemaVersion -ne 2) {
        Add-Failure 'Bootstrap-order contract must use schemaVersion 2.'
    }
    if ([string]$contract.contractId -ne 'agentswitchboard.technician-bootstrap-order.v2') {
        Add-Failure 'Bootstrap-order contract ID is incorrect.'
    }
    if ([bool]$contract.generatedEvidence.tracked) {
        Add-Failure 'Generated bootstrap-order evidence must remain untracked.'
    }

    $bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw
    $engine = Get-Content -LiteralPath $enginePath -Raw
    $frontDoor = Get-Content -LiteralPath $frontDoorPath -Raw

    Test-OrderedTokens -Text $bootstrap -Gates @($contract.bootstrapGates) -Label 'bootstrap'
    Test-OrderedTokens -Text $frontDoor -Gates @($contract.frontDoorGates) -Label 'front-door'

    foreach ($token in @($contract.higherRuntimeTokens)) {
        $runtimeToken = [string]$token
        if (-not $engine.Contains($runtimeToken)) {
            Add-Failure "Runtime owner is missing token: $runtimeToken"
        }
        if ($bootstrap.Contains($runtimeToken)) {
            Add-Failure "Prerequisite gate illegally owns higher runtime token: $runtimeToken"
        }
    }

    foreach ($forbidden in @('git reset', 'git clean', 'git stash', 'push --force')) {
        if ($bootstrap.ToLowerInvariant().Contains($forbidden)) {
            Add-Failure "Prerequisite gate contains forbidden destructive token: $forbidden"
        }
    }

    foreach ($path in @($bootstrapPath, $enginePath)) {
        $tokens = $null
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
        foreach ($parseError in $parseErrors) {
            Add-Failure "PowerShell parse error in $path at line $($parseError.Extent.StartLineNumber): $($parseError.Message)"
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host "Technician bootstrap-order validation failed with $($failures.Count) issue(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'PASS: The front door proves WezTerm and tmux prerequisites before the higher AgentSwitchboard runtime engine can execute.' -ForegroundColor Green
exit 0
