#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
Generate machine-local P67 OpenCode adapter configuration (ADP-02).

.DESCRIPTION
Generates configuration for P67 Triage compute-authority adapter, matching the
compute-authority-agent-adapter/v1 schema. Contains only names, paths, provider/model
identity, and limits. NEVER stores credential values.

Config points to Invoke-P67OpenCodeAdapter.ps1 as the canonical argv target.

.PARAMETER OutputPath
Path to write the generated JSON config. Required.

.PARAMETER Provider
OpenCode provider name (e.g., "anthropic", "openai"). Required.

.PARAMETER Model
Model identifier (e.g., "claude-sonnet-4", "gpt-4"). Required.

.PARAMETER Agent
Agent/system identifier for pairing. Defaults to "opencode-v2".

.PARAMETER TimeoutSeconds
Maximum execution timeout in seconds. Defaults to 900 (15 minutes).

.PARAMETER CredentialEnvVars
Comma-separated list of environment variable names that hold credentials (e.g., "ANTHROPIC_API_KEY,OPENAI_API_KEY").
Only variable names are stored, never values.

.PARAMETER AdapterRoot
Root path to AgentSwitchboard repository. Defaults to script's grandparent directory.

.EXAMPLE
./New-P67AdapterConfig.ps1 -OutputPath /tmp/p67-config.json -Provider anthropic -Model claude-sonnet-4

.EXAMPLE
./New-P67AdapterConfig.ps1 -OutputPath config.json -Provider openai -Model gpt-4 -CredentialEnvVars OPENAI_API_KEY -TimeoutSeconds 600

.NOTES
ADP-02: Machine-local config generator only. Does not execute provider or store secrets.
Forbidden: credential values, raw prompts, global config mutation.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$OutputPath,

    [Parameter(Mandatory)]
    [string]$Provider,

    [Parameter(Mandatory)]
    [string]$Model,

    [string]$Agent = 'opencode-v2',

    [ValidateRange(60, 3600)]
    [int]$TimeoutSeconds = 900,

    [string]$CredentialEnvVars = '',

    [string]$AdapterRoot = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-DiagnosticMessage {
    param([string]$Message)
    if ($VerbosePreference -eq 'Continue') {
        Write-Host "[CONFIG] $Message" -ForegroundColor Cyan
    }
}

function Get-AdapterRootPath {
    param([string]$ProvidedRoot)

    if ($ProvidedRoot) {
        $resolved = Resolve-Path -LiteralPath $ProvidedRoot -ErrorAction Stop
        return $resolved.Path
    }

    $scriptDir = Split-Path -Parent $PSCommandPath
    $parentDir = Split-Path -Parent $scriptDir
    $rootCandidate = Split-Path -Parent $parentDir

    if (Test-Path -LiteralPath (Join-Path $rootCandidate '.git') -PathType Container) {
        return (Resolve-Path -LiteralPath $rootCandidate).Path
    }

    throw "Could not resolve AgentSwitchboard root. Provide -AdapterRoot explicitly."
}

function New-AdapterConfig {
    param(
        [string]$InvokeScriptPath,
        [string]$ProviderName,
        [string]$ModelName,
        [string]$AgentName,
        [int]$Timeout,
        [string[]]$EnvAllowlist
    )

    $config = [ordered]@{
        schema_version = 'compute-authority-agent-adapter/v1'
        adapter_identity = [ordered]@{
            provider = $ProviderName
            model = $ModelName
            agent = $AgentName
            adapter_version = 'asb-p67-opencode-adp-02/v1'
        }
        argv = @(
            'pwsh',
            '-NoLogo',
            '-NoProfile',
            '-File',
            $InvokeScriptPath,
            '-Workspace', '{workspace}',
            '-Task', '{task}',
            '-Prompt', '{prompt}',
            '-Result', '{result}',
            '-Provider', $ProviderName,
            '-Model', $ModelName,
            '-Agent', $AgentName
        )
        timeout_seconds = $Timeout
        env_allowlist = $EnvAllowlist
        forbidden_fields = @(
            'api_key',
            'token',
            'secret',
            'password',
            'credential'
        )
    }

    return $config
}

try {
    Write-DiagnosticMessage "Generating P67 OpenCode adapter config (ADP-02)"
    Write-DiagnosticMessage "Provider: $Provider, Model: $Model, Agent: $Agent"

    $rootPath = Get-AdapterRootPath -ProvidedRoot $AdapterRoot
    $invokeScriptPath = Join-Path $rootPath 'tooling/evals/p67-opencode-adapter/Invoke-P67OpenCodeAdapter.ps1'

    if (-not (Test-Path -LiteralPath $invokeScriptPath -PathType Leaf)) {
        throw "Invoke script not found: $invokeScriptPath"
    }

    $envAllowlist = @()
    if ($CredentialEnvVars) {
        $envAllowlist = @($CredentialEnvVars -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }

    Write-DiagnosticMessage "Credential env vars (names only): $($envAllowlist -join ', ')"
    Write-DiagnosticMessage "Timeout: ${TimeoutSeconds}s"

    $config = New-AdapterConfig `
        -InvokeScriptPath $invokeScriptPath `
        -ProviderName $Provider `
        -ModelName $Model `
        -AgentName $Agent `
        -Timeout $TimeoutSeconds `
        -EnvAllowlist $envAllowlist

    $json = $config | ConvertTo-Json -Depth 10

    $credentialPattern = '(api[_-]?key|token|secret|password).*[:=]\s*[a-zA-Z0-9+/]{10,}'
    if ($json -match $credentialPattern) {
        throw "SECURITY: Generated config contains potential credential values. This is forbidden."
    }

    $json | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM

    Write-DiagnosticMessage "Config written to: $OutputPath"
    Write-Host "P67 OpenCode adapter config generated successfully" -ForegroundColor Green
    Write-Host "Provider: $Provider | Model: $Model | Agent: $Agent" -ForegroundColor Green
    Write-Host "Output: $OutputPath" -ForegroundColor Green

    exit 0

} catch {
    Write-Error "Config generation failed: $($_.Exception.Message)"
    exit 1
}
