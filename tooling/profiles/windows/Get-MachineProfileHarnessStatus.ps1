[CmdletBinding()]
param([ValidateSet('Human','Json')][string]$Emit='Human',[string]$OutputRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$manifestPath=Join-Path $repoRoot 'tooling\profiles\windows\harness\machine-profile\manifest.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$keys=@('codebaseMap','machineProfileRegistry','environmentRoleRegistry','knownTrapsRegistry','artifactRegistry','workflowSpecs','schemaPath','skill','operatorDocumentation','operatorReportTemplate','statusReporter','statusCommand','validator','validatorCommand','pythonValidator','preCommitHook','ciWorkflow')
$required=@($keys | ForEach-Object {[string]$manifest.$_})
$missing=@($required | Where-Object {-not (Test-Path -LiteralPath (Join-Path $repoRoot $_) -PathType Leaf)})
$trackedMissing=@()
$git=Get-Command git -ErrorAction SilentlyContinue
if($git){foreach($path in $required){& $git.Source -C $repoRoot ls-files --error-unmatch -- $path *> $null;if($LASTEXITCODE -ne 0){$trackedMissing+=$path}}}
$roles=Get-Content -LiteralPath (Join-Path $repoRoot ([string]$manifest.environmentRoleRegistry)) -Raw | ConvertFrom-Json
$roleIds=@($roles.roles | ForEach-Object {$_.roleId})
$status=if($missing.Count -eq 0 -and $trackedMissing.Count -eq 0){'ready'}else{'incomplete'}
$now=Get-Date
$runId='{0}-{1}' -f $now.ToUniversalTime().ToString('yyyyMMddTHHmmssZ'),([guid]::NewGuid().ToString('N').Substring(0,8))
if([string]::IsNullOrWhiteSpace($OutputRoot)){$OutputRoot=Join-Path ([IO.Path]::GetTempPath()) "AgentSwitchboard\machine-profile-harness\$runId"}
$null=New-Item -ItemType Directory -Path $OutputRoot -Force
$result=[ordered]@{schema='agentswitchboard.machine-profile-harness-status.v1';generatedAt=$now.ToUniversalTime().ToString('o');status=$status;requiredCount=$required.Count;presentCount=$required.Count-$missing.Count;missing=$missing;trackedMissing=$trackedMissing;environmentRoles=$roleIds;proofCeiling=[string]$manifest.proofCeiling;nextCommand='Test-MachineProfileHarness.cmd'}
$jsonPath=Join-Path $OutputRoot 'machine-profile-harness-status.json'
$mdPath=Join-Path $OutputRoot 'machine-profile-harness-status.md'
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM
@('# Windows Machine-Profile Harness Status','',"- Status: **$status**","- Components: $($result.presentCount)/$($result.requiredCount)","- Roles: $($roleIds -join ', ')","- Missing: $(if($missing.Count){$missing -join ', '}else{'none'})","- Untracked: $(if($trackedMissing.Count){$trackedMissing -join ', '}else{'none'})",'','## Proof ceiling','',[string]$manifest.proofCeiling,'','## Exact next command','','```cmd','Test-MachineProfileHarness.cmd','```') | Set-Content -LiteralPath $mdPath -Encoding utf8NoBOM
if($Emit -eq 'Json'){$result | ConvertTo-Json -Depth 8}else{Write-Host "Machine-profile harness: $status";Write-Host "Components: $($result.presentCount)/$($result.requiredCount)";Write-Host "Roles: $($roleIds -join ', ')";Write-Host "JSON: $jsonPath";Write-Host "Report: $mdPath";Write-Host 'NEXT COMMAND: Test-MachineProfileHarness.cmd'}
if($status -ne 'ready'){exit 1}
exit 0
