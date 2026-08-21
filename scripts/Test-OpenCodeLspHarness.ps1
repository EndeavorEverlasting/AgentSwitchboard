[CmdletBinding()]
param([string]$RootPath)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RootPath)) { $RootPath = Split-Path -Parent $PSScriptRoot }
$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path
$required = @(
 'SKILLS.md','TRIGGERS.md','tooling/harness/operational/workflow-registry.json',
 'tooling/harness/operational/opencode-lsp-setup/manifest.json',
 'tooling/harness/operational/opencode-lsp-setup/codebase-map.json',
 'tooling/harness/operational/opencode-lsp-setup/workflows.json',
 'tooling/harness/operational/opencode-lsp-setup/artifact-registry.json',
 'tooling/harness/operational/opencode-lsp-setup/operator-report.template.md',
 'tooling/harness/operational/opencode-lsp-setup/Recover-AgentSwitchboardCheckout.ps1',
 'tooling/harness/operational/opencode-lsp-setup/Recover-OpenCodeRuntime.ps1',
 'tooling/harness/operational/opencode-lsp-setup/Resolve-AgentSwitchboardCheckout.ps1',
 'tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1',
 'tooling/harness/operational/opencode-lsp-setup/hooks/Invoke-OpenCodeLspPreCommit.ps1',
 'tooling/harness/operational/opencode-lsp-setup/hooks/Invoke-OpenCodeLspPrePush.ps1',
 '.ai/skills/opencode-lsp-workstation-setup/SKILL.md',
 'docs/harness/opencode-lsp-workstation-setup.md',
 'tests/test_opencode_lsp_harness.py','tests/test_opencode_runtime_recovery.py','scripts/Test-OpenCodeLspHarness.ps1','Test-OpenCodeLspHarness.cmd','.github/workflows/opencode-lsp-harness.yml'
)
$failures = [Collections.Generic.List[string]]::new()
foreach ($p in $required) { if (-not (Test-Path -LiteralPath (Join-Path $RootPath $p) -PathType Leaf)) { [void]$failures.Add("missing:$p") } }
foreach ($p in @('manifest.json','codebase-map.json','workflows.json','artifact-registry.json','workflows/failure-recovery.workflow.json')) {
 try { $null = Get-Content -LiteralPath (Join-Path $RootPath "tooling/harness/operational/opencode-lsp-setup/$p") -Raw | ConvertFrom-Json }
 catch { [void]$failures.Add("invalid-json:$p") }
}
foreach ($p in @('tooling/harness/operational/opencode-lsp-setup/Recover-AgentSwitchboardCheckout.ps1','tooling/harness/operational/opencode-lsp-setup/Recover-OpenCodeRuntime.ps1','tooling/harness/operational/opencode-lsp-setup/Resolve-AgentSwitchboardCheckout.ps1','tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1','tooling/harness/operational/opencode-lsp-setup/hooks/Invoke-OpenCodeLspPreCommit.ps1','tooling/harness/operational/opencode-lsp-setup/hooks/Invoke-OpenCodeLspPrePush.ps1','scripts/Test-OpenCodeLspHarness.ps1')) {
 $tokens=$null; $errors=$null; [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $RootPath $p),[ref]$tokens,[ref]$errors)
 if ($errors.Count -gt 0) { [void]$failures.Add("powershell-parse:${p}:$($errors[0].Message)") }
}
$genericManifest = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/manifest.json') -Raw
if (-not $genericManifest.Contains('opencode-lsp-setup/manifest.json')) { [void]$failures.Add('generic-operational-manifest-route-missing') }
$skills = Get-Content -LiteralPath (Join-Path $RootPath 'SKILLS.md') -Raw
if (-not $skills.Contains('opencode-lsp-workstation-setup')) { [void]$failures.Add('canonical-skill-route-missing') }
$triggers = Get-Content -LiteralPath (Join-Path $RootPath 'TRIGGERS.md') -Raw
if (-not ($triggers.Contains('opencode.lsp-workstation-setup') -and $triggers.Contains('opencode-lsp-workstation-setup'))) { [void]$failures.Add('canonical-trigger-route-missing') }
$workflowRegistry = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/workflow-registry.json') -Raw
if (-not ($workflowRegistry.Contains('opencode-lsp-workstation-setup/SKILL.md') -and $workflowRegistry.Contains('opencode-lsp-setup/'))) { [void]$failures.Add('operational-specialized-route-missing') }
$recoveryRouter = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/Recover-AgentSwitchboardCheckout.ps1') -Raw
$recoveryRouterLower = $recoveryRouter.ToLowerInvariant()
foreach ($token in @('git ls-remote --symref','refs/heads/$defaultbranch','resolve-agentswitchboardcheckout.ps1','-expectedbranch $defaultbranch','-expectedhead $expectedhead')) { if (-not $recoveryRouterLower.Contains($token)) { [void]$failures.Add("recovery-router-contract:$token") } }
foreach ($forbidden in @('git reset','git clean','git stash','push --force','remove-item')) { if ($recoveryRouterLower.Contains($forbidden)) { [void]$failures.Add("recovery-router-forbidden-token:$forbidden") } }
$runtimeRecoveryRouter = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/Recover-OpenCodeRuntime.ps1') -Raw
$runtimeRecoveryRouterLower = $runtimeRecoveryRouter.ToLowerInvariant()
foreach ($token in @('installtimeoutseconds = 180','https://opencode.ai/install','agentswitchboard\bin\opencode.cmd','invoke-boundedprocess','timeout --signal=term','opencode-command-discovery','opencode-version-probe','existing-runtime-version-failed','existing-runtime-version-timeout','opencode-install','post-install-command-discovery','post-install-version-probe','opencode-runtime-recovery.json','opencode-runtime-recovery.md','write-recoveryevidence','laststdoutpresent','laststderrpresent','secretorenvironmentdumppersisted = $false','inspect-handoff','opencode_inspect_handoff_timeout')) { if (-not $runtimeRecoveryRouterLower.Contains($token)) { [void]$failures.Add("runtime-recovery-router-contract:$token") } }
foreach ($forbidden in @('repair-technician-command-shims.cmd','agent_switchboard_no_pause','setup-technicianagentswitchboard.ps1','antigravity.google','git reset','git clean','git stash','push --force','remove-item')) { if ($runtimeRecoveryRouterLower.Contains($forbidden)) { [void]$failures.Add("runtime-recovery-router-forbidden-token:$forbidden") } }
$installStart = $runtimeRecoveryRouterLower.IndexOf("`$installscript = @'")
$installEnd = $runtimeRecoveryRouterLower.IndexOf('$installresult = invoke-wslbash -script $installscript')
if ($installStart -lt 0 -or $installEnd -le $installStart) { [void]$failures.Add('runtime-recovery-install-block-missing') }
elseif ($runtimeRecoveryRouterLower.Substring($installStart, $installEnd - $installStart).Contains('command -v opencode')) { [void]$failures.Add('runtime-recovery-unhealthy-install-skipped-by-command-presence') }
$resolver = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/Resolve-AgentSwitchboardCheckout.ps1') -Raw
$resolverLower = $resolver.ToLowerInvariant()
foreach ($token in @('preferredpath','expectedbranch','expectedhead','canonicaloriginpattern','bounded-existing-checkout','created-isolated-clone','worktree add --detach','remote_head_mismatch','opencode-lsp-checkout-resolution.json')) { if (-not $resolverLower.Contains($token)) { [void]$failures.Add("resolver-contract:$token") } }
foreach ($forbidden in @('git reset','git clean','git stash','push --force','remove-item')) { if ($resolverLower.Contains($forbidden)) { [void]$failures.Add("resolver-forbidden-token:$forbidden") } }
$runner = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1') -Raw
$runnerLower = $runner.ToLowerInvariant()
foreach ($token in @('opencode_config_content','opencode/nemotron-3-ultra-free','opencode_v2_lsp_unavailable','configurationdirectory','configuration_directory_already_owned','launcher_mismatch','canonicaloriginpattern','modelprovider','localappdata','lsp=$true','free trial','wrong_repository','recover-agentswitchboardcheckout.ps1','recover-opencoderuntime.ps1','-preferredpath','git_identity_output_empty','$originlines = @(invoke-gitlines','$origin = ([string]$originlines[0]).trim()','$headlines = @(invoke-gitlines','$head = ([string]$headlines[0]).trim()','agentswitchboard\bin\opencode.cmd',"elseif (`$failurecode -eq 'opencode_not_found' -and `$reporesolved)",'probetimeoutseconds = 30','invoke-boundedprocess',"stop-setup 'opencode_version_timeout'", "stop-setup 'model_query_timeout'", "@('models', `$modelprovider)")) { if (-not $runnerLower.Contains($token)) { [void]$failures.Add("runner-contract:$token") } }
foreach ($ambiguous in @("([string](Invoke-GitLines @('remote','get-url','origin'))[0])","([string](Invoke-GitLines @('rev-parse','HEAD'))[0])","@(& `$openCode --version 2>&1)","@(& `$openCode models `$modelProvider 2>&1)")) { if ($runner.Contains($ambiguous)) { [void]$failures.Add("runner-ambiguous-or-unbounded-call:$ambiguous") } }
if ($runner.Contains('Set-Content -LiteralPath $globalConfig')) { [void]$failures.Add('runner-contract:existing-global-config-mutation') }
foreach ($forbidden in @('git reset','git clean','git stash','push --force','apikey','password=')) { if ($runnerLower.Contains($forbidden)) { [void]$failures.Add("forbidden-token:$forbidden") } }
$manifest = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/manifest.json') -Raw | ConvertFrom-Json
if ([string]$manifest.entrypoints.runtimeRecoveryRouter -ne 'tooling/harness/operational/opencode-lsp-setup/Recover-OpenCodeRuntime.ps1') { [void]$failures.Add('manifest-runtime-recovery-router-missing') }
if ([bool]$manifest.runtimeRecovery.sameStateRetryAllowed) { [void]$failures.Add('manifest-runtime-recovery-allows-same-state-retry') }
if ([bool]$manifest.runtimeRecovery.unrelatedToolInstallationAllowed) { [void]$failures.Add('manifest-runtime-recovery-allows-unrelated-tools') }
if (-not [bool]$manifest.runtimeRecovery.unhealthyExistingRuntimeRepairAllowed) { [void]$failures.Add('manifest-runtime-recovery-disallows-unhealthy-repair') }
if (-not [bool]$manifest.runtimeRecovery.recoveryEvidenceBeforeInspectRequired) { [void]$failures.Add('manifest-runtime-recovery-evidence-not-required') }
$artifacts = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/artifact-registry.json') -Raw | ConvertFrom-Json
$artifactIds = @($artifacts.artifacts | ForEach-Object { [string]$_.artifactId })
foreach ($artifactId in @('runtime-recovery-json','runtime-recovery-report')) { if ($artifactId -notin $artifactIds) { [void]$failures.Add("runtime-recovery-artifact-missing:$artifactId") } }
$failureWorkflow = (Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/workflows/failure-recovery.workflow.json') -Raw).ToLowerInvariant()
foreach ($token in @('opencode_not_found','existing but unhealthy opencode command','one bounded opencode-only install','opencode-runtime-recovery.json','failures before inspect','do not delegate opencode_not_found or unhealthy runtime repair to broad technician setup','never emit the same failing gate as its own next action','same-state retry commands are insufficient','instead of hanging indefinitely')) { if (-not $failureWorkflow.Contains($token)) { [void]$failures.Add("failure-recovery-progress-contract:$token") } }
$cmd = Get-Content -LiteralPath (Join-Path $RootPath 'Test-OpenCodeLspHarness.cmd') -Raw
foreach ($token in @('python.exe -c','py.exe -3 -c','if not errorlevel 1 set "PY_KIND=python"','if not errorlevel 1 set "PY_KIND=py"','Test-AgentDocumentationContract.ps1')) { if (-not $cmd.Contains($token)) { [void]$failures.Add("cmd-contract:$token") } }
$preCommit = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/hooks/Invoke-OpenCodeLspPreCommit.ps1') -Raw
foreach ($token in @('--diff-filter=ACMRD','git -C $RootPath diff --quiet -- $path')) { if (-not $preCommit.Contains($token)) { [void]$failures.Add("precommit-contract:$token") } }
$prePush = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/hooks/Invoke-OpenCodeLspPrePush.ps1') -Raw
foreach ($token in @('[Parameter(Mandatory=$true)][string]$BaseRef','rev-parse --verify')) { if (-not $prePush.Contains($token)) { [void]$failures.Add("prepush-contract:$token") } }
if ($failures.Count -gt 0) { Write-Host 'OPENCODE LSP HARNESS: FAIL' -ForegroundColor Red; $failures | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }; exit 1 }
Write-Host "OPENCODE LSP HARNESS: PASS ($($required.Count) required files)" -ForegroundColor Green
exit 0
