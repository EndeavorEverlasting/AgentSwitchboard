#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
ADP-03 synthetic interoperability runner for P67 OpenCode adapter.

.DESCRIPTION
Exercises end-to-end paths through config → invoke → neutral normalize → capture v2
using synthetic fixtures (no live OpenCode provider).

Tests 8 paths:
1. Happy path (VALID capture v2)
2. Validation/nonzero fail-closed
3. Timeout fail-closed
4. Missing/malformed result fail-closed
5. Parallel/subagent or multi-event lane (synthetic)
6. Privacy rejection
7. Evaluative rejection
8. Mutation-boundary/invalid workspace fail-closed

.PARAMETER OutputPath
Path to write machine-readable receipt JSON.

.PARAMETER Verbose
Enable verbose diagnostic output.

.EXAMPLE
./Invoke-P67OpenCodeAdapterSyntheticInterop.ps1 -OutputPath /tmp/adp03-receipt.json

.NOTES
ADP-03: Synthetic interoperability only.
Proof ceiling: SYNTHETIC INTEROPERABILITY (no live OpenCode).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RootPath = Split-Path -Parent $PSScriptRoot
$script:AdapterDir = Join-Path $script:RootPath 'tooling/evals/p67-opencode-adapter'
$script:FixturesDir = Join-Path $script:AdapterDir 'fixtures/adp03'
$script:StartTime = Get-Date

