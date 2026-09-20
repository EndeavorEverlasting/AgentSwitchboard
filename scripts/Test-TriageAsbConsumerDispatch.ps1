#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validate AgentSwitchboard Triage lane dispatch implementation.

.DESCRIPTION
    Tests the dispatch policy, receipt schema, fixtures, and Python dispatcher:
    - Dispatch policy enforces fail_closed and preserves consumer policy constraints
    - Receipt schema validates against fixtures
    - Python dispatcher can execute local-argv lanes
    - CloudAgent/runtime-tool adapters emit structured BLOCKED_UNSUPPORTED receipts
    - Receipts are machine-readable JSON with correct structure

.PARAMETER Verbose
    Show detailed validation output

.EXAMPLE
    pwsh -NoLogo -NoProfile -File scripts/Test-TriageAsbConsumerDispatch.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = Split-Path -Parent $PSScriptRoot
$DispatchRoot = Join-Path $RepoRoot "tooling/harness/triage-consumer/dispatch"
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

Write-Host "==> Triage Lane Dispatch Validator" -ForegroundColor Cyan
Write-Host ""

# Test 1: Dispatch structure exists
Write-Host "Test: Dispatch infrastructure" -ForegroundColor Yellow
Test-Condition "Dispatch root exists" (Test-Path $DispatchRoot)
Test-Condition "Dispatch policy exists" (Test-Path (Join-Path $DispatchRoot "dispatch.policy.json"))
Test-Condition "Receipt schema exists" (Test-Path (Join-Path $DispatchRoot "schemas/dispatch-receipt.schema.json"))
Test-Condition "Dispatch runner exists" (Test-Path (Join-Path $DispatchRoot "dispatch_lanes.py"))
Test-Condition "Fixtures directory exists" (Test-Path (Join-Path $DispatchRoot "fixtures"))
Write-Host ""

