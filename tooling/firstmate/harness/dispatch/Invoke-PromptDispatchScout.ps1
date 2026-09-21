#!/usr/bin/env pwsh
<#
.SYNOPSIS
PowerShell wrapper for the FirstMate prompt-dispatch scout.

.DESCRIPTION
Remote-safe scout that demonstrates routing-decision → prompt-dispatch translation
without claiming live crew delivery or dual-path vision complete.

Default mode is dry-run / contract scout:
  - Loads a prompt-kit.routing-decision/v1 fixture
  - Calls build_prompt_dispatch(...) from RRB-03
  - Writes asb.prompt-dispatch/v1 artifact to local untracked evidence
  - Does NOT invoke fm-send, tmux, or FirstMate lifecycle

Optional live-delivery mode fails-closed on Linux with BLOCKED_LINUX_WSL_REQUIRED.

.PARAMETER DecisionPath
Path to prompt-kit.routing-decision/v1 JSON file.

.PARAMETER Mode
Scout mode: 'dry-run' (default) or 'live-delivery' (blocked/unimplemented).

.PARAMETER FirstMateTaskId
FirstMate task identifier.

.PARAMETER InstructionSummary
Instruction packet summary (1..4000 chars).

.PARAMETER ProofGate
Proof gate text (1..4000 chars).

.PARAMETER AllowMutation
Whether mutation is allowed (default True).

.PARAMETER AllowedScopes
Array of allowed scope patterns.

.PARAMETER ForbiddenScopes
Array of forbidden scope patterns.

.PARAMETER ExpectedGeneration
Expected task generation (optional).

.PARAMETER Variables
Hashtable of resolved variables.

.PARAMETER EvidenceRoot
Custom evidence root directory (optional).

.EXAMPLE
Invoke-PromptDispatchScout.ps1 `
    -DecisionPath .\.ai\harness\fixtures\fm-asb-promptkit\routing-decision.valid.json `
    -FirstMateTaskId "task-scout-01" `
    -InstructionSummary "Test scout contract translation" `
    -ProofGate "Prove dispatch artifact structure"

.EXAMPLE
Invoke-PromptDispatchScout.ps1 `
    -DecisionPath .\my-decision.json `
    -Mode live-delivery `
    -FirstMateTaskId "task-42" `
    -InstructionSummary "Attempt live delivery" `
    -ProofGate "Observe blocked status"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$DecisionPath,

    [ValidateSet('dry-run', 'live-delivery')]
    [string]$Mode = 'dry-run',

    [Parameter(Mandatory)]
    [string]$FirstMateTaskId,

    [Parameter(Mandatory)]
    [string]$InstructionSummary,

    [Parameter(Mandatory)]
    [string]$ProofGate,

    [bool]$AllowMutation = $true,

    [string[]]$AllowedScopes = @(),

    [string[]]$ForbiddenScopes = @(),

    [int]$ExpectedGeneration = $null,

    [hashtable]$Variables = @{},

    [string]$EvidenceRoot = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
$scoutScript = Join-Path $scriptDir 'scout_prompt_dispatch.py'

if (-not (Test-Path -LiteralPath $scoutScript -PathType Leaf)) {
    throw "Scout script not found: $scoutScript"
}

# Build command-line arguments
$args = @(
    $scoutScript
    '--decision'
    $DecisionPath
    '--mode'
    $Mode
    '--firstmate-task-id'
    $FirstMateTaskId
    '--instruction-summary'
    $InstructionSummary
    '--proof-gate'
    $ProofGate
)

if (-not $AllowMutation) {
    $args += '--allow-mutation'
    $args += 'false'
}

foreach ($scope in $AllowedScopes) {
    $args += '--allowed-scope'
    $args += $scope
}

foreach ($scope in $ForbiddenScopes) {
    $args += '--forbidden-scope'
    $args += $scope
}

if ($null -ne $ExpectedGeneration) {
    $args += '--expected-generation'
    $args += $ExpectedGeneration.ToString()
}

foreach ($key in $Variables.Keys) {
    $value = $Variables[$key]
    if ($value -is [string]) {
        $jsonValue = $value
    } else {
        $jsonValue = ConvertTo-Json -InputObject $value -Compress -Depth 10
    }
    $args += '--var'
    $args += "$key=$jsonValue"
}

if ($EvidenceRoot) {
    $args += '--evidence-root'
    $args += $EvidenceRoot
}

# Execute scout
$result = & python3 @args
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host "Scout execution: SUCCESS" -ForegroundColor Green
} elseif ($exitCode -eq 1) {
    Write-Host "Scout execution: BLOCKED or UNIMPLEMENTED" -ForegroundColor Yellow
} else {
    Write-Host "Scout execution: ERROR" -ForegroundColor Red
}

# Parse and display result
try {
    $resultObj = $result | ConvertFrom-Json
    Write-Host ""
    Write-Host "Scout Result:" -ForegroundColor Cyan
    Write-Host "  Status: $($resultObj.status)"
    Write-Host "  Mode: $($resultObj.mode)"
    Write-Host "  Proof Ceiling: $($resultObj.proofCeiling)"

    if ($resultObj.artifactPath) {
        Write-Host "  Artifact: $($resultObj.artifactPath)" -ForegroundColor Green
    }

    if ($resultObj.reason) {
        Write-Host "  Reason: $($resultObj.reason)" -ForegroundColor Yellow
    }

    if ($resultObj.notes) {
        Write-Host "  Notes:"
        foreach ($note in $resultObj.notes) {
            Write-Host "    - $note"
        }
    }
} catch {
    Write-Warning "Could not parse scout result JSON"
    Write-Host $result
}

exit $exitCode
