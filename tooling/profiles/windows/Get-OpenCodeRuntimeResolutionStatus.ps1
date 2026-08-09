[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))),
    [switch]$ObserveCurrentProcess,
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$registryPath = Join-Path $RootPath 'tooling\profiles\windows\harness\opencode-runtime-resolution\runtime-resolution.registry.json'
$reportTemplatePath = Join-Path $RootPath 'tooling\profiles\windows\harness\opencode-runtime-resolution\operator-report.template.md'
if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) { throw "OpenCode runtime-resolution registry is missing: $registryPath" }
if (-not (Test-Path -LiteralPath $reportTemplatePath -PathType Leaf)) { throw "OpenCode runtime-resolution report template is missing: $reportTemplatePath" }

$registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json
$requiredTracked = @(
    'tooling/profiles/windows/harness/opencode-runtime-resolution/codebase-map.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/runtime-resolution.registry.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/artifact-registry.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/composition.graph.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/workflows/runtime-resolution-intake.workflow.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/workflows/path-collision-diagnosis.workflow.json',
    'tooling/profiles/windows/harness/opencode-runtime-resolution/schemas/opencode-runtime-resolution.schema.json',
    '.ai/skills/opencode-runtime-resolution/SKILL.md',
    'scripts/Test-OpenCodeRuntimeResolutionHarness.ps1',
    'tests/test_opencode_runtime_resolution_harness.py',
    'docs/harness/opencode-runtime-resolution-harness.md'
)

$missing = [System.Collections.Generic.List[string]]::new()
foreach ($relativePath in $requiredTracked) {
    if (-not (Test-Path -LiteralPath (Join-Path $RootPath $relativePath) -PathType Leaf)) { [void]$missing.Add($relativePath) }
}

$observation = $null
if ($ObserveCurrentProcess) {
    if ($env:OS -ne 'Windows_NT') { throw '-ObserveCurrentProcess is a Windows-only local observation.' }

    $allOpenCode = @(Get-Command opencode -All -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{
            name = $_.Name
            commandType = [string]$_.CommandType
            source = [string]$_.Source
            path = [string]$_.Path
        }
    })
    $selected = if ($allOpenCode.Count -gt 0) { $allOpenCode[0] } else { $null }
    $shimPath = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\bin\opencode.cmd'
    $statePath = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\GnhfFleet\state.json'
    $stateOpenCode = $null
    if (Test-Path -LiteralPath $statePath -PathType Leaf) {
        try {
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            if ($state.agents -and $state.agents.PSObject.Properties['opencode']) {
                $record = $state.agents.opencode
                $stateOpenCode = [ordered]@{
                    commandPath = [string]$record.commandPath
                    integration = [string]$record.integration
                    available = [bool]$record.available
                    version = [string]$record.version
                }
            }
        }
        catch {
            $stateOpenCode = [ordered]@{ error = $_.Exception.Message }
        }
    }

    $classification = 'unresolved-runtime-identity'
    if ($selected) {
        $selectedPath = [string]$selected.path
        $asbShimRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\bin'
        $npmRoot = Join-Path $env:APPDATA 'npm'
        if ($selectedPath -and $selectedPath.StartsWith($asbShimRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $classification = 'agentswitchboard-wsl-shim-selected'
        }
        elseif ($selectedPath -and $selectedPath.StartsWith($npmRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $classification = 'native-windows-selected'
        }
        else {
            $classification = 'unknown-resolver-selected'
        }
    }

    $observation = [ordered]@{
        capturedAt = (Get-Date).ToUniversalTime().ToString('o')
        selected = $selected
        allOpenCodeCommands = $allOpenCode
        processPath = @($env:Path -split ';' | Where-Object { $_ })
        userPath = @(([Environment]::GetEnvironmentVariable('Path', 'User')) -split ';' | Where-Object { $_ })
        machinePath = @(([Environment]::GetEnvironmentVariable('Path', 'Machine')) -split ';' | Where-Object { $_ })
        agentSwitchboardShimPath = $shimPath
        agentSwitchboardShimExists = (Test-Path -LiteralPath $shimPath -PathType Leaf)
        fleetStatePath = $statePath
        fleetStateOpenCode = $stateOpenCode
        parentClassification = $classification
        effectiveChildResolution = $null
        proofCeiling = 'Current PowerShell and known local path observation only; effective AgentSwitchboard/GNHF/OpenCode child identity is not established.'
    }
}

$status = if ($missing.Count -eq 0) { 'ready' } else { 'incomplete' }
Write-Host 'OPENCODE RUNTIME RESOLUTION HARNESS' -ForegroundColor Cyan
Write-Host "Repository: $RootPath"
Write-Host "Registry:   $($registry.registryId)"
Write-Host "Status:     $status"
Write-Host "Missing:    $($missing.Count)"
Write-Host "Proof:      $($registry.proofCeiling)"
if ($observation) {
    Write-Host "Parent:     $($observation.parentClassification)"
    Write-Host 'Child:      unresolved unless separately captured through the exact launch chain'
}

if ($OutputRoot) {
    $fullOutputRoot = [IO.Path]::GetFullPath($OutputRoot)
    $fullRepoRoot = [IO.Path]::GetFullPath($RootPath)
    if ($fullOutputRoot.StartsWith($fullRepoRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Runtime-resolution reports must be written outside the repository.'
    }
    $null = New-Item -ItemType Directory -Path $fullOutputRoot -Force
    $jsonPath = Join-Path $fullOutputRoot 'opencode-runtime-resolution-snapshot.json'
    $reportPath = Join-Path $fullOutputRoot 'opencode-runtime-operator-report.md'
    [ordered]@{
        schema = 'agentswitchboard.opencode-runtime-resolution-status.v1'
        repository = $RootPath
        status = $status
        missing = @($missing)
        observation = $observation
        tracked = $false
        proofCeiling = $registry.proofCeiling
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM

    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add('# OpenCode Runtime Resolution Report')
    [void]$lines.Add('')
    [void]$lines.Add("- Repository harness status: $status")
    [void]$lines.Add("- Missing tracked components: $($missing.Count)")
    [void]$lines.Add("- Parent observation requested: $([bool]$ObserveCurrentProcess)")
    if ($observation) { [void]$lines.Add("- Parent classification: $($observation.parentClassification)") }
    [void]$lines.Add('')
    [void]$lines.Add('## Working')
    [void]$lines.Add('Tracked runtime-resolution contracts can classify native Windows, declared WSL, and native-shadowed-by-WSL-shim evidence.')
    [void]$lines.Add('')
    [void]$lines.Add('## Broken')
    [void]$lines.Add('No machine repair is performed by this report. Any observed resolver mismatch remains an owning runtime/product defect until repaired and rerun.')
    [void]$lines.Add('')
    [void]$lines.Add('## Missing')
    [void]$lines.Add('The exact failing AgentSwitchboard/GNHF/OpenCode child-process executable identity remains unproved unless separately captured through that exact launch chain.')
    [void]$lines.Add('')
    [void]$lines.Add('## Proof ceiling')
    [void]$lines.Add($registry.proofCeiling)
    $lines | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM
    Write-Host "Snapshot:   $jsonPath"
    Write-Host "Report:     $reportPath"
}

if ($missing.Count -gt 0) { exit 1 }
exit 0
