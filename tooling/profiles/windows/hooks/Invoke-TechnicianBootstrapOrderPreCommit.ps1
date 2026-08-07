[CmdletBinding()]
param([string]$RootPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $rootLines = @(& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $rootLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$rootLines[0])) { throw 'Unable to resolve repository root.' }
    $RootPath = ([string]$rootLines[0]).Trim()
}
$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path

$staged = @(& git -C $RootPath diff --cached --name-only --diff-filter=ACMR 2>$null)
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect staged files.' }
$relevantPrefixes = @(
    'SKILLS.md',
    'TRIGGERS.md',
    'Technician-AgentSwitchboard-Ready.cmd',
    'Test-TechnicianBootstrapOrderHarness.cmd',
    'tooling/profiles/windows/Invoke-TechnicianBootstrapPrerequisites.ps1',
    'tooling/profiles/windows/Invoke-TechnicianAgentSwitchboardReady.ps1',
    'tooling/profiles/windows/harness/technician-ready/',
    'tooling/profiles/windows/Get-TechnicianBootstrapOrderHarnessStatus.ps1',
    'tooling/profiles/windows/hooks/Invoke-TechnicianBootstrapOrderPreCommit.ps1',
    'scripts/Test-TechnicianBootstrapOrder',
    'tests/test_technician_bootstrap_order',
    '.ai/skills/technician-bootstrap-order-validation/',
    'docs/harness/technician-bootstrap-order',
    '.github/workflows/technician-bootstrap-order.yml'
)
$relevant = @($staged | Where-Object {
    $path = [string]$_
    @($relevantPrefixes | Where-Object { $path.StartsWith([string]$_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
})
if ($relevant.Count -eq 0) {
    Write-Host 'SKIP: No staged technician bootstrap-order paths.' -ForegroundColor Yellow
    exit 0
}

Push-Location -LiteralPath $RootPath
try {
    & python -m unittest tests.test_technician_bootstrap_order_harness -v
    if ($LASTEXITCODE -ne 0) { throw "Harness Python contracts failed with exit code $LASTEXITCODE" }
    & python -m unittest tests.test_technician_bootstrap_order -v
    if ($LASTEXITCODE -ne 0) { throw "Bootstrap-order Python contracts failed with exit code $LASTEXITCODE" }
    & pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts/Test-TechnicianBootstrapOrderHarnessCompleteness.ps1') -RootPath $RootPath -NoWrite
    if ($LASTEXITCODE -ne 0) { throw "Harness completeness failed with exit code $LASTEXITCODE" }
    & pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts/Test-TechnicianBootstrapOrder.ps1') -RootPath $RootPath
    if ($LASTEXITCODE -ne 0) { throw "Bootstrap-order validator failed with exit code $LASTEXITCODE" }
    & python -m unittest tests.test_technician_agentswitchboard_ready -v
    if ($LASTEXITCODE -ne 0) { throw "Technician readiness contracts failed with exit code $LASTEXITCODE" }
    & pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'scripts/Test-AgentDocumentationContract.ps1') -RootPath $RootPath
    if ($LASTEXITCODE -ne 0) { throw "Agent documentation contract failed with exit code $LASTEXITCODE" }
    & pwsh -NoLogo -NoProfile -File (Join-Path $RootPath 'tooling/profiles/windows/Get-TechnicianBootstrapOrderHarnessStatus.ps1') -RootPath $RootPath -NoWrite
    if ($LASTEXITCODE -ne 0) { throw "Harness component-status readback failed with exit code $LASTEXITCODE" }
    & git -C $RootPath diff --cached --check
    if ($LASTEXITCODE -ne 0) { throw "Staged diff hygiene failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}
Write-Host 'PASS: staged technician bootstrap-order validation order passed.' -ForegroundColor Green
exit 0
