[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..')).Path
& pwsh -NoLogo -NoProfile -File (Join-Path $root 'scripts\Test-ExecutionActorRoutingHarness.ps1')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& python (Join-Path $root 'tests\test_execution_actor_routing_harness.py')
exit $LASTEXITCODE
