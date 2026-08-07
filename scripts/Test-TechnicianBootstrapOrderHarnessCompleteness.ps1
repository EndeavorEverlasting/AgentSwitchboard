[CmdletBinding()]
param(
    [string]$RootPath,
    [switch]$NoWrite,
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { throw 'Unable to resolve validator directory. Supply -RootPath.' }
    $RootPath = Split-Path -Parent $PSScriptRoot
}
$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path
$registryPath = Join-Path $RootPath 'tooling\profiles\windows\harness\technician-ready\harness.registry.json'
$failures = [Collections.Generic.List[string]]::new()
$checks = [Collections.Generic.List[object]]::new()
$registry = $null

function Add-Check {
    param([string]$Name, [bool]$Passed, [string]$Detail)
    [void]$checks.Add([pscustomobject]@{ name = $Name; passed = $Passed; detail = $Detail })
    if (-not $Passed) { [void]$failures.Add("${Name}: $Detail") }
}

if (-not (Test-Path -LiteralPath $registryPath -PathType Leaf)) {
    Add-Check 'registry-present' $false $registryPath
} else {
    try { $registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json; Add-Check 'registry-json' $true 'parsed' }
    catch { Add-Check 'registry-json' $false $_.Exception.Message }
}

if ($failures.Count -eq 0) {
    $missing = @()
    foreach ($relativePath in @($registry.requiredPaths)) {
        if (-not (Test-Path -LiteralPath (Join-Path $RootPath ([string]$relativePath)) -PathType Leaf)) { $missing += [string]$relativePath }
    }
    Add-Check 'required-components' ($missing.Count -eq 0) $(if ($missing.Count -eq 0) { 'all registered files exist' } else { $missing -join ', ' })

    $jsonPaths = @($registry.requiredPaths | Where-Object { ([string]$_).EndsWith('.json', [StringComparison]::OrdinalIgnoreCase) })
    foreach ($relativePath in $jsonPaths) {
        try { $null = Get-Content -LiteralPath (Join-Path $RootPath ([string]$relativePath)) -Raw | ConvertFrom-Json; Add-Check ("json:{0}" -f $relativePath) $true 'parsed' }
        catch { Add-Check ("json:{0}" -f $relativePath) $false $_.Exception.Message }
    }

    $routing = Get-Content -LiteralPath (Join-Path $RootPath 'tooling\profiles\windows\harness\technician-ready\skill-routing.registry.json') -Raw | ConvertFrom-Json
    $routeIds = @($routing.routes | ForEach-Object { [string]$_.workflowId })
    foreach ($workflowId in @($registry.workflowIds)) {
        Add-Check ("workflow-route:{0}" -f $workflowId) ($workflowId -in $routeIds) 'workflow must be routed'
    }

    $artifactRegistry = Get-Content -LiteralPath (Join-Path $RootPath 'tooling\profiles\windows\harness\technician-ready\artifact-registry.json') -Raw | ConvertFrom-Json
    Add-Check 'artifacts-untracked' (-not [bool]$artifactRegistry.tracked) 'generated evidence must remain untracked'

    $workflowText = Get-Content -LiteralPath (Join-Path $RootPath '.github\workflows\technician-bootstrap-order.yml') -Raw
    foreach ($token in @('tests.test_technician_bootstrap_order_harness', 'Test-TechnicianBootstrapOrderHarnessCompleteness.ps1', 'Get-TechnicianBootstrapOrderHarnessStatus.ps1', 'tests.test_technician_bootstrap_order', 'tests.test_technician_agentswitchboard_ready', 'git diff --check')) {
        Add-Check ("ci-token:{0}" -f $token) ($workflowText.Contains($token)) 'CI must run the focused floor'
    }

    $skillText = Get-Content -LiteralPath (Join-Path $RootPath '.ai\skills\technician-bootstrap-order-validation\SKILL.md') -Raw
    foreach ($token in @('repair-failure', 'validate-change', 'handoff', 'Never weaken', 'Proof ceiling')) {
        Add-Check ("skill-token:{0}" -f $token) ($skillText.Contains($token)) 'skill must preserve routing and gate integrity'
    }

    $hookText = Get-Content -LiteralPath (Join-Path $RootPath 'tooling\profiles\windows\hooks\Invoke-TechnicianBootstrapOrderPreCommit.ps1') -Raw
    foreach ($token in @('tests.test_technician_bootstrap_order_harness', 'Test-TechnicianBootstrapOrderHarnessCompleteness.ps1', 'Test-TechnicianBootstrapOrder.ps1', 'diff --cached --check')) {
        Add-Check ("hook-token:{0}" -f $token) ($hookText.Contains($token)) 'opt-in hook must run focused validation'
    }

    foreach ($relativePath in @(
        'tooling/profiles/windows/Get-TechnicianBootstrapOrderHarnessStatus.ps1',
        'tooling/profiles/windows/hooks/Invoke-TechnicianBootstrapOrderPreCommit.ps1',
        'scripts/Test-TechnicianBootstrapOrderHarnessCompleteness.ps1'
    )) {
        $tokens = $null
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $RootPath $relativePath), [ref]$tokens, [ref]$parseErrors)
        Add-Check ("powershell-parse:{0}" -f $relativePath) ($parseErrors.Count -eq 0) $(if ($parseErrors.Count -eq 0) { 'parsed' } else { ($parseErrors | ForEach-Object { $_.Message }) -join '; ' })
    }
}

$status = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
$result = [ordered]@{
    schema = 'agentswitchboard.technician-bootstrap-order-harness-validation.v1'
    status = $status
    repository = 'EndeavorEverlasting/AgentSwitchboard'
    checks = @($checks)
    failures = @($failures)
    proofCeiling = if ($null -ne $registry) { [string]$registry.proofCeiling } else { 'Harness registry unavailable; no proof promoted.' }
}

Write-Host ("TECHNICIAN BOOTSTRAP-ORDER HARNESS: {0}" -f $status) -ForegroundColor $(if ($status -eq 'PASS') { 'Green' } else { 'Red' })
Write-Host ("Checks: {0}; Failures: {1}" -f $checks.Count, $failures.Count)
$failures | ForEach-Object { Write-Host ("- {0}" -f $_) -ForegroundColor Red }

if (-not $NoWrite) {
    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $runId = '{0}-{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')), ([guid]::NewGuid().ToString('N').Substring(0, 8))
        $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [System.IO.Path]::GetTempPath() }
        $OutputDirectory = Join-Path $base ("AgentSwitchboard/technician-bootstrap-order/runs/{0}" -f $runId)
    }
    $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
    $path = Join-Path $OutputDirectory 'bootstrap-order-harness-validation.json'
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding utf8
    Write-Host ("JSON: {0}" -f $path)
}

if ($failures.Count -gt 0) { exit 1 }
exit 0
