#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
Regression test for Get-P67OpenCodeAdapterStatus.ps1 case-collision fix (LPW003ASI173).

.DESCRIPTION
Validates that the status script:
1. Outputs valid JSON (not a type name string)
2. Has a 'status' property with READY or BLOCKED value
3. Never outputs "System.Collections.Specialized.OrderedDictionary"

This test catches the PowerShell case-insensitive variable collision bug where
param([string]$Status) and local $status = [ordered]@{...} reference the same
variable, causing OrderedDictionary → string coercion.

.EXAMPLE
./Test-P67OpenCodeAdapterStatus.ps1
Runs all regression tests and exits with 0 on success, 1 on failure.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $PSCommandPath
$StatusScript = Join-Path $ScriptDir 'Get-P67OpenCodeAdapterStatus.ps1'

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

Write-Host '[TEST] Running P67 OpenCode adapter status regression tests' -ForegroundColor Cyan

$statusScriptExists = Test-Path -LiteralPath $StatusScript -PathType Leaf
Add-Result -Passed $statusScriptExists `
    -Name 'status-script-exists' `
    -FailureMessage "Status script not found at $StatusScript"

if (-not $statusScriptExists) {
    Write-Host "FAILED: Status script not found" -ForegroundColor Red
    exit 1
}

try {
    Write-Host '[TEST] Executing status script...' -ForegroundColor Cyan
    $output = & $StatusScript 2>&1 | Out-String

    Write-Host "[TEST] Raw output length: $($output.Length) characters" -ForegroundColor Cyan

    $notTypeString = -not ($output -match 'System\.Collections\.Specialized\.OrderedDictionary')
    Add-Result -Passed $notTypeString `
        -Name 'output-not-type-string' `
        -FailureMessage "Output contains OrderedDictionary type name (case-collision bug): $output"

    $outputNotEmpty = $output.Trim().Length -gt 0
    Add-Result -Passed $outputNotEmpty `
        -Name 'output-not-empty' `
        -FailureMessage 'Status script produced empty output'

    if ($outputNotEmpty) {
        try {
            $statusObject = $output | ConvertFrom-Json -ErrorAction Stop

            $jsonParsed = $true
            Add-Result -Passed $jsonParsed `
                -Name 'output-is-valid-json' `
                -FailureMessage "Output is not valid JSON: $output"

            $hasStatusProperty = $null -ne $statusObject.PSObject.Properties['status']
            Add-Result -Passed $hasStatusProperty `
                -Name 'has-status-property' `
                -FailureMessage "JSON object missing 'status' property"

            if ($hasStatusProperty) {
                $statusValue = $statusObject.status
                $statusIsString = $statusValue -is [string]
                Add-Result -Passed $statusIsString `
                    -Name 'status-value-is-string' `
                    -FailureMessage "Status value is not a string: $($statusValue.GetType().Name)"

                $validStatusValue = $statusValue -in @('READY', 'BLOCKED')
                Add-Result -Passed $validStatusValue `
                    -Name 'status-value-valid' `
                    -FailureMessage "Status value '$statusValue' is not READY or BLOCKED"
            }

            $hasSchemaVersion = $null -ne $statusObject.PSObject.Properties['schema_version']
            Add-Result -Passed $hasSchemaVersion `
                -Name 'has-schema-version' `
                -FailureMessage 'JSON object missing schema_version property'

            $hasOpenCodeFound = $null -ne $statusObject.PSObject.Properties['opencode_found']
            Add-Result -Passed $hasOpenCodeFound `
                -Name 'has-opencode-found' `
                -FailureMessage 'JSON object missing opencode_found property'

            $hasCapabilities = $null -ne $statusObject.PSObject.Properties['capabilities_verified']
            Add-Result -Passed $hasCapabilities `
                -Name 'has-capabilities' `
                -FailureMessage 'JSON object missing capabilities_verified property'

        } catch {
            Add-Result -Passed $false `
                -Name 'output-is-valid-json' `
                -FailureMessage "Failed to parse JSON: $($_.Exception.Message). Output: $output"
        }
    }

} catch {
    Add-Result -Passed $false `
        -Name 'script-execution' `
        -FailureMessage "Script execution failed: $($_.Exception.Message)"
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
