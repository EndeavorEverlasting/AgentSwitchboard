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
    'tooling/harness/operational/opencode-lsp-setup/native-system-bootstrap.contract.json',
    'tests/test_opencode_native_system_bootstrap.py',
    'docs/harness/opencode-native-system-bootstrap.md'
)

foreach ($relative in $required) {
    $path = Join-Path $RootPath $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing OpenCode native bootstrap component: $relative"
    }
}

$parseTargets = @(
    'tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1',
    'tooling/profiles/windows/Setup-TechnicianAgentSwitchboard.ps1',
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
if ($contract.contractId -ne 'agentswitchboard.opencode-native-system-bootstrap.v1') {
    throw 'Unexpected native OpenCode bootstrap contract id.'
}
if ($contract.owner -ne 'tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1') {
    throw 'Native OpenCode bootstrap owner drifted.'
}
if (@($contract.preflight.packageManagersAssumed).Count -ne 0) {
    throw 'Native OpenCode bootstrap must not assume a package manager.'
}
if (-not $contract.powershellSafety.implementationMustRunAsWholeScript -or $contract.powershellSafety.interactiveFragmentExecutionAllowed) {
    throw 'Native OpenCode bootstrap PowerShell whole-script safety contract drifted.'
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $python) { throw 'Python is required for the dependency-free native bootstrap contract.' }
& $python.Source -m unittest tests.test_opencode_native_system_bootstrap -v
if ($LASTEXITCODE -ne 0) { throw "Native OpenCode bootstrap Python contract failed with exit code $LASTEXITCODE." }

if ($env:OS -eq 'Windows_NT') {
    $bootstrap = Join-Path $RootPath 'tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1'
    & $bootstrap -Mode Inspect
    if ($LASTEXITCODE -ne 0) { throw "Native OpenCode bootstrap Inspect failed with exit code $LASTEXITCODE." }
}

Write-Host '[PASS] OpenCode native system bootstrap contract'
