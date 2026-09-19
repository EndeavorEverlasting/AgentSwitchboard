#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
Canonical P67 OpenCode adapter argv target (ADP-02).

.DESCRIPTION
Privacy-bounded OpenCode execution adapter for P67 Triage evaluation harness.
Consumes Triage capture contract v2 (neutral structural telemetry only).

Accepts only workspace/task/prompt/result placeholders via argv.
Executes OpenCode in isolated workspace with enforced bounds.
Emits one sanitized neutral result JSON.
Fails closed on timeout/nonzero/missing-result.

.PARAMETER Workspace
Path to isolated evaluation workspace (P67-owned fixture directory).

.PARAMETER Task
Task identifier for this evaluation run.

.PARAMETER Prompt
Frozen prompt text for this evaluation case.

.PARAMETER Result
Output path for result JSON (P67 capture contract v2 schema).

.PARAMETER Provider
OpenCode provider name (from config).

.PARAMETER Model
Model identifier (from config).

.PARAMETER Agent
Agent/system identifier for pairing (from config).

.PARAMETER TimeoutSeconds
Maximum execution timeout. Defaults to 600 seconds.

.EXAMPLE
./Invoke-P67OpenCodeAdapter.ps1 -Workspace /tmp/eval-workspace -Task TC01 -Prompt "Fix the bug" -Result /tmp/result.json -Provider anthropic -Model claude-sonnet-4

.NOTES
ADP-02: Privacy-bounded adapter implementation.
Forbidden: raw transcript persistence, global config mutation, self-grading.
Proof ceiling: IMPLEMENTATION + STATIC/SYNTHETIC VALIDATION.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Workspace,

    [Parameter(Mandatory)]
    [string]$Task,

    [Parameter(Mandatory)]
    [string]$Prompt,

    [Parameter(Mandatory)]
    [string]$Result,

    [Parameter(Mandatory)]
    [string]$Provider,

    [Parameter(Mandatory)]
    [string]$Model,

    [string]$Agent = 'opencode-v2',

    [int]$TimeoutSeconds = 600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:startTime = Get-Date
$script:ephemeralDir = $null

function Write-DiagnosticMessage {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $(if ($Level -eq 'ERROR') { 'Red' } else { 'Cyan' })
}

function New-InvalidRunResult {
    param(
        [string]$Code,
        [string]$Message,
        [hashtable]$Identity
    )

    $elapsed = ((Get-Date) - $script:startTime).TotalSeconds

    return [ordered]@{
        schema_version = 'compute-authority-provider-capture/v2'
        run_status = 'INVALID'
        invalid_reason = [ordered]@{
            code = $Code
            message = $Message
        }
        provider_identity = $Identity
        task_id = $Task
        execution_summary = [ordered]@{
            started_utc = $script:startTime.ToUniversalTime().ToString('o')
            ended_utc = (Get-Date).ToUniversalTime().ToString('o')
            elapsed_seconds = [math]::Round($elapsed, 2)
        }
    }
}

function New-ValidRunResult {
    param(
        [string]$WorkspaceState,
        [int]$ExitCode,
        [hashtable]$Identity,
        [hashtable]$ValidationResult
    )

    $elapsed = ((Get-Date) - $script:startTime).TotalSeconds

    return [ordered]@{
        schema_version = 'compute-authority-provider-capture/v2'
        run_status = 'VALID'
        provider_identity = $Identity
        task_id = $Task
        execution_summary = [ordered]@{
            started_utc = $script:startTime.ToUniversalTime().ToString('o')
            ended_utc = (Get-Date).ToUniversalTime().ToUniversalTime().ToString('o')
            elapsed_seconds = [math]::Round($elapsed, 2)
            exit_code = $ExitCode
        }
        workspace_state = $WorkspaceState
        validation_result = $ValidationResult
        neutral_telemetry = [ordered]@{
            provider_actions_count = 0
            subprocess_spawned = $false
        }
    }
}

function Test-WorkspaceValid {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return @{ Valid = $false; Reason = 'Workspace directory does not exist' }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $Path '.git') -PathType Container)) {
        return @{ Valid = $false; Reason = 'Workspace is not a git repository' }
    }

    return @{ Valid = $true; Reason = $null }
}

