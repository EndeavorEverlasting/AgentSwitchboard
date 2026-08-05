[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$repoRoot=Split-Path -Parent $PSScriptRoot
function Read-Json([string]$Relative){$path=Join-Path $repoRoot $Relative;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing harness component: $Relative"};Get-Content -LiteralPath $path -Raw | ConvertFrom-Json}
$manifest=Read-Json 'tooling\profiles\windows\harness\machine-profile\manifest.json'
if($manifest.schema -ne 'agentswitchboard.machine-profile-harness-manifest.v1'){throw 'Unexpected manifest schema.'}
if($manifest.productMutationAllowed -ne $false -or $manifest.secretsAllowed -ne $false -or $manifest.implicitHookInstallationAllowed -ne $false){throw 'Harness safety flags are invalid.'}
$keys=@('codebaseMap','machineProfileRegistry','environmentRoleRegistry','knownTrapsRegistry','artifactRegistry','workflowSpecs','schemaPath','skill','operatorDocumentation','operatorReportTemplate','statusReporter','statusCommand','validator','validatorCommand','pythonValidator','preCommitHook','ciWorkflow')
$required=@($keys | ForEach-Object {[string]$manifest.$_})
foreach($relative in $required){if(-not(Test-Path -LiteralPath (Join-Path $repoRoot $relative) -PathType Leaf)){throw "Missing registered file: $relative"}}
$roles=Read-Json ([string]$manifest.environmentRoleRegistry)
$expected=@('personal-windows-laptop','desktop-workstation','admin-box-1','admin-box-2')
$actual=@($roles.roles | ForEach-Object {[string]$_.roleId})
if((Compare-Object ($expected|Sort-Object) ($actual|Sort-Object)).Count){throw "Role mismatch: $($actual -join ', ')"}
foreach($role in $roles.roles){if($role.pathResolution.committedResolvedPathAllowed -ne $false){throw "Committed path allowed for $($role.roleId)"}}
$personal=@($roles.roles | Where-Object roleId -eq 'personal-windows-laptop')[0]
if($personal.pathResolution.workspacePattern -ne '%USERPROFILE%\Desktop\Dev'){throw 'Personal-laptop workspace contract mismatch.'}
$traps=Read-Json ([string]$manifest.knownTrapsRegistry)
foreach($id in @('shell-mismatch','errorlevel-clobber','downstream-after-failure','unsafe-powershell-null-replace','remembered-path','pull-over-local-patch','path-role-collapse')){if($id -notin @($traps.traps.id)){throw "Missing trap: $id"}}
$nullTrap=@($traps.traps | Where-Object id -eq 'unsafe-powershell-null-replace')[0]
if($nullTrap.safeExpression -ne '.Replace(([char]0).ToString(), [string]::Empty)'){throw 'Safe NUL expression missing.'}
$artifacts=Read-Json ([string]$manifest.artifactRegistry)
foreach($artifact in $artifacts.generatedArtifacts){if($artifact.tracked -ne $false){throw "Generated artifact tracked: $($artifact.id)"}}
$workflows=Read-Json ([string]$manifest.workflowSpecs)
$workflowIds=@($workflows.workflows | ForEach-Object {$_.workflowId})
foreach($id in @('machine-profile-task-intake','machine-profile-validation','machine-profile-failure-recovery','machine-profile-handoff')){if($id -notin $workflowIds){throw "Missing workflow: $id"}}
$text=@($required | ForEach-Object {Get-Content -LiteralPath (Join-Path $repoRoot $_) -Raw}) -join "`n"
foreach($literal in @('CheeksMcClappeth','pa_rperez26','OneDrive - Northwell Health')){if($text -match [regex]::Escape($literal)){throw "Real machine literal committed: $literal"}}
$git=Get-Command git -ErrorAction SilentlyContinue
if($git){foreach($relative in $required){& $git.Source -C $repoRoot ls-files --error-unmatch -- $relative *> $null;if($LASTEXITCODE -ne 0){throw "Harness file is not tracked: $relative"}}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('agentswitchboard-machine-profile-harness-'+[guid]::NewGuid().ToString('N'))
try{& (Join-Path $repoRoot 'tooling\profiles\windows\Get-MachineProfileHarnessStatus.ps1') -Emit Json -OutputRoot $temp | Out-Null;if($LASTEXITCODE -ne 0){throw "Status reporter failed: $LASTEXITCODE"};foreach($name in @('machine-profile-harness-status.json','machine-profile-harness-status.md')){if(-not(Test-Path -LiteralPath (Join-Path $temp $name) -PathType Leaf)){throw "Missing status artifact: $name"}}}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host '[PASS] Machine-profile operational harness completeness passed.'
