#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
Regression test for Invoke-P67OpenCodeAdapter.ps1 parameter case-collision fix (LPW003ASI173).

.DESCRIPTION
Validates that the Invoke script:
1. Writes valid JSON to the caller-supplied ResultPath (not a type name string)
2. Never outputs "System.Collections.Specialized.OrderedDictionary" to the result file
3. Result file exists at the exact caller-supplied path
4. Result contains run_status INVALID when OpenCode is missing or times out
5. Result parses as valid JSON with proper capture contract v2 schema

This test catches the PowerShell case-insensitive variable collision bug where
param([string]$Result) and local $result = [ordered]@{...} reference the same
variable, causing OrderedDictionary → string coercion and the result file never
landing at the caller-supplied path.

.EXAMPLE
./Test-P67InvokeResultPathCollision.ps1
Runs regression test and exits with 0 on success, 1 on failure.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
$InvokeScript = Join-Path $ScriptDir 'Invoke-P67OpenCodeAdapter.ps1'

$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [string]$FailureMessage = ''
    )
    if ($Passed) {
        [void]$passes.Add($Name)
    } else {
        [void]$failures.Add("${Name}: $FailureMessage")
    }
}

Write-Host '[TEST] Running P67 Invoke adapter ResultPath collision regression test' -ForegroundColor Cyan

$invokeScriptExists = Test-Path -LiteralPath $InvokeScript -PathType Leaf
Add-Result -Passed $invokeScriptExists `
    -Name 'invoke-script-exists' `
    -FailureMessage "Invoke script not found at $InvokeScript"

if (-not $invokeScriptExists) {
    Write-Host "FAILED: Invoke script not found" -ForegroundColor Red
    exit 1
}

