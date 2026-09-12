[CmdletBinding()]
param([string]$RootPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = Split-Path -Parent $PSScriptRoot
}
$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path

$required = @(
    'tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1',
    'tooling/profiles/windows/Setup-TechnicianAgentSwitchboard.ps1',
    'Pull-And-Run-AgentSwitchboard.cmd',
    'Bootstrap-OpenCode-SystemWide.cmd',
    'Unbootstrap-OpenCode-SystemWide.cmd',
    'tooling/harness/system-bootstrap-lifecycle/BootstrapLifecycle.psm1',
    'tooling/harness/system-bootstrap-lifecycle/lifecycle.contract.json',
    'tooling/harness/system-bootstrap-lifecycle/lifecycle-state.schema.json',
    'tooling/harness/system-bootstrap-lifecycle/adapters.v1.json',
    'tooling/harness/operational/opencode-lsp-setup/native-system-bootstrap.contract.json',
    'scripts/Test-SystemBootstrapLifecycleContracts.ps1',
    'tests/test_system_bootstrap_lifecycle.py',
    'tests/test_opencode_native_system_bootstrap.py',
    'docs/harness/system-bootstrap-lifecycle.md',
    'docs/harness/opencode-native-system-bootstrap.md'
)

foreach ($relative in $required) {
    $path = Join-Path $RootPath $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing OpenCode native bootstrap component: $relative"
    }
}

$parseTargets = @(
    'tooling/harness/system-bootstrap-lifecycle/BootstrapLifecycle.psm1',
    'tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1',
    'tooling/profiles/windows/Setup-TechnicianAgentSwitchboard.ps1',
    'scripts/Test-SystemBootstrapLifecycleContracts.ps1',
    'scripts/Test-OpenCodeNativeSystemBootstrap.ps1'
)
foreach ($relative in $parseTargets) {
    $path = Join-Path $RootPath $relative
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $messages = ($errors | ForEach-Object { $_.Message }) -join '; '
        throw "PowerShell parse failed for ${relative}: $messages"
    }
}

$contractPath = Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/native-system-bootstrap.contract.json'
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json -ErrorAction Stop
if ($contract.contractId -ne 'agentswitchboard.opencode-native-system-bootstrap.v2') {
    throw 'Unexpected native OpenCode bootstrap contract id.'
}
if ($contract.owner -ne 'tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1') {
    throw 'Native OpenCode bootstrap owner drifted.'
}
if (@($contract.operations) -join ',' -ne 'Inspect,Apply,Remove') {
    throw 'Native OpenCode bootstrap must implement Inspect/Apply/Remove.'
}
if (@($contract.preflight.packageManagersAssumed).Count -ne 0) {
    throw 'Native OpenCode bootstrap must not assume a package manager.'
}
if (-not $contract.powershellSafety.implementationMustRunAsWholeScript -or $contract.powershellSafety.interactiveFragmentExecutionAllowed) {
    throw 'Native OpenCode bootstrap PowerShell whole-script safety contract drifted.'
}
foreach ($proofFlag in @(
        'inspectReportsOwnershipAndRemoveReadiness',
        'applyRequiresManagedLspReadback',
        'applyRequiresResolvedLspDebugConfig',
        'applyRequiresImmediateRemoveReadiness',
        'removeRequiresPreflightDriftCheckBeforeRollback',
        'removeRequiresRollbackVerification',
        'versionComparisonIgnoresLeadingV',
        'dirtyCheckoutStillAllowsBootstrapOpencode',
        'activeLspProofRequiresRuntimeObservation'
    )) {
    if (-not $contract.proof.$proofFlag) {
        throw "Native OpenCode bootstrap proof contract drifted: $proofFlag"
    }
}
if (-not $contract.lifecycle.removeRequiresOwnershipStateForPresentResources -or -not $contract.lifecycle.removeFailsClosedOnOwnedResourceDrift) {
    throw 'OpenCode lifecycle removal ownership contract drifted.'
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $python) { throw 'Python is required for the dependency-free native bootstrap contract.' }
& $python.Source -m unittest tests.test_system_bootstrap_lifecycle tests.test_opencode_native_system_bootstrap -v
if ($LASTEXITCODE -ne 0) { throw "OpenCode/system lifecycle Python contracts failed with exit code $LASTEXITCODE." }

& pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts/Test-SystemBootstrapLifecycleContracts.ps1') -RootPath $RootPath
if ($LASTEXITCODE -ne 0) { throw "System bootstrap lifecycle validator failed with exit code $LASTEXITCODE." }

if ($env:OS -eq 'Windows_NT') {
    $bootstrap = Join-Path $RootPath 'tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1'
    & $bootstrap -Mode Inspect
    if ($LASTEXITCODE -ne 0) { throw "Native OpenCode bootstrap Inspect failed with exit code $LASTEXITCODE." }
}

Write-Host '[PASS] OpenCode reversible native system bootstrap contract'
