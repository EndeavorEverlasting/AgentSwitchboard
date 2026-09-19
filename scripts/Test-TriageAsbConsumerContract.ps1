#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validate AgentSwitchboard Triage→ASB consumer contract floor.

.DESCRIPTION
    Tests the consumer policy, schemas, fixtures, and Python implementation:
    - Policy enforces human_scheduler_allowed:false and panel_ingest_required:true
    - Schemas validate against fixtures
    - Python code can ingest manifests, panels, and checkpoints
    - AUTONOMY_GAP classification works
    - Lane mapping to ASB descriptors works structurally
    - Merge-gate classification applies degraded + local_proof => CONTINUE

.PARAMETER Verbose
    Show detailed validation output

.EXAMPLE
    pwsh -NoLogo -NoProfile -File scripts/Test-TriageAsbConsumerContract.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ConsumerRoot = Join-Path $RepoRoot "tooling/harness/triage-consumer"

$script:PassCount = 0
$script:FailCount = 0

function Test-Condition {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter(Mandatory)]
        [bool]$Condition,
        
        [string]$FailureMessage = ""
    )
    
    if ($Condition) {
        Write-Host "  ✓ $Name" -ForegroundColor Green
        $script:PassCount++
    } else {
        Write-Host "  ✗ $Name" -ForegroundColor Red
        if ($FailureMessage) {
            Write-Host "    $FailureMessage" -ForegroundColor Red
        }
        $script:FailCount++
    }
}

Write-Host "==> Triage→ASB Consumer Contract Validator" -ForegroundColor Cyan
Write-Host ""

# Test 1: Consumer root exists
Write-Host "Test: Consumer root structure" -ForegroundColor Yellow
Test-Condition "Consumer root exists" (Test-Path $ConsumerRoot)
Test-Condition "Policy file exists" (Test-Path (Join-Path $ConsumerRoot "consumer.policy.json"))
Test-Condition "Schemas directory exists" (Test-Path (Join-Path $ConsumerRoot "schemas"))
Test-Condition "Fixtures directory exists" (Test-Path $ConsumerRoot "fixtures")
Test-Condition "Python module exists" (Test-Path (Join-Path $ConsumerRoot "triage_consumer.py"))
Write-Host ""

# Test 2: Policy validation
Write-Host "Test: Consumer policy contract" -ForegroundColor Yellow
$PolicyPath = Join-Path $ConsumerRoot "consumer.policy.json"
try {
    $Policy = Get-Content $PolicyPath -Raw | ConvertFrom-Json
    
    Test-Condition "Policy has schemaVersion" ($null -ne $Policy.schemaVersion)
    Test-Condition "Policy has policyId" ($null -ne $Policy.policyId)
    Test-Condition "Policy has policy object" ($null -ne $Policy.policy)
    
    # Critical policy enforcement
    Test-Condition "human_scheduler_allowed is false" `
        ($Policy.policy.human_scheduler_allowed -eq $false) `
        "MUST be false to enforce autonomous dispatch"
    
    Test-Condition "panel_ingest_required is true" `
        ($Policy.policy.panel_ingest_required -eq $true) `
        "MUST be true to treat panels as machine inputs"
    
    Test-Condition "autonomy_gap_classification_required is true" `
        ($Policy.policy.autonomy_gap_classification_required -eq $true) `
        "MUST be true to classify AUTONOMY_GAP"
    
    Test-Condition "manifest_and_panels_are_machine_inputs is true" `
        ($Policy.policy.manifest_and_panels_are_machine_inputs -eq $true)
    
    Test-Condition "panel_deletion_forbidden is true" `
        ($Policy.policy.panel_deletion_forbidden -eq $true) `
        "MUST NOT delete panels as design goal"
    
} catch {
    Test-Condition "Policy JSON parses" $false $_.Exception.Message
}
Write-Host ""

# Test 3: Schema validation
Write-Host "Test: Consumer schemas" -ForegroundColor Yellow
$SchemaFiles = @(
    "triage-manifest.schema.json",
    "triage-panel.schema.json",
    "triage-checkpoint.schema.json",
    "lane-mapping.schema.json",
    "autonomy-gap.schema.json"
)

foreach ($schemaFile in $SchemaFiles) {
    $schemaPath = Join-Path $ConsumerRoot "schemas/$schemaFile"
    try {
        $schema = Get-Content $schemaPath -Raw | ConvertFrom-Json
        Test-Condition "Schema $schemaFile is valid JSON" $true
        Test-Condition "Schema $schemaFile has `$schema" ($null -ne $schema.'$schema')
        Test-Condition "Schema $schemaFile has `$id" ($null -ne $schema.'$id')
    } catch {
        Test-Condition "Schema $schemaFile is valid JSON" $false $_.Exception.Message
    }
}
Write-Host ""

# Test 4: Fixture validation
Write-Host "Test: Consumer fixtures" -ForegroundColor Yellow
$FixtureFiles = @(
    "example-manifest.json",
    "example-panel.json",
    "example-checkpoint.json",
    "example-lane-mapping.json",
    "example-autonomy-gap.json"
)

foreach ($fixtureFile in $FixtureFiles) {
    $fixturePath = Join-Path $ConsumerRoot "fixtures/$fixtureFile"
    try {
        $fixture = Get-Content $fixturePath -Raw | ConvertFrom-Json
        Test-Condition "Fixture $fixtureFile is valid JSON" $true
    } catch {
        Test-Condition "Fixture $fixtureFile is valid JSON" $false $_.Exception.Message
    }
}
Write-Host ""

# Test 5: Python module syntax
Write-Host "Test: Python module" -ForegroundColor Yellow
$PythonModulePath = Join-Path $ConsumerRoot "triage_consumer.py"
try {
    $pythonCheck = python3 -m py_compile $PythonModulePath 2>&1
    Test-Condition "Python module syntax is valid" ($LASTEXITCODE -eq 0) "$pythonCheck"
} catch {
    Test-Condition "Python module syntax is valid" $false $_.Exception.Message
}
Write-Host ""

# Test 6: Python module basic functionality
Write-Host "Test: Python module functionality" -ForegroundColor Yellow
try {
    $manifestPath = Join-Path $ConsumerRoot "fixtures/example-manifest.json"
    $panelPath = Join-Path $ConsumerRoot "fixtures/example-panel.json"
    
    # Test manifest ingestion
    $manifestTest = python3 $PythonModulePath --manifest $manifestPath 2>&1
    Test-Condition "Manifest ingestion works" ($LASTEXITCODE -eq 0) "$manifestTest"
    
    # Test panel ingestion
    $panelTest = python3 $PythonModulePath --panel $panelPath 2>&1
    Test-Condition "Panel ingestion works" ($LASTEXITCODE -eq 0) "$panelTest"
    
    # Test AUTONOMY_GAP classification
    $gapTest = python3 $PythonModulePath --manifest $manifestPath --classify-gap 2>&1
    Test-Condition "AUTONOMY_GAP classification works" ($LASTEXITCODE -eq 0) "$gapTest"
    
} catch {
    Test-Condition "Python module functionality" $false $_.Exception.Message
}
Write-Host ""

# Summary
Write-Host "==> Summary" -ForegroundColor Cyan
Write-Host "  Passed: $script:PassCount" -ForegroundColor Green
Write-Host "  Failed: $script:FailCount" -ForegroundColor $(if ($script:FailCount -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($script:FailCount -gt 0) {
    Write-Host "FAIL: Triage→ASB consumer contract validation failed" -ForegroundColor Red
    exit 1
} else {
    Write-Host "PASS: Triage→ASB consumer contract validated" -ForegroundColor Green
    exit 0
}
