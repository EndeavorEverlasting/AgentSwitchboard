#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
Read-only probe for OpenCode V2 provider capability and readiness (ADP-01).

.DESCRIPTION
Verifies required capabilities for P67 OpenCode adapter without mutating configuration
or persisting credentials. Returns structured readiness status aligned with capability-contract.v1.json
and Triage adapter-contract.v2.json vocabulary.

This is a read-only probe only. It does not implement the full ADP-02 adapter.

.PARAMETER OutputPath
Optional path to write JSON status. If omitted, writes to stdout.

.PARAMETER Verbose
Enable detailed diagnostic output to stderr.

.OUTPUTS
JSON object matching p67-opencode-readiness-status/v1 schema.

.EXAMPLE
./Get-P67OpenCodeAdapterStatus.ps1
Probes OpenCode readiness and writes JSON status to stdout.

.EXAMPLE
./Get-P67OpenCodeAdapterStatus.ps1 -OutputPath /tmp/opencode-status.json
Writes status to specified file.

.NOTES
ADP-01: Capability verification only. Does not execute provider or create adapter config.
Forbidden: credential exposure, global config mutation, raw prompt/response persistence.
#>

[CmdletBinding()]
param(
    [string]$OutputPath = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-DiagnosticMessage {
    param([string]$Message)
    if ($VerbosePreference -eq 'Continue') {
        Write-Host "[PROBE] $Message" -ForegroundColor Cyan
    }
}

function Get-OpenCodeVersion {
    try {
        $versionOutput = & opencode --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            $version = ($versionOutput | Select-Object -First 1) -replace '^[^0-9]*([0-9]+\.[0-9]+\.[0-9]+).*$', '$1'
            return @{ Found = $true; Version = $version; Output = $versionOutput }
        }
        return @{ Found = $false; Version = $null; Output = $versionOutput }
    } catch {
        return @{ Found = $false; Version = $null; Output = $_.Exception.Message }
    }
}

function Test-NoninteractiveExecution {
    param([hashtable]$VersionInfo)

    if (-not $VersionInfo.Found) {
        return @{ Status = 'BLOCKED'; Reason = 'OpenCode CLI not found' }
    }

    try {
        $runHelpOutput = & opencode run --help 2>&1
        $runHelpExitCode = $LASTEXITCODE

        $hasRunCommand = $runHelpExitCode -eq 0 -or $runHelpOutput -match 'run'

        if (-not $hasRunCommand) {
            $helpOutput = & opencode --help 2>&1
            $hasRunCommand = $helpOutput -match '\s+run\s+'
        }

        if ($hasRunCommand) {
            $hasFormatFlag = $runHelpOutput -match '--format'
            $hasModelFlag = $runHelpOutput -match '-m|--model'
            $hasDirFlag = $runHelpOutput -match '--dir'

            if ($hasFormatFlag -and $hasModelFlag -and $hasDirFlag) {
                return @{ Status = 'VERIFIED'; Reason = 'CLI with structured run command detected' }
            }

            return @{ Status = 'UNVERIFIED'; Reason = 'run command exists but required flags not clearly documented' }
        }

        return @{ Status = 'UNVERIFIED'; Reason = 'run command interface not clearly documented' }
    } catch {
        return @{ Status = 'BLOCKED'; Reason = "Help invocation failed: $($_.Exception.Message)" }
    }
}

function Test-ExplicitIdentity {
    param([hashtable]$VersionInfo)

    if (-not $VersionInfo.Found) {
        return @{ Status = 'BLOCKED'; Reason = 'OpenCode CLI not found' }
    }

    try {
        $runHelpOutput = & opencode run --help 2>&1

        $hasModelFlag = $runHelpOutput -match '-m|--model'
        $hasAgentFlag = $runHelpOutput -match '--agent'

        if ($hasModelFlag) {
            return @{ Status = 'VERIFIED'; Reason = 'Model identity flag found' }
        }

        return @{ Status = 'UNVERIFIED'; Reason = 'Model identity flags not clearly documented' }
    } catch {
        return @{ Status = 'BLOCKED'; Reason = "Identity verification failed: $($_.Exception.Message)" }
    }
}

function Test-IsolatedConfig {
    param([hashtable]$VersionInfo)

    if (-not $VersionInfo.Found) {
        return @{ Status = 'BLOCKED'; Reason = 'OpenCode CLI not found' }
    }

    try {
        $helpOutput = & opencode --help 2>&1

        $hasConfigFlag = $helpOutput -match '--config'
        $supportsEnvVars = $helpOutput -match 'OPENCODE_' -or $helpOutput -match 'environment variable'

        if ($hasConfigFlag -or $supportsEnvVars) {
            return @{ Status = 'VERIFIED'; Reason = 'Per-run configuration mechanism detected' }
        }

        return @{ Status = 'UNVERIFIED'; Reason = 'Isolated configuration mechanism not clearly documented' }
    } catch {
        return @{ Status = 'BLOCKED'; Reason = "Config verification failed: $($_.Exception.Message)" }
    }
}