function Invoke-OpenCodeExecution {
    param(
        [string]$WorkspacePath,
        [string]$PromptText,
        [string]$ProviderName,
        [string]$ModelName,
        [string]$AgentName,
        [int]$Timeout
    )

    Write-DiagnosticMessage "Starting OpenCode execution (timeout: ${Timeout}s)"

    $ephemeralOutputFile = Join-Path $script:ephemeralDir 'opencode-output.txt'
    $ephemeralStderrFile = Join-Path $script:ephemeralDir 'opencode-stderr.txt'

    $modelSpec = "${ProviderName}/${ModelName}"

    $opencodeArgs = @(
        'run',
        $PromptText,
        '--format', 'json',
        '-m', $modelSpec,
        '--dir', $WorkspacePath
    )

    if ($AgentName) {
        $opencodeArgs += @('--agent', $AgentName)
    }

    Write-DiagnosticMessage "OpenCode command: opencode $($opencodeArgs -join ' ')"

    $startExec = Get-Date
    try {
        $process = Start-Process -FilePath 'opencode' `
            -ArgumentList $opencodeArgs `
            -WorkingDirectory $WorkspacePath `
            -RedirectStandardOutput $ephemeralOutputFile `
            -RedirectStandardError $ephemeralStderrFile `
            -NoNewWindow `
            -PassThru

        $completed = $process.WaitForExit($Timeout * 1000)
        $elapsedExec = ((Get-Date) - $startExec).TotalSeconds

        if (-not $completed) {
            Write-DiagnosticMessage "OpenCode execution timed out after ${Timeout}s" 'ERROR'
            $process.Kill($true)
            return @{
                Success = $false
                ExitCode = -1
                TimedOut = $true
                Elapsed = $elapsedExec
                Output = $null
            }
        }

        $exitCode = $process.ExitCode
        Write-DiagnosticMessage "OpenCode exited with code: $exitCode (elapsed: $([math]::Round($elapsedExec, 2))s)"

        $output = $null
        if (Test-Path -LiteralPath $ephemeralOutputFile -PathType Leaf) {
            $output = Get-Content -LiteralPath $ephemeralOutputFile -Raw
        }

        return @{
            Success = ($exitCode -eq 0)
            ExitCode = $exitCode
            TimedOut = $false
            Elapsed = $elapsedExec
            Output = $output
        }

    } catch {
        Write-DiagnosticMessage "OpenCode execution failed: $($_.Exception.Message)" 'ERROR'
        return @{
            Success = $false
            ExitCode = -1
            TimedOut = $false
            Elapsed = ((Get-Date) - $startExec).TotalSeconds
            Output = $null
            Error = $_.Exception.Message
        }
    }
}

function Get-WorkspaceState {
    param([string]$Path)

    try {
        Push-Location -LiteralPath $Path

        $gitStatus = & git status --porcelain 2>&1
        $hasChanges = $gitStatus.Count -gt 0

        $modified = @()
        $added = @()
        $deleted = @()

        if ($hasChanges) {
            foreach ($line in $gitStatus) {
                $status = $line.Substring(0, 2)
                $file = $line.Substring(3)

                if ($status -match 'M') { $modified += $file }
                if ($status -match 'A') { $added += $file }
                if ($status -match 'D') { $deleted += $file }
            }
        }

        return [ordered]@{
            has_changes = $hasChanges
            modified_files = @($modified | Select-Object -First 10)
            added_files = @($added | Select-Object -First 10)
            deleted_files = @($deleted | Select-Object -First 10)
        }

    } finally {
        Pop-Location
    }
}

function Invoke-WorkspaceValidation {
    param([string]$Path)

    Write-DiagnosticMessage "Running workspace validation"

    try {
        Push-Location -LiteralPath $Path

        $testResult = & python -m pytest --tb=short --timeout=30 2>&1
        $testExitCode = $LASTEXITCODE

        $passed = $testExitCode -eq 0

        return [ordered]@{
            validation_passed = $passed
            validation_command = 'python -m pytest'
            validation_exit_code = $testExitCode
        }

    } catch {
        Write-DiagnosticMessage "Validation failed: $($_.Exception.Message)" 'ERROR'
        return [ordered]@{
            validation_passed = $false
            validation_command = 'python -m pytest'
            validation_exit_code = -1
            validation_error = $_.Exception.Message
        }
    } finally {
        Pop-Location
    }
}