try {
    Write-Host '[TEST] Creating temporary workspace and result path...' -ForegroundColor Cyan
    
    $tempWorkspace = Join-Path ([System.IO.Path]::GetTempPath()) "p67-test-workspace-$(New-Guid)"
    $tempResultPath = Join-Path ([System.IO.Path]::GetTempPath()) "p67-test-result-$(New-Guid).json"
    
    New-Item -ItemType Directory -Path $tempWorkspace -Force | Out-Null
    & git init $tempWorkspace 2>&1 | Out-Null
    
    Write-Host "[TEST] Workspace: $tempWorkspace" -ForegroundColor Cyan
    Write-Host "[TEST] Result path: $tempResultPath" -ForegroundColor Cyan
    
    Add-Result -Passed (Test-Path -LiteralPath $tempWorkspace -PathType Container) `
        -Name 'workspace-created' `
        -FailureMessage 'Failed to create temporary workspace'
    
    Write-Host '[TEST] Executing Invoke script with missing OpenCode (should produce INVALID result)...' -ForegroundColor Cyan
    
    $invokeArgs = @(
        '-Workspace', $tempWorkspace,
        '-Task', 'REGRESSION_TEST_LPW003ASI173',
        '-Prompt', 'Test prompt for regression',
        '-ResultPath', $tempResultPath,
        '-Provider', 'test-provider',
        '-Model', 'test-model',
        '-TimeoutSeconds', '5'
    )
    
    $env:PATH_BACKUP = $env:PATH
    $env:PATH = ''
    
    try {
        $invokeProcess = Start-Process -FilePath 'pwsh' `
            -ArgumentList @('-NoLogo', '-NoProfile', '-File', $InvokeScript) + $invokeArgs `
            -Wait `
            -PassThru `
            -NoNewWindow `
            -RedirectStandardOutput (Join-Path ([System.IO.Path]::GetTempPath()) "invoke-stdout-$(New-Guid).txt") `
            -RedirectStandardError (Join-Path ([System.IO.Path]::GetTempPath()) "invoke-stderr-$(New-Guid).txt")
        
        $invokeExitCode = $invokeProcess.ExitCode
    } finally {
        $env:PATH = $env:PATH_BACKUP
    }
    
    Write-Host "[TEST] Invoke exited with code: $invokeExitCode" -ForegroundColor Cyan
    
    Add-Result -Passed ($invokeExitCode -eq 1) `
        -Name 'invoke-exit-code-invalid' `
        -FailureMessage "Invoke should exit 1 for INVALID run, got: $invokeExitCode"
    
    $resultFileExists = Test-Path -LiteralPath $tempResultPath -PathType Leaf
    Add-Result -Passed $resultFileExists `
        -Name 'result-file-exists-at-caller-path' `
        -FailureMessage "Result file not found at caller-supplied path: $tempResultPath (THIS IS THE BUG)"
    
    if ($resultFileExists) {
        $resultContent = Get-Content -LiteralPath $tempResultPath -Raw
        
        Write-Host "[TEST] Result file size: $($resultContent.Length) bytes" -ForegroundColor Cyan
        
        $notTypeString = -not ($resultContent -match 'System\.Collections\.Specialized\.OrderedDictionary')
        Add-Result -Passed $notTypeString `
            -Name 'result-not-type-string' `
            -FailureMessage "Result contains OrderedDictionary type name (case-collision bug): $resultContent"
        
        $resultNotEmpty = $resultContent.Trim().Length -gt 0
        Add-Result -Passed $resultNotEmpty `
            -Name 'result-not-empty' `
            -FailureMessage 'Result file is empty'
        
        if ($resultNotEmpty) {
            try {
                $resultObject = $resultContent | ConvertFrom-Json -ErrorAction Stop
                
                $jsonParsed = $true
                Add-Result -Passed $jsonParsed `
                    -Name 'result-is-valid-json' `
                    -FailureMessage "Result is not valid JSON: $resultContent"
                
                $hasSchemaVersion = $null -ne $resultObject.PSObject.Properties['schema_version']
                Add-Result -Passed $hasSchemaVersion `
                    -Name 'has-schema-version' `
                    -FailureMessage 'Result missing schema_version property'
                
                if ($hasSchemaVersion) {
                    $correctSchema = $resultObject.schema_version -eq 'compute-authority-provider-capture/v2'
                    Add-Result -Passed $correctSchema `
                        -Name 'correct-schema-version' `
                        -FailureMessage "Expected capture/v2 schema, got: $($resultObject.schema_version)"
                }
                
                $hasRunStatus = $null -ne $resultObject.PSObject.Properties['run_status']
                Add-Result -Passed $hasRunStatus `
                    -Name 'has-run-status' `
                    -FailureMessage 'Result missing run_status property'
                
                if ($hasRunStatus) {
                    $runStatusInvalid = $resultObject.run_status -eq 'INVALID'
                    Add-Result -Passed $runStatusInvalid `
                        -Name 'run-status-is-invalid' `
                        -FailureMessage "Expected run_status INVALID, got: $($resultObject.run_status)"
                }
                
                $hasInvalidReason = $null -ne $resultObject.PSObject.Properties['invalid_reason']
                Add-Result -Passed $hasInvalidReason `
                    -Name 'has-invalid-reason' `
                    -FailureMessage 'INVALID result missing invalid_reason property'
                
                if ($hasInvalidReason) {
                    $invalidCode = $resultObject.invalid_reason.code
                    $validInvalidCode = $invalidCode -in @('RUNTIME_UNAVAILABLE', 'ADAPTER_ERROR', 'EXECUTION_TIMEOUT', 'WORKSPACE_INVALID')
                    Add-Result -Passed $validInvalidCode `
                        -Name 'invalid-reason-code-valid' `
                        -FailureMessage "Expected known invalid_reason.code, got: $invalidCode"
                    
                    $hasInvalidMessage = $null -ne $resultObject.invalid_reason.message -and $resultObject.invalid_reason.message.Length -gt 5
                    Add-Result -Passed $hasInvalidMessage `
                        -Name 'invalid-reason-has-message' `
                        -FailureMessage 'invalid_reason.message missing or too short'
                }
                
                $hasProviderIdentity = $null -ne $resultObject.PSObject.Properties['provider_identity']
                Add-Result -Passed $hasProviderIdentity `
                    -Name 'has-provider-identity' `
                    -FailureMessage 'Result missing provider_identity'
                
                $hasTaskId = $null -ne $resultObject.PSObject.Properties['task_id']
                Add-Result -Passed $hasTaskId `
                    -Name 'has-task-id' `
                    -FailureMessage 'Result missing task_id'
                
                if ($hasTaskId) {
                    $taskIdMatches = $resultObject.task_id -eq 'REGRESSION_TEST_LPW003ASI173'
                    Add-Result -Passed $taskIdMatches `
                        -Name 'task-id-matches-input' `
                        -FailureMessage "Task ID mismatch, expected REGRESSION_TEST_LPW003ASI173, got: $($resultObject.task_id)"
                }
                
            } catch {
                Add-Result -Passed $false `
                    -Name 'result-is-valid-json' `
                    -FailureMessage "Failed to parse JSON: $($_.Exception.Message). Content: $resultContent"
            }
        }
    } else {
        Write-Host '[TEST] Result file missing - checking if it landed elsewhere (the bug)...' -ForegroundColor Yellow
        
        $tempDir = [System.IO.Path]::GetTempPath()
        $suspiciousFiles = Get-ChildItem -Path $tempDir -Filter '*OrderedDictionary*' -ErrorAction SilentlyContinue
        
        if ($suspiciousFiles.Count -gt 0) {
            Write-Host "[TEST] Found suspicious OrderedDictionary files in temp:" -ForegroundColor Red
            foreach ($file in $suspiciousFiles) {
                Write-Host "  - $($file.FullName)" -ForegroundColor Red
            }
        }
    }
    
    Write-Host '[TEST] Cleaning up temporary files...' -ForegroundColor Cyan
    if (Test-Path -LiteralPath $tempWorkspace) {
        Remove-Item -LiteralPath $tempWorkspace -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $tempResultPath) {
        Remove-Item -LiteralPath $tempResultPath -Force -ErrorAction SilentlyContinue
    }
    
} catch {
    Add-Result -Passed $false `
        -Name 'script-execution' `
        -FailureMessage "Test execution failed: $($_.Exception.Message)"
}

Write-Host "`n=== Test Results ===" -ForegroundColor Cyan
Write-Host "PASSED: $($passes.Count)" -ForegroundColor Green
foreach ($pass in $passes) {
    Write-Host "  ✓ $pass" -ForegroundColor Green
}

if ($failures.Count -gt 0) {
    Write-Host "`nFAILED: $($failures.Count)" -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host "  ✗ $failure" -ForegroundColor Red
    }
    Write-Host "`nREGRESSION TEST FAILED" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nREGRESSION TEST PASSED" -ForegroundColor Green
    exit 0
}