function Test-InstrumentationFeasibility {
    param([hashtable]$VersionInfo)

    if (-not $VersionInfo.Found) {
        return @{ Status = 'BLOCKED'; Reason = 'OpenCode CLI not found' }
    }

    try {
        $runHelpOutput = & opencode run --help 2>&1

        $hasJsonFormat = $runHelpOutput -match '--format.*json'
        $hasVerboseLogging = $runHelpOutput -match '--verbose' -or $runHelpOutput -match '--debug'
        $hasLogFile = $runHelpOutput -match '--log'

        if ($hasJsonFormat -or $hasVerboseLogging -or $hasLogFile) {
            return @{ Status = 'VERIFIED'; Reason = 'Structured output or logging detected' }
        }

        return @{ Status = 'UNVERIFIED'; Reason = 'Instrumentation interface not clearly documented' }
    } catch {
        return @{ Status = 'BLOCKED'; Reason = "Instrumentation verification failed: $($_.Exception.Message)" }
    }
}

function Test-AuthReadiness {
    param([hashtable]$VersionInfo)

    if (-not $VersionInfo.Found) {
        return @{ Status = 'BLOCKED'; Reason = 'OpenCode CLI not found' }
    }

    try {
        $statusOutput = & opencode status 2>&1
        $statusExitCode = $LASTEXITCODE

        $credentialLeaked = $statusOutput -match '(api[_-]?key|token|secret|password).*[:=]\s*[a-zA-Z0-9+/]+'

        if ($credentialLeaked) {
            return @{ Status = 'BLOCKED'; Reason = 'SECURITY: Credentials exposed in status output' }
        }

        if ($statusExitCode -eq 0) {
            return @{ Status = 'VERIFIED'; Reason = 'Status command succeeded without credential exposure' }
        }

        if ($statusOutput -match '(auth|login|token|credential)') {
            return @{ Status = 'VERIFIED'; Reason = 'Auth status distinguishable from other errors' }
        }

        return @{ Status = 'UNVERIFIED'; Reason = 'Auth readiness signal not clearly distinguishable' }
    } catch {
        return @{ Status = 'UNVERIFIED'; Reason = "Status command unavailable: $($_.Exception.Message)" }
    }
}

function New-ReadinessStatus {
    param(
        [string]$Status,
        [bool]$OpenCodeFound,
        [string]$OpenCodeVersion,
        [hashtable]$Capabilities,
        [hashtable]$Blocker
    )

    $status = [ordered]@{
        schema_version = 'p67-opencode-readiness-status/v1'
        status = $Status
        opencode_found = $OpenCodeFound
        opencode_version = $OpenCodeVersion
        capabilities_verified = [ordered]@{
            noninteractive_execution = $Capabilities.noninteractive_execution
            explicit_identity = $Capabilities.explicit_identity
            isolated_config = $Capabilities.isolated_config
            instrumentation_feasibility = $Capabilities.instrumentation_feasibility
            auth_readiness = $Capabilities.auth_readiness
        }
        blocker = $Blocker
        probe_timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    }

    return $status
}

function ConvertTo-BlockerObject {
    param([string]$Code, [string]$Message)
    return [ordered]@{ code = $Code; message = $Message }
}

