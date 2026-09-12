[CmdletBinding()]
param([string]$RootPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RootPath)) { $RootPath = Split-Path -Parent $PSScriptRoot }
$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path

$modulePath = Join-Path $RootPath 'tooling/harness/system-bootstrap-lifecycle/BootstrapLifecycle.psm1'
$contractPath = Join-Path $RootPath 'tooling/harness/system-bootstrap-lifecycle/lifecycle.contract.json'
$schemaPath = Join-Path $RootPath 'tooling/harness/system-bootstrap-lifecycle/lifecycle-state.schema.json'
$registryPath = Join-Path $RootPath 'tooling/harness/system-bootstrap-lifecycle/adapters.v1.json'
$openCodeOwner = Join-Path $RootPath 'tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1'
$unbootstrap = Join-Path $RootPath 'Unbootstrap-OpenCode-SystemWide.cmd'

foreach ($path in @($modulePath,$contractPath,$schemaPath,$registryPath,$openCodeOwner,$unbootstrap)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing system bootstrap lifecycle component: $path" }
}

foreach ($relative in @(
    'tooling/harness/system-bootstrap-lifecycle/BootstrapLifecycle.psm1',
    'scripts/Test-SystemBootstrapLifecycleContracts.ps1',
    'tooling/profiles/windows/Install-AgentSwitchboardOpenCode.ps1'
)) {
    $path = Join-Path $RootPath $relative
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if ($errors.Count -gt 0) {
        throw "PowerShell parse failed for ${relative}: $(($errors | ForEach-Object Message) -join '; ')"
    }
}

$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json -ErrorAction Stop
$schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json -ErrorAction Stop
$registry = Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json -ErrorAction Stop

if ($contract.contractId -ne 'agentswitchboard.system-bootstrap-lifecycle.v1') { throw 'Unexpected lifecycle contract id.' }
if (@($contract.operations) -join ',' -ne 'Inspect,Apply,Remove') { throw 'Lifecycle contract must own Inspect/Apply/Remove.' }
if ($schema.'$id' -ne 'agentswitchboard.system-bootstrap-state.v1') { throw 'Unexpected lifecycle state schema id.' }
if ($registry.schema -ne 'agentswitchboard.system-bootstrap-adapter-registry.v1') { throw 'Unexpected lifecycle adapter registry schema.' }

$openCode = @($registry.adapters | Where-Object adapterId -eq 'opencode')
if ($openCode.Count -ne 1) { throw 'Exactly one OpenCode lifecycle adapter registration is required.' }
if ($openCode[0].status -ne 'reference-implementation') { throw 'OpenCode must remain the lifecycle reference implementation until parity adapters are proven.' }
if (@($openCode[0].operations) -join ',' -ne 'Inspect,Apply,Remove') { throw 'OpenCode registry entry does not declare lifecycle parity.' }
if (-not $openCode[0].removeRequiresOwnershipState -or -not $openCode[0].removePreservesUnrelatedSharedState) { throw 'OpenCode removal ownership contract drifted.' }

Import-Module $modulePath -Force -ErrorAction Stop

$pathSample = 'C:\Windows;C:\Tools'
$added = Add-ASBPathEntry -PathValue $pathSample -Entry 'C:\Program Files\OpenCode' -Position Append
if (-not $added.Changed -or $added.Preexisting) { throw 'PATH add contract failed.' }
if (-not (Test-ASBPathContainsEntry -PathValue $added.Value -Entry 'C:\Program Files\OpenCode\')) { throw 'PATH normalized contains contract failed.' }
$secondAdd = Add-ASBPathEntry -PathValue $added.Value -Entry 'c:\program files\opencode' -Position Append
if ($secondAdd.Changed -or -not $secondAdd.Preexisting) { throw 'PATH add idempotence contract failed.' }
$removed = Remove-ASBPathEntry -PathValue $added.Value -Entry 'C:\Program Files\OpenCode'
if (-not $removed.Changed -or (Test-ASBPathContainsEntry -PathValue $removed.Value -Entry 'C:\Program Files\OpenCode')) { throw 'PATH exact removal contract failed.' }
if ($removed.Value -ne $pathSample) { throw 'PATH removal changed unrelated entries.' }

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('ASB-lifecycle-test-' + [guid]::NewGuid().ToString('N'))
try {
    $fakeProgramData = Join-Path $tempRoot 'ProgramData'
    $statePath = Get-ASBLifecycleStatePath -AdapterId 'test-adapter' -ProgramDataRoot $fakeProgramData
    $state = [ordered]@{
        schema = 'agentswitchboard.system-bootstrap-state.v1'
        adapterId = 'test-adapter'
        installId = 'test-install'
        status = 'installed'
        createdAt = [DateTime]::UtcNow.ToString('o')
        updatedAt = [DateTime]::UtcNow.ToString('o')
        resources = [ordered]@{ demo = [ordered]@{ changedByAsb = $true } }
    }
    Write-ASBLifecycleStateAtomic -StatePath $statePath -State $state
    $readback = Read-ASBLifecycleState -StatePath $statePath
    if ($readback.adapterId -ne 'test-adapter' -or $readback.status -ne 'installed') { throw 'Atomic lifecycle state readback failed.' }
    $lifecycleRoot = Get-ASBLifecycleRoot -AdapterId 'test-adapter' -ProgramDataRoot $fakeProgramData
    $historyPath = Archive-ASBLifecycleState -LifecycleRoot $lifecycleRoot -State $readback
    if (-not (Test-Path -LiteralPath $historyPath -PathType Leaf)) { throw 'Lifecycle state archive contract failed.' }

    $hashFile = Join-Path $tempRoot 'hash.txt'
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $hashFile) -Force
    Set-Content -LiteralPath $hashFile -Value 'bootstrap-lifecycle' -NoNewline
    $hash = Get-ASBFileSha256 -Path $hashFile
    if ($hash -notmatch '^[0-9a-f]{64}$') { throw 'Lifecycle SHA-256 helper failed.' }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$ownerText = Get-Content -LiteralPath $openCodeOwner -Raw
foreach ($token in @(
    "[ValidateSet('Inspect','Apply','Remove')]",
    'Get-ASBLifecycleStatePath',
    'OPENCODE_REMOVE_OWNERSHIP_UNPROVEN',
    'OPENCODE_REMOVE_DRIFT_DETECTED',
    'OPENCODE_REMOVE_BINARY_RESTORE_FAILED',
    'OPENCODE_REMOVE_CONFIG_VERIFY_FAILED',
    'OPENCODE_POST_APPLY_REMOVE_CONTRACT_FAILED'
)) {
    if (-not $ownerText.Contains($token)) { throw "OpenCode lifecycle owner is missing required token: $token" }
}

$unbootstrapText = Get-Content -LiteralPath $unbootstrap -Raw
if (-not $unbootstrapText.Contains('-Mode Remove')) { throw 'OpenCode unbootstrap entrypoint does not invoke Remove.' }
if ($unbootstrapText.Contains('git reset') -or $unbootstrapText.Contains('git clean')) { throw 'OpenCode unbootstrap entrypoint must not rewrite Git state.' }

Write-Host '[PASS] AgentSwitchboard system bootstrap lifecycle contracts'
