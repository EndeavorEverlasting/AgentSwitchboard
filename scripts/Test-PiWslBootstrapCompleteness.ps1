[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$failures = [System.Collections.Generic.List[string]]::new()

$required = @(
    'Bootstrap-Pi-WSL.cmd',
    'Pull-And-Run-AgentSwitchboard.cmd',
    'tooling/profiles/windows/Setup-TechnicianAgentSwitchboard.ps1',
    'tooling/pi/Install-AgentSwitchboardPiWsl.ps1',
    'tooling/pi/harness/wsl-user-bootstrap.contract.json',
    'tests/test_pi_wsl_bootstrap.py',
    'docs/harness/pi-wsl-workstation-bootstrap.md',
    '.github/workflows/pi-harness-contract.yml'
)

foreach ($relative in $required) {
    $path = Join-Path $RootPath $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $failures.Add("missing:$relative")
        continue
    }
    $null = & git -C $RootPath ls-files --error-unmatch -- $relative 2>$null
    if ($LASTEXITCODE -ne 0) { $failures.Add("untracked:$relative") }
}

try {
    $contractPath = Join-Path $RootPath 'tooling/pi/harness/wsl-user-bootstrap.contract.json'
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    if ($contract.bootstrapId -ne 'pi-wsl-user-bootstrap') { $failures.Add('contract:bootstrapId') }
    if ($contract.entrypoint -ne 'Bootstrap-Pi-WSL.cmd') { $failures.Add('contract:entrypoint') }
    if ($contract.dispatcherMode -ne 'bootstrap-pi-wsl') { $failures.Add('contract:dispatcherMode') }
    if ($contract.installer -ne 'tooling/pi/Install-AgentSwitchboardPiWsl.ps1') { $failures.Add('contract:installer') }
    if ($contract.target.wslDistribution -ne 'Ubuntu') { $failures.Add('contract:wslDistribution') }
    if ($contract.target.nativeWindowsPiUnchanged -ne $true) { $failures.Add('contract:nativeWindowsPiUnchanged') }
    if ($contract.boundedMutation.credentialMutation -ne $false) { $failures.Add('contract:credentialMutation') }
}
catch {
    $failures.Add("contract:parse:$($_.Exception.Message)")
}

foreach ($relative in @(
    'tooling/pi/Install-AgentSwitchboardPiWsl.ps1',
    'tooling/profiles/windows/Setup-TechnicianAgentSwitchboard.ps1'
)) {
    $tokens = $null
    $parseErrors = $null
    $path = Join-Path $RootPath $relative
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) {
        $failures.Add("parse:${relative}:$($parseError.Message)")
    }
}

$entry = Get-Content -LiteralPath (Join-Path $RootPath 'Bootstrap-Pi-WSL.cmd') -Raw
$dispatcher = Get-Content -LiteralPath (Join-Path $RootPath 'Pull-And-Run-AgentSwitchboard.cmd') -Raw
$setup = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/profiles/windows/Setup-TechnicianAgentSwitchboard.ps1') -Raw
$workflow = Get-Content -LiteralPath (Join-Path $RootPath '.github/workflows/pi-harness-contract.yml') -Raw

if (-not $entry.Contains('bootstrap-pi-wsl')) { $failures.Add('entry:mode') }
if (-not $entry.Contains('Pull-And-Run-AgentSwitchboard.cmd')) { $failures.Add('entry:dispatcher') }
if (-not $dispatcher.Contains('bootstrap-pi-wsl')) { $failures.Add('dispatcher:mode') }
if (-not $setup.Contains('Install-AgentSwitchboardPiWsl.ps1')) { $failures.Add('setup:installer') }
if (-not $workflow.Contains('tests/test_pi_wsl_bootstrap.py')) { $failures.Add('workflow:test-path') }
if (-not $workflow.Contains('Bootstrap-Pi-WSL.cmd')) { $failures.Add('workflow:entry-path') }
if (-not $workflow.Contains('Test-PiWslBootstrapCompleteness.ps1')) { $failures.Add('workflow:completeness') }

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Host '[PASS] PI_WSL_BOOTSTRAP_COMPLETENESS'
Write-Host 'PROOF_CEILING=tracked contract completeness and parser validation only; no physical WSL install or provider authentication proven'
exit 0