try {
    Write-DiagnosticMessage "Starting OpenCode capability probe (ADP-01)"

    $versionInfo = Get-OpenCodeVersion
    Write-DiagnosticMessage "OpenCode found: $($versionInfo.Found), Version: $($versionInfo.Version)"

    if (-not $versionInfo.Found) {
    $status = New-ReadinessStatus `
        -Status 'BLOCKED' `
        -OpenCodeFound $false `
        -OpenCodeVersion $null `
        -Capabilities @{
            noninteractive_execution = 'BLOCKED'
            explicit_identity = 'BLOCKED'
            isolated_config = 'BLOCKED'
            instrumentation_feasibility = 'BLOCKED'
            auth_readiness = 'BLOCKED'
        } `
        -Blocker (ConvertTo-BlockerObject 'OPENCODE_NOT_FOUND' 'OpenCode CLI not found in PATH. Install OpenCode or ensure it is available.')

        $jsonText = $status | ConvertTo-Json -Depth 10

        if ($OutputPath) {
            [string]$jsonText | Set-Content -LiteralPath $OutputPath -Encoding utf8
            Write-DiagnosticMessage "Status written to: $OutputPath"
        } else {
            Write-Output $jsonText
        }

        exit 0
    }

    $noninteractiveResult = Test-NoninteractiveExecution -VersionInfo $versionInfo
    $identityResult = Test-ExplicitIdentity -VersionInfo $versionInfo
    $configResult = Test-IsolatedConfig -VersionInfo $versionInfo
    $instrumentationResult = Test-InstrumentationFeasibility -VersionInfo $versionInfo
    $authResult = Test-AuthReadiness -VersionInfo $versionInfo

    Write-DiagnosticMessage "Noninteractive: $($noninteractiveResult.Status) - $($noninteractiveResult.Reason)"
    Write-DiagnosticMessage "Identity: $($identityResult.Status) - $($identityResult.Reason)"
    Write-DiagnosticMessage "Config: $($configResult.Status) - $($configResult.Reason)"
    Write-DiagnosticMessage "Instrumentation: $($instrumentationResult.Status) - $($instrumentationResult.Reason)"
    Write-DiagnosticMessage "Auth: $($authResult.Status) - $($authResult.Reason)"

    $allBlocked = @($noninteractiveResult, $identityResult, $configResult, $instrumentationResult, $authResult) | Where-Object { $_.Status -eq 'BLOCKED' }

    $overallStatus = 'READY'
    $blocker = $null

    if ($allBlocked.Count -gt 0) {
        $overallStatus = 'BLOCKED'
        $firstBlocker = $allBlocked[0]

        if ($firstBlocker.Reason -match 'not found') {
            $blocker = ConvertTo-BlockerObject 'OPENCODE_NOT_FOUND' $firstBlocker.Reason
        } elseif ($firstBlocker.Reason -match 'SECURITY') {
            $blocker = ConvertTo-BlockerObject 'CAPABILITY_PROBE_ERROR' $firstBlocker.Reason
        } elseif ($firstBlocker.Reason -match 'auth|login|credential') {
            $blocker = ConvertTo-BlockerObject 'OPENCODE_AUTH_UNAVAILABLE' $firstBlocker.Reason
        } elseif ($firstBlocker.Reason -match 'noninteractive|structured') {
            $blocker = ConvertTo-BlockerObject 'OPENCODE_NONINTERACTIVE_UNSUPPORTED' $firstBlocker.Reason
        } elseif ($firstBlocker.Reason -match 'identity|model|provider') {
            $blocker = ConvertTo-BlockerObject 'OPENCODE_IDENTITY_OPAQUE' $firstBlocker.Reason
        } elseif ($firstBlocker.Reason -match 'config') {
            $blocker = ConvertTo-BlockerObject 'OPENCODE_CONFIG_IMMUTABLE' $firstBlocker.Reason
        } elseif ($firstBlocker.Reason -match 'instrumentation|logging') {
            $blocker = ConvertTo-BlockerObject 'OPENCODE_INSTRUMENTATION_IMPOSSIBLE' $firstBlocker.Reason
        } else {
            $blocker = ConvertTo-BlockerObject 'CAPABILITY_PROBE_ERROR' $firstBlocker.Reason
        }
    }

    $status = New-ReadinessStatus `
        -Status $overallStatus `
        -OpenCodeFound $true `
        -OpenCodeVersion $versionInfo.Version `
        -Capabilities @{
            noninteractive_execution = $noninteractiveResult.Status
            explicit_identity = $identityResult.Status
            isolated_config = $configResult.Status
            instrumentation_feasibility = $instrumentationResult.Status
            auth_readiness = $authResult.Status
        } `
        -Blocker $blocker

    $jsonText = $status | ConvertTo-Json -Depth 10

    if ($OutputPath) {
        [string]$jsonText | Set-Content -LiteralPath $OutputPath -Encoding utf8
        Write-DiagnosticMessage "Status written to: $OutputPath"
    } else {
        Write-Output $jsonText
    }

    Write-DiagnosticMessage "Probe complete: $overallStatus"
    exit 0

} catch {
    $errorStatus = New-ReadinessStatus `
        -Status 'BLOCKED' `
        -OpenCodeFound $false `
        -OpenCodeVersion $null `
        -Capabilities @{
            noninteractive_execution = 'BLOCKED'
            explicit_identity = 'BLOCKED'
            isolated_config = 'BLOCKED'
            instrumentation_feasibility = 'BLOCKED'
            auth_readiness = 'BLOCKED'
        } `
        -Blocker (ConvertTo-BlockerObject 'CAPABILITY_PROBE_ERROR' "Probe execution failed: $($_.Exception.Message)")

    $jsonText = $errorStatus | ConvertTo-Json -Depth 10

    if ($OutputPath) {
        [string]$jsonText | Set-Content -LiteralPath $OutputPath -Encoding utf8
    } else {
        Write-Output $jsonText
    }

    exit 1
}