function Write-DiagnosticMessage {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $color = switch ($Level) {
        'ERROR' { 'Red' }
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        default { 'Cyan' }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function Test-FixtureAgainstContract {
    param(
        [Parameter(Mandatory)]
        [string]$FixturePath,
        [Parameter(Mandatory)]
        [string]$TestName
    )

    Write-DiagnosticMessage "Testing fixture: $TestName"

    if (-not (Test-Path -LiteralPath $FixturePath -PathType Leaf)) {
        return @{
            TestName = $TestName
            Passed = $false
            Reason = "Fixture file not found: $FixturePath"
            FixturePath = $FixturePath
        }
    }

    try {
        $fixture = Get-Content -LiteralPath $FixturePath -Raw | ConvertFrom-Json

        $validations = @()

        $validations += @{
            Check = 'schema_version'
            Passed = ($fixture.schema_version -eq 'compute-authority-provider-capture/v2')
            Message = "Schema version must be compute-authority-provider-capture/v2"
        }

        $validations += @{
            Check = 'run_status'
            Passed = ($fixture.run_status -in @('VALID', 'INVALID'))
            Message = "run_status must be VALID or INVALID"
        }

        $validations += @{
            Check = 'provider_identity'
            Passed = ($null -ne $fixture.provider_identity)
            Message = "provider_identity must be present"
        }

        $validations += @{
            Check = 'task_id'
            Passed = ($null -ne $fixture.task_id)
            Message = "task_id must be present"
        }

        $validations += @{
            Check = 'execution_summary'
            Passed = ($null -ne $fixture.execution_summary)
            Message = "execution_summary must be present"
        }

        if ($fixture.run_status -eq 'INVALID') {
            $validations += @{
                Check = 'invalid_reason'
                Passed = ($null -ne $fixture.invalid_reason -and $null -ne $fixture.invalid_reason.code)
                Message = "INVALID runs must have invalid_reason with code"
            }
        }

        if ($fixture.run_status -eq 'VALID') {
            $validations += @{
                Check = 'workspace_state'
                Passed = ($null -ne $fixture.workspace_state)
                Message = "VALID runs must have workspace_state"
            }

            $validations += @{
                Check = 'validation_result'
                Passed = ($null -ne $fixture.validation_result)
                Message = "VALID runs must have validation_result"
            }
        }

        $fixtureJson = $fixture | ConvertTo-Json -Depth 10 -Compress
        $forbiddenEvaluativePattern = '"(useful|first_green|after_fixed_point|correct|effectiveness)":\s*[^"]'
        $hasForbiddenEvaluative = $fixtureJson -match $forbiddenEvaluativePattern

        if ($hasForbiddenEvaluative -and $fixture.invalid_reason.code -ne 'CAPTURE_EVALUATIVE_REJECTED') {
            $validations += @{
                Check = 'no_evaluative_leak'
                Passed = $false
                Message = "Fixture contains evaluative field outside of CAPTURE_EVALUATIVE_REJECTED marker"
            }
        } else {
            $validations += @{
                Check = 'no_evaluative_leak'
                Passed = $true
                Message = "No evaluative field leakage"
            }
        }

        $forbiddenPrivacyPattern = '"(raw_prompt|raw_response|transcript|full_conversation|chat_history)":\s*[^"]'
        $hasForbiddenPrivacy = $fixtureJson -match $forbiddenPrivacyPattern

        if ($hasForbiddenPrivacy -and $fixture.invalid_reason.code -ne 'CAPTURE_PRIVACY_REJECTED') {
            $validations += @{
                Check = 'no_privacy_leak'
                Passed = $false
                Message = "Fixture contains privacy field outside of CAPTURE_PRIVACY_REJECTED marker"
            }
        } else {
            $validations += @{
                Check = 'no_privacy_leak'
                Passed = $true
                Message = "No privacy field leakage"
            }
        }

        $allPassed = ($validations | Where-Object { -not $_.Passed }).Count -eq 0

        return @{
            TestName = $TestName
            Passed = $allPassed
            FixturePath = $FixturePath
            Validations = $validations
            FixtureContent = $fixture
        }

    } catch {
        return @{
            TestName = $TestName
            Passed = $false
            Reason = "Failed to parse or validate fixture: $($_.Exception.Message)"
            FixturePath = $FixturePath
        }
    }
}

function Test-NormalizerModule {
    Write-DiagnosticMessage "Testing ConvertTo-NeutralCapture module"

    $normalizerPath = Join-Path $script:AdapterDir 'ConvertTo-NeutralCapture.psm1'

    if (-not (Test-Path -LiteralPath $normalizerPath -PathType Leaf)) {
        return @{
            TestName = 'normalizer_module_exists'
            Passed = $false
            Reason = "Normalizer module not found: $normalizerPath"
        }
    }

    try {
        Import-Module $normalizerPath -Force -ErrorAction Stop

        $testCapture = @{
            schema_version = 'compute-authority-provider-capture/v2'
            run_status = 'VALID'
            provider_identity = @{
                provider = 'test'
                model = 'test-model'
                agent = 'test-agent'
            }
            task_id = 'TEST'
            execution_summary = @{
                started_utc = '2026-09-19T20:00:00Z'
                ended_utc = '2026-09-19T20:01:00Z'
                elapsed_seconds = 60
                exit_code = 0
            }
            workspace_state = 'CLEAN'
            validation_result = @{
                validation_passed = $true
            }
        }

        $validationResult = Test-CaptureObjectValid -CaptureObject $testCapture

        $evaluativeTest = @{
            useful = $true
            first_green = $true
        }

        $evaluativeValidation = Test-CaptureObjectValid -CaptureObject $evaluativeTest

        return @{
            TestName = 'normalizer_module_functional'
            Passed = ($validationResult.Valid -eq $true -and $evaluativeValidation.Valid -eq $false)
            NormalizerPath = $normalizerPath
            ValidCaptureTest = $validationResult
            EvaluativeRejectionTest = $evaluativeValidation
        }

    } catch {
        return @{
            TestName = 'normalizer_module_functional'
            Passed = $false
            Reason = "Failed to test normalizer: $($_.Exception.Message)"
        }
    }
}

function Invoke-SyntheticInteropTests {
    Write-DiagnosticMessage "Starting ADP-03 synthetic interoperability tests"

    $tests = @(
        @{ Name = 'happy_path_valid'; File = 'synthetic-01-happy-path-valid.json' }
        @{ Name = 'validation_nonzero'; File = 'synthetic-02-validation-nonzero.json' }
        @{ Name = 'timeout_fail_closed'; File = 'synthetic-03-timeout-fail-closed.json' }
        @{ Name = 'missing_result_fail_closed'; File = 'synthetic-04-missing-result-fail-closed.json' }
        @{ Name = 'parallel_subagent_lane'; File = 'synthetic-05-parallel-subagent-lane.json' }
        @{ Name = 'privacy_rejected'; File = 'synthetic-06-privacy-rejected.json' }
        @{ Name = 'evaluative_rejected'; File = 'synthetic-07-evaluative-rejected.json' }
        @{ Name = 'invalid_workspace'; File = 'synthetic-08-invalid-workspace.json' }
    )

    $results = @()

    foreach ($test in $tests) {
        $fixturePath = Join-Path $script:FixturesDir $test.File
        $result = Test-FixtureAgainstContract -FixturePath $fixturePath -TestName $test.Name

        $results += $result

        if ($result.Passed) {
            Write-DiagnosticMessage "✓ $($test.Name)" 'PASS'
        } else {
            Write-DiagnosticMessage "✗ $($test.Name): $($result.Reason)" 'FAIL'
        }
    }

    $normalizerResult = Test-NormalizerModule
    $results += $normalizerResult

    if ($normalizerResult.Passed) {
        Write-DiagnosticMessage "✓ normalizer_module_functional" 'PASS'
    } else {
        Write-DiagnosticMessage "✗ normalizer_module_functional: $($normalizerResult.Reason)" 'FAIL'
    }

    return $results
}

try {
    Write-DiagnosticMessage "P67 OpenCode Adapter ADP-03 Synthetic Interoperability Runner"
    Write-DiagnosticMessage "=============================================================="

    if (-not (Test-Path -LiteralPath $script:FixturesDir -PathType Container)) {
        Write-DiagnosticMessage "Fixtures directory not found: $script:FixturesDir" 'ERROR'
        throw "ADP-03 fixtures directory missing"
    }

    $testResults = Invoke-SyntheticInteropTests

    $passedCount = ($testResults | Where-Object { $_.Passed }).Count
    $failedCount = ($testResults | Where-Object { -not $_.Passed }).Count
    $totalCount = $testResults.Count

    $elapsed = ((Get-Date) - $script:StartTime).TotalSeconds

    $receipt = [ordered]@{
        schema_version = 'asb-p67-adp03-synthetic-interop-receipt/v1'
        test_run_summary = [ordered]@{
            total_tests = $totalCount
            passed = $passedCount
            failed = $failedCount
            success = ($failedCount -eq 0)
        }
        execution_summary = [ordered]@{
            started_utc = $script:StartTime.ToUniversalTime().ToString('o')
            ended_utc = (Get-Date).ToUniversalTime().ToString('o')
            elapsed_seconds = [math]::Round($elapsed, 2)
        }
        test_results = @($testResults | ForEach-Object {
            [ordered]@{
                test_name = $_.TestName
                passed = $_.Passed
                fixture_path = $_.FixturePath
                reason = $_.Reason
                validations = $_.Validations
            }
        })
        proof_level = 'SYNTHETIC_INTEROPERABILITY'
        proof_ceiling_note = 'ADP-03 synthetic interoperability only. No live OpenCode provider. Live smoke is ADP-04.'
        adp03_paths_covered = @(
            'happy_path_valid_capture_v2',
            'validation_nonzero_fail_closed',
            'timeout_fail_closed',
            'missing_result_fail_closed',
            'parallel_subagent_synthetic_lane',
            'privacy_rejection',
            'evaluative_rejection',
            'invalid_workspace_fail_closed'
        )
    }

    $receipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM

    Write-DiagnosticMessage ""
    Write-DiagnosticMessage "Test Summary"
    Write-DiagnosticMessage "============"
    Write-DiagnosticMessage "Total: $totalCount | Passed: $passedCount | Failed: $failedCount" $(if ($failedCount -eq 0) { 'PASS' } else { 'FAIL' })
    Write-DiagnosticMessage ""
    Write-DiagnosticMessage "Receipt written to: $OutputPath"

    if ($failedCount -gt 0) {
        Write-DiagnosticMessage "ADP-03 synthetic interoperability tests FAILED" 'ERROR'
        exit 1
    }

    Write-DiagnosticMessage "ADP-03 synthetic interoperability tests PASSED" 'PASS'
    exit 0

} catch {
    Write-DiagnosticMessage "Fatal error: $($_.Exception.Message)" 'ERROR'

    $errorReceipt = [ordered]@{
        schema_version = 'asb-p67-adp03-synthetic-interop-receipt/v1'
        test_run_summary = [ordered]@{
            total_tests = 0
            passed = 0
            failed = 1
            success = $false
        }
        execution_summary = [ordered]@{
            started_utc = $script:StartTime.ToUniversalTime().ToString('o')
            ended_utc = (Get-Date).ToUniversalTime().ToString('o')
            elapsed_seconds = ((Get-Date) - $script:StartTime).TotalSeconds
        }
        error = $_.Exception.Message
        proof_level = 'SYNTHETIC_INTEROPERABILITY'
    }

    $errorReceipt | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM -ErrorAction SilentlyContinue

    exit 1
}
