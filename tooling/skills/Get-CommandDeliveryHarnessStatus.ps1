[CmdletBinding()]
param([string]$RootPath,[string]$OutputDirectory,[switch]$NoWrite)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$git = if ($env:OS -eq 'Windows_NT') { 'git.exe' } else { 'git' }
if ([string]::IsNullOrWhiteSpace($RootPath)) { $RootPath = [string]((& $git -C $PSScriptRoot rev-parse --show-toplevel 2>$null | Select-Object -First 1)) }
if ([string]::IsNullOrWhiteSpace($RootPath)) { throw 'Unable to resolve repository root.' }
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$manifest = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/skills/harness/command-delivery/manifest.json') -Raw | ConvertFrom-Json
$components = @($manifest.components | ForEach-Object { [pscustomobject]@{path=[string]$_;exists=(Test-Path -LiteralPath (Join-Path $RootPath ([string]$_)) -PathType Leaf)} })
$missing = @($components | Where-Object { -not $_.exists })
$branch = [string](& $git -C $RootPath branch --show-current 2>$null)
$head = [string](& $git -C $RootPath rev-parse HEAD 2>$null)
$status = if ($missing.Count -eq 0) { 'contract-ready' } else { 'incomplete' }
$working = @('Codebase map, workflows, registries, validators, hooks, skills, reports, and handoff are tracked.','Routing and PowerShell boundary fixtures are deterministic.','Windows exact-entrypoint proof uses a detached path containing spaces.','Generated evidence is local and untracked.')
$gaps = @($missing | ForEach-Object { 'Missing tracked component: ' + $_.path })
$gaps += @('Contract readiness does not prove arbitrary operator or target-runtime behavior.','Windows outer-entrypoint proof still requires a Windows execution.','Merge, deployment, provider, secret, and live-target authority remain out of scope.')
$map = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/skills/harness/command-delivery/codebase-map.json') -Raw | ConvertFrom-Json
$traps = @($map.knownTraps | ForEach-Object { [string]$_ })
$next = 'pwsh -NoLogo -NoProfile -File scripts/Test-CommandDeliveryHarnessCompleteness.ps1'
$result = [ordered]@{schema='agentswitchboard.command-delivery-harness-status.v1';status=$status;repository='EndeavorEverlasting/AgentSwitchboard';branch=$branch;head=$head;components=$components;missing=@($missing|ForEach-Object{$_.path});working=$working;gaps=$gaps;knownTraps=$traps;proofCeiling=[string]$manifest.proofCeiling;nextCommand=$next}
Write-Host 'COMMAND DELIVERY HARNESS' -ForegroundColor Cyan
Write-Host ("Status: {0}; Branch: {1}; HEAD: {2}; Components: {3}/{4}" -f $status,$branch,$head,($components.Count-$missing.Count),$components.Count)
$working | ForEach-Object { Write-Host ('- WORKING: '+$_) }; $gaps | ForEach-Object { Write-Host ('- GAP: '+$_) }; Write-Host ('Next: '+$next)
if (-not $NoWrite) {
  if ([string]::IsNullOrWhiteSpace($OutputDirectory)) { $base=if($env:LOCALAPPDATA){$env:LOCALAPPDATA}else{[IO.Path]::GetTempPath()}; $OutputDirectory=Join-Path $base 'AgentSwitchboard/command-delivery-harness' }
  $null=New-Item -ItemType Directory -Path $OutputDirectory -Force
  $json=Join-Path $OutputDirectory 'command-delivery-harness-status.json'; $md=Join-Path $OutputDirectory 'command-delivery-harness-status.md'; $handoffPath=Join-Path $OutputDirectory 'command-delivery-handoff.json'
  $result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $json -Encoding utf8
  $rendered=Get-Content -LiteralPath (Join-Path $RootPath 'tooling/skills/harness/command-delivery/reports/operator-status.template.md') -Raw
  $values=[ordered]@{'{{STATUS}}'=$status;'{{REPOSITORY}}'='EndeavorEverlasting/AgentSwitchboard';'{{BRANCH}}'=$branch;'{{HEAD}}'=$head;'{{PRESENT}}'=[string]($components.Count-$missing.Count);'{{TOTAL}}'=[string]$components.Count;'{{WORKING}}'=(($working|ForEach-Object{'- '+$_})-join [Environment]::NewLine);'{{GAPS}}'=(($gaps|ForEach-Object{'- '+$_})-join [Environment]::NewLine);'{{TRAPS}}'=(($traps|ForEach-Object{'- '+$_})-join [Environment]::NewLine);'{{PROOF_CEILING}}'=[string]$manifest.proofCeiling;'{{NEXT_COMMAND}}'=$next}
  foreach($key in $values.Keys){$rendered=$rendered.Replace($key,[string]$values[$key])}; if($rendered -match '\{\{[A-Z_]+\}\}'){throw 'Unresolved report placeholder.'}; $rendered|Set-Content -LiteralPath $md -Encoding utf8
  $handoff=[ordered]@{schema='agentswitchboard.command-delivery-handoff.v1';repository='EndeavorEverlasting/AgentSwitchboard';branch=$branch;head=$head;status=$status;missing=$result.missing;artifacts=@($json,$md);proofCeiling=[string]$manifest.proofCeiling;nextCommand=$next;receiverMustRefresh=@('AGENTS.md','codebase map','manifest','Git status','active PR','hosted checks')}
  $handoff|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $handoffPath -Encoding utf8
  Write-Host ('JSON: '+$json); Write-Host ('Report: '+$md); Write-Host ('Handoff: '+$handoffPath)
}
if($missing.Count -gt 0){exit 1}; exit 0
