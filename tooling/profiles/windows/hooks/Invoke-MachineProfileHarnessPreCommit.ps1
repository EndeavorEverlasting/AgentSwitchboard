[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
& (Join-Path $repoRoot 'scripts\Test-MachineProfileHarnessCompleteness.ps1')
if($LASTEXITCODE -ne 0){throw "Machine-profile harness completeness failed: $LASTEXITCODE"}
$git=Get-Command git -ErrorAction Stop
& $git.Source -C $repoRoot diff --cached --check
if($LASTEXITCODE -ne 0){throw 'Staged diff hygiene failed.'}
$forbidden=@('machine-profile.json','machine-profile.env.cmd','machine-profile.env.ps1','machine-profile-harness-status.json','machine-profile-harness-status.md')
$violations=@(& $git.Source -C $repoRoot diff --cached --name-only | Where-Object {$forbidden -contains (Split-Path -Leaf $_)})
if($violations.Count){throw "Generated machine-local evidence must not be committed: $($violations -join ', ')"}
Write-Host '[PASS] Machine-profile harness pre-commit checks passed.'
