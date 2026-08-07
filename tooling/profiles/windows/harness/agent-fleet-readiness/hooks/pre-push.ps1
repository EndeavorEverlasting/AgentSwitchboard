[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..\..\..\..')).Path
$validator = Join-Path $repoRoot 'scripts\Test-AgentFleetReadinessHarnessCompleteness.ps1'
$pythonTest = Join-Path $repoRoot 'tests\test_agent_fleet_readiness_harness.py'
$productContract = Join-Path $repoRoot 'tooling\gnhf\Test-GnhfFleetContracts.ps1'

foreach ($path in @($validator,$pythonTest,$productContract)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required agent fleet readiness validation surface is missing: $path"
    }
}

& pwsh -NoLogo -NoProfile -File $validator
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& python $pythonTest
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& pwsh -NoLogo -NoProfile -File $productContract
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'PASS: agent fleet readiness pre-push checks' -ForegroundColor Green
exit 0