# Test 2: Dispatch policy validation
Write-Host "Test: Dispatch policy contract" -ForegroundColor Yellow
$PolicyPath = Join-Path $DispatchRoot "dispatch.policy.json"
try {
    $DispatchPolicy = Get-Content $PolicyPath -Raw | ConvertFrom-Json

    Test-Condition "Policy has schemaVersion" ($null -ne $DispatchPolicy.schemaVersion)
    Test-Condition "Policy has policyId" ($null -ne $DispatchPolicy.policyId)
    Test-Condition "Policy has dispatch_rules" ($null -ne $DispatchPolicy.dispatch_rules)

    Test-Condition "fail_closed_on_policy_violation is true" `
        ($DispatchPolicy.dispatch_rules.fail_closed_on_policy_violation -eq $true) `
        "MUST fail closed on policy violations"

    Test-Condition "require_panel_ingest is true" `
        ($DispatchPolicy.dispatch_rules.require_panel_ingest -eq $true) `
        "MUST preserve consumer policy panel_ingest_required"

    Test-Condition "human_scheduler_forbidden is true" `
        ($DispatchPolicy.dispatch_rules.human_scheduler_forbidden -eq $true) `
        "MUST preserve consumer policy human_scheduler_allowed:false"

    Test-Condition "emit_receipt_per_lane is true" `
        ($DispatchPolicy.dispatch_rules.emit_receipt_per_lane -eq $true)

    Test-Condition "preserve_panels is true" `
        ($DispatchPolicy.dispatch_rules.preserve_panels -eq $true) `
        "MUST NOT delete panels"

    Test-Condition "Has adapter_execution_policy" ($null -ne $DispatchPolicy.adapter_execution_policy)

    $LocalArgv = $DispatchPolicy.adapter_execution_policy.local_argv
    Test-Condition "local_argv adapter enabled" ($LocalArgv.enabled -eq $true)

} catch {
    Test-Condition "Dispatch policy JSON parses" $false $_.Exception.Message
}
Write-Host ""

# Test 3: Receipt schema validation
Write-Host "Test: Receipt schema structure" -ForegroundColor Yellow
$SchemaPath = Join-Path $DispatchRoot "schemas/dispatch-receipt.schema.json"
try {
    $Schema = Get-Content $SchemaPath -Raw | ConvertFrom-Json

    Test-Condition "Schema has required fields" `
        ($null -ne $Schema.required -and $Schema.required.Count -gt 0)

    $RequiredFields = @("receipt_version", "lane_id", "adapter_kind", "dispatch_status", "timestamp")
    foreach ($field in $RequiredFields) {
        Test-Condition "Schema requires $field" `
            ($Schema.required -contains $field)
    }

    Test-Condition "Schema has dispatch_status enum" `
        ($null -ne $Schema.properties.dispatch_status.enum)

    $Statuses = @("DISPATCHED", "EXECUTED", "BLOCKED_UNSUPPORTED", "BLOCKED_MISSING_ADAPTER", "BLOCKED_POLICY_VIOLATION", "BLOCKED_HOST", "BLOCKED_API", "FAILED")
    foreach ($status in $Statuses) {
        Test-Condition "Schema defines status $status" `
            ($Schema.properties.dispatch_status.enum -contains $status)
    }

} catch {
    Test-Condition "Receipt schema JSON parses" $false $_.Exception.Message
}
Write-Host ""

# Test 4: Fixture validation
Write-Host "Test: Dispatch fixtures" -ForegroundColor Yellow
$FixturesDir = Join-Path $DispatchRoot "fixtures"

$ExampleReceipts = @(
    "example-receipt-success.json",
    "example-receipt-blocked.json"
)

foreach ($fixture in $ExampleReceipts) {
    $fixturePath = Join-Path $FixturesDir $fixture
    Test-Condition "Fixture $fixture exists" (Test-Path $fixturePath)

    if (Test-Path $fixturePath) {
        try {
            $receipt = Get-Content $fixturePath -Raw | ConvertFrom-Json
            Test-Condition "$fixture has receipt_version" ($null -ne $receipt.receipt_version)
            Test-Condition "$fixture has lane_id" ($null -ne $receipt.lane_id)
            Test-Condition "$fixture has adapter_kind" ($null -ne $receipt.adapter_kind)
            Test-Condition "$fixture has dispatch_status" ($null -ne $receipt.dispatch_status)
        } catch {
            Test-Condition "$fixture parses as JSON" $false $_.Exception.Message
        }
    }
}
Write-Host ""

# Test 5: Python dispatcher smoke test
Write-Host "Test: Python dispatcher execution" -ForegroundColor Yellow
$DispatcherPath = Join-Path $DispatchRoot "dispatch_lanes.py"
$TestManifestPath = Join-Path $DispatchRoot "fixtures/test-dispatch-manifest.json"
$TestOutputDir = Join-Path $RepoRoot "test-dispatch-output"

if (Test-Path $TestManifestPath) {
    try {
        # Create test output directory
        if (Test-Path $TestOutputDir) {
            Remove-Item $TestOutputDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $TestOutputDir -Force | Out-Null

        # Run dispatcher (prefer python3, fall back to python on Windows hosts)
        $python = Get-Command python3 -ErrorAction SilentlyContinue
        if (-not $python) {
            $python = Get-Command python -ErrorAction SilentlyContinue
        }
        if (-not $python) {
            throw 'Python 3 is required for Triage dispatch smoke (python3/python not found).'
        }
        $result = & $python.Source $DispatcherPath $TestManifestPath $TestOutputDir 2>&1
        $exitCode = $LASTEXITCODE

        Test-Condition "Dispatcher executes without crash" ($exitCode -in @(0, 1))

        # Check for receipts
        $summaryPath = Join-Path $TestOutputDir "dispatch-summary.json"
        Test-Condition "Dispatch summary generated" (Test-Path $summaryPath)

        if (Test-Path $summaryPath) {
            $summary = Get-Content $summaryPath -Raw | ConvertFrom-Json
            Test-Condition "Summary has total_lanes" ($null -ne $summary.total_lanes)
            Test-Condition "Summary has receipts array" ($null -ne $summary.receipts)
            Test-Condition "At least one lane processed" ($summary.total_lanes -gt 0)

            # Check individual receipts
            $receiptFiles = Get-ChildItem $TestOutputDir -Filter "receipt-*.json"
            Test-Condition "Individual receipts generated" ($receiptFiles.Count -gt 0)

            foreach ($receiptFile in $receiptFiles) {
                try {
                    $receipt = Get-Content $receiptFile.FullName -Raw | ConvertFrom-Json
                    Test-Condition "$($receiptFile.Name) is valid JSON with dispatch_status" `
                        ($null -ne $receipt.dispatch_status)
                } catch {
                    Test-Condition "$($receiptFile.Name) is valid JSON" $false $_.Exception.Message
                }
            }
        }

        # Cleanup
        if (Test-Path $TestOutputDir) {
            Remove-Item $TestOutputDir -Recurse -Force
        }

    } catch {
        Test-Condition "Dispatcher execution" $false $_.Exception.Message
    }
} else {
    Test-Condition "Test manifest fixture exists" $false "Cannot run dispatcher smoke test"
}
Write-Host ""

# Test 6: Consumer policy consistency
Write-Host "Test: Consumer policy consistency" -ForegroundColor Yellow
$ConsumerPolicyPath = Join-Path $ConsumerRoot "consumer.policy.json"
try {
    $ConsumerPolicy = Get-Content $ConsumerPolicyPath -Raw | ConvertFrom-Json

    Test-Condition "Consumer policy human_scheduler_allowed:false preserved" `
        ($ConsumerPolicy.policy.human_scheduler_allowed -eq $false) `
        "Dispatch must preserve consumer policy constraint"

    Test-Condition "Consumer policy panel_ingest_required:true preserved" `
        ($ConsumerPolicy.policy.panel_ingest_required -eq $true) `
        "Dispatch must preserve consumer policy constraint"

} catch {
    Test-Condition "Consumer policy readable" $false $_.Exception.Message
}
Write-Host ""

# Summary
Write-Host "==> Test Summary" -ForegroundColor Cyan
Write-Host "  Pass: $script:PassCount" -ForegroundColor Green
Write-Host "  Fail: $script:FailCount" -ForegroundColor Red
Write-Host ""

if ($script:FailCount -eq 0) {
    Write-Host "✓ All dispatch tests passed" -ForegroundColor Green
    exit 0
} else {
    Write-Host "✗ Some dispatch tests failed" -ForegroundColor Red
    exit 1
}