function Remove-EphemeralState {
    if ($script:ephemeralDir -and (Test-Path -LiteralPath $script:ephemeralDir)) {
        Write-DiagnosticMessage "Cleaning ephemeral state: $script:ephemeralDir"
        Remove-Item -LiteralPath $script:ephemeralDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

try {
    Write-DiagnosticMessage "P67 OpenCode Adapter (ADP-02) starting"
    Write-DiagnosticMessage "Task: $Task | Provider: $Provider | Model: $Model | Agent: $Agent"

    $identity = [ordered]@{
        provider = $Provider
        model = $Model
        agent = $Agent
        adapter_version = 'asb-p67-opencode-adp-02/v1'
    }

    $script:ephemeralDir = Join-Path ([System.IO.Path]::GetTempPath()) "p67-opencode-$(New-Guid)"
    New-Item -ItemType Directory -Path $script:ephemeralDir -Force | Out-Null
    Write-DiagnosticMessage "Ephemeral directory: $script:ephemeralDir"

    $workspaceCheck = Test-WorkspaceValid -Path $Workspace
    if (-not $workspaceCheck.Valid) {
        Write-DiagnosticMessage "Invalid workspace: $($workspaceCheck.Reason)" 'ERROR'
        $result = New-InvalidRunResult `
            -Code 'WORKSPACE_INVALID' `
            -Message $workspaceCheck.Reason `
            -Identity $identity

        $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Result -Encoding utf8NoBOM
        Remove-EphemeralState
        exit 1
    }

    Write-DiagnosticMessage "Workspace validated: $Workspace"

    $execResult = Invoke-OpenCodeExecution `
        -WorkspacePath $Workspace `
        -PromptText $Prompt `
        -ProviderName $Provider `
        -ModelName $Model `
        -AgentName $Agent `
        -Timeout $TimeoutSeconds

    if ($execResult.TimedOut) {
        Write-DiagnosticMessage "Execution timed out" 'ERROR'
        $result = New-InvalidRunResult `
            -Code 'EXECUTION_TIMEOUT' `
            -Message "OpenCode execution exceeded timeout of ${TimeoutSeconds}s" `
            -Identity $identity

        $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Result -Encoding utf8NoBOM
        Remove-EphemeralState
        exit 1
    }

    if (-not $execResult.Success -and $null -ne $execResult.Error) {
        Write-DiagnosticMessage "Execution failed: $($execResult.Error)" 'ERROR'
        $result = New-InvalidRunResult `
            -Code 'RUNTIME_UNAVAILABLE' `
            -Message "OpenCode execution failed: $($execResult.Error)" `
            -Identity $identity

        $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Result -Encoding utf8NoBOM
        Remove-EphemeralState
        exit 1
    }

    Write-DiagnosticMessage "Execution completed with exit code: $($execResult.ExitCode)"

    $workspaceState = Get-WorkspaceState -Path $Workspace
    $validationResult = Invoke-WorkspaceValidation -Path $Workspace

    Write-DiagnosticMessage "Workspace changes: $($workspaceState.has_changes)"
    Write-DiagnosticMessage "Validation passed: $($validationResult.validation_passed)"

    $result = New-ValidRunResult `
        -WorkspaceState ($workspaceState.has_changes ? 'MODIFIED' : 'CLEAN') `
        -ExitCode $execResult.ExitCode `
        -Identity $identity `
        -ValidationResult $validationResult

    $resultJson = $result | ConvertTo-Json -Depth 10

    $evaluativePattern = '"(useful|first_green|after_fixed_point|correct|effectiveness)"'
    if ($resultJson -match $evaluativePattern) {
        Write-DiagnosticMessage "SECURITY: Result contains evaluative fields. This violates CAPTURE_EVALUATIVE_REJECTED." 'ERROR'
        $invalidResult = New-InvalidRunResult `
            -Code 'CAPTURE_EVALUATIVE_REJECTED' `
            -Message "Adapter attempted to emit forbidden evaluative field" `
            -Identity $identity

        $invalidResult | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Result -Encoding utf8NoBOM
        Remove-EphemeralState
        exit 1
    }

    $resultJson | Set-Content -LiteralPath $Result -Encoding utf8NoBOM
    Write-DiagnosticMessage "Result written to: $Result"

    Remove-EphemeralState

    Write-DiagnosticMessage "P67 OpenCode Adapter completed successfully"
    exit 0

} catch {
    Write-DiagnosticMessage "Fatal error: $($_.Exception.Message)" 'ERROR'

    $result = New-InvalidRunResult `
        -Code 'ADAPTER_ERROR' `
        -Message "Adapter execution failed: $($_.Exception.Message)" `
        -Identity @{
            provider = $Provider
            model = $Model
            agent = $Agent
            adapter_version = 'asb-p67-opencode-adp-02/v1'
        }

    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Result -Encoding utf8NoBOM -ErrorAction SilentlyContinue

    Remove-EphemeralState

    exit 1
}
