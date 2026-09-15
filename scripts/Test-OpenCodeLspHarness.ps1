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
foreach ($token in @('installtimeoutseconds = 180','raw.githubusercontent.com/anomalyco/opencode','installersourcecommit','__installer_commit__','agentswitchboard\bin\opencode.cmd','requires localappdata','invoke-boundedprocess','timeout --signal=term','xdg_bin_dir','$installertemppath = ''/tmp/agentswitchboard-opencode-{0}.install.sh'' -f $runid','__installer_path__','.replace(''__installer_path__'', $installertemppath)','grep -fq ''install_dir=$home/.opencode/bin''','grep -fq -- ''--no-modify-path''','bash "__installer_path__" --no-modify-path','opencode_installer_contract_drift','opencode-command-discovery','opencode-version-probe','$initialversionscript = "set -u`n$($script:initialopencodepath) --version"','managed="$home/.opencode/bin/opencode"','__runtime_probe_timeout__','__runtime_kill_after__','--kill-after=__runtime_kill_after__s','illegal-instruction','bus-error','segmentation-fault','$postdiscovery = invoke-wslbash -script $postinstalldiscoveryscript -timeoutseconds 45','$postversionscript = "set -u`n$($script:opencodepath) --version"','reproof-timeout','reproof-version-failed','existing-runtime-version-failed','existing-runtime-version-timeout','opencode-install','post-install-command-discovery','post-install-version-probe','officialinstallpath','postinstallhealthstate','postinstallversionexitcode','postinstallfailureclass','opencode-runtime-recovery.json','opencode-runtime-recovery.md','write-recoveryevidence','laststdoutpresent','laststderrpresent','secretorenvironmentdumppersisted = $false','inspect-handoff','opencode_inspect_handoff_timeout')) { if (-not $runtimeRecoveryRouterLower.Contains($token)) { [void]$failures.Add("runtime-recovery-router-contract:$token") } }
foreach ($forbidden in @('repair-technician-command-shims.cmd','agent_switchboard_no_pause','setup-technicianagentswitchboard.ps1','antigravity.google','git reset','git clean','git stash','push --force','remove-item','export opencode_install_dir=')) { if ($runtimeRecoveryRouterLower.Contains($forbidden)) { [void]$failures.Add("runtime-recovery-router-forbidden-token:$forbidden") } }
if ($runtimeRecoveryRouter.Contains('$versionScript')) { [void]$failures.Add('runtime-recovery-shared-version-script-can-be-undefined') }
$discoveryStart = $runtimeRecoveryRouterLower.IndexOf("`$discoveryscript = @'")
$discoveryEnd = $runtimeRecoveryRouterLower.IndexOf('$discovery = invoke-wslbash -script $discoveryscript')
if ($discoveryStart -lt 0 -or $discoveryEnd -le $discoveryStart) { [void]$failures.Add('runtime-recovery-initial-discovery-block-missing') }
else {
 $discoveryBlock = $runtimeRecoveryRouterLower.Substring($discoveryStart, $discoveryEnd - $discoveryStart)
 if ($discoveryBlock.Contains('command -v opencode')) { [void]$failures.Add('runtime-recovery-initial-discovery-uses-path-winner') }
 if ($discoveryBlock.Contains(':$path')) { [void]$failures.Add('runtime-recovery-initial-discovery-inherits-path') }
 foreach ($candidate in @('"$home/.opencode/bin/opencode"','"${xdg_bin_dir:-}/opencode"','"$home/bin/opencode"','"$home/.local/bin/opencode"')) { if (-not $discoveryBlock.Contains($candidate)) { [void]$failures.Add("runtime-recovery-initial-candidate-missing:$candidate") } }
}
$installStart = $runtimeRecoveryRouterLower.IndexOf("`$installscript = @'")
$installEnd = $runtimeRecoveryRouterLower.IndexOf('$installresult = invoke-wslbash -script $installscript')
if ($installStart -lt 0 -or $installEnd -le $installStart) { [void]$failures.Add('runtime-recovery-install-block-missing') }
else {
 $installBlock = $runtimeRecoveryRouterLower.Substring($installStart, $installEnd - $installStart)
 if ($installBlock.Contains('command -v opencode')) { [void]$failures.Add('runtime-recovery-unhealthy-install-skipped-by-command-presence') }
 if ($installBlock.Contains('opencode_install_dir')) { [void]$failures.Add('runtime-recovery-uses-ignored-install-dir-environment') }
 if ($installBlock.Contains('installer="$(mktemp)"')) { [void]$failures.Add('runtime-recovery-installer-temp-path-bash-local') }
 foreach ($token in @('__installer_path__','raw.githubusercontent.com/anomalyco/opencode/__installer_commit__/install','-o "__installer_path__"','grep -fq ''install_dir=$home/.opencode/bin'' "__installer_path__"','grep -fq -- ''--no-modify-path'' "__installer_path__"','bash "__installer_path__" --no-modify-path')) { if (-not $installBlock.Contains($token)) { [void]$failures.Add("runtime-recovery-installer-contract:$token") } }
}
$postDiscoveryStart = $runtimeRecoveryRouterLower.IndexOf("`$postinstalldiscoveryscript = @'")
$postDiscoveryEnd = $runtimeRecoveryRouterLower.IndexOf('$postdiscovery = invoke-wslbash -script $postinstalldiscoveryscript')
if ($postDiscoveryStart -lt 0 -or $postDiscoveryEnd -le $postDiscoveryStart) { [void]$failures.Add('runtime-recovery-post-install-discovery-block-missing') }
else {
 $postDiscoveryBlock = $runtimeRecoveryRouterLower.Substring($postDiscoveryStart, $postDiscoveryEnd - $postDiscoveryStart)
 if ($postDiscoveryBlock.Contains('command -v opencode')) { [void]$failures.Add('runtime-recovery-post-install-uses-path-winner') }
 if ($postDiscoveryBlock.Contains('candidates=(')) { [void]$failures.Add('runtime-recovery-post-install-guesses-alternate-paths') }
 foreach ($token in @('managed="$home/.opencode/bin/opencode"','timeout --signal=term --kill-after=__runtime_kill_after__s __runtime_probe_timeout__s "$managed" --version','failure_class=''illegal-instruction''','failure_class=''bus-error''','failure_class=''segmentation-fault''','class=%s','state=healthy','state=unhealthy')) { if (-not $postDiscoveryBlock.Contains($token)) { [void]$failures.Add("runtime-recovery-post-install-health-contract:$token") } }
}
$resolver = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/Resolve-AgentSwitchboardCheckout.ps1') -Raw
$resolverLower = $resolver.ToLowerInvariant()
foreach ($token in @('preferredpath','expectedbranch','expectedhead','canonicaloriginpattern','bounded-existing-checkout','created-isolated-clone','worktree add --detach','remote_head_mismatch','opencode-lsp-checkout-resolution.json')) { if (-not $resolverLower.Contains($token)) { [void]$failures.Add("resolver-contract:$token") } }
foreach ($forbidden in @('git reset','git clean','git stash','push --force','remove-item')) { if ($resolverLower.Contains($forbidden)) { [void]$failures.Add("resolver-forbidden-token:$forbidden") } }
$runner = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1') -Raw
$runnerLower = $runner.ToLowerInvariant()
foreach ($token in @('opencode_config_content','opencode/nemotron-3-ultra-free','opencode_v2_lsp_unavailable','configurationdirectory','configuration_directory_already_owned','launcher_mismatch','canonicaloriginpattern','modelprovider','localappdata','lsp=$true','free trial','wrong_repository','recover-agentswitchboardcheckout.ps1','recover-opencoderuntime.ps1','-preferredpath','git_identity_output_empty','$originlines = @(invoke-gitlines','$origin = ([string]$originlines[0]).trim()','$headlines = @(invoke-gitlines','$head = ([string]$headlines[0]).trim()','agentswitchboard\bin\opencode.cmd',"elseif (`$failurecode -eq 'opencode_not_found' -and `$reporesolved)",'probetimeoutseconds = 30','invoke-boundedprocess',"stop-setup 'opencode_version_timeout'", "stop-setup 'model_query_timeout'", "@('models', `$modelprovider)",'programfiles','opencode\opencode.exe')) { if (-not $runnerLower.Contains($token)) { [void]$failures.Add("runner-contract:$token") } }
foreach ($ambiguous in @("([string](Invoke-GitLines @('remote','get-url','origin'))[0])","([string](Invoke-GitLines @('rev-parse','HEAD'))[0])","@(& `$openCode --version 2>&1)","@(& `$openCode models `$modelProvider 2>&1)")) { if ($runner.Contains($ambiguous)) { [void]$failures.Add("runner-ambiguous-or-unbounded-call:$ambiguous") } }
if ($runner.Contains('Set-Content -LiteralPath $globalConfig')) { [void]$failures.Add('runner-contract:existing-global-config-mutation') }
foreach ($forbidden in @('git reset','git clean','git stash','push --force','apikey','password=')) { if ($runnerLower.Contains($forbidden)) { [void]$failures.Add("forbidden-token:$forbidden") } }
$manifest = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/manifest.json') -Raw | ConvertFrom-Json
if ([string]$manifest.entrypoints.runtimeRecoveryRouter -ne 'tooling/harness/operational/opencode-lsp-setup/Recover-OpenCodeRuntime.ps1') { [void]$failures.Add('manifest-runtime-recovery-router-missing') }
if ([bool]$manifest.runtimeRecovery.sameStateRetryAllowed) { [void]$failures.Add('manifest-runtime-recovery-allows-same-state-retry') }
if ([bool]$manifest.runtimeRecovery.unrelatedToolInstallationAllowed) { [void]$failures.Add('manifest-runtime-recovery-allows-unrelated-tools') }
if (-not [bool]$manifest.runtimeRecovery.unhealthyExistingRuntimeRepairAllowed) { [void]$failures.Add('manifest-runtime-recovery-disallows-unhealthy-repair') }
if (-not [bool]$manifest.runtimeRecovery.recoveryEvidenceBeforeInspectRequired) { [void]$failures.Add('manifest-runtime-recovery-evidence-not-required') }
if (-not [bool]$manifest.runtimeRecovery.localAppDataRequired) { [void]$failures.Add('manifest-runtime-recovery-localappdata-not-required') }
if ([bool]$manifest.runtimeRecovery.inheritedPathDiscoveryAllowed) { [void]$failures.Add('manifest-runtime-recovery-allows-inherited-path-discovery') }
if ([bool]$manifest.runtimeRecovery.shellProfileMutationAllowed) { [void]$failures.Add('manifest-runtime-recovery-allows-shell-profile-mutation') }
if (-not [bool]$manifest.runtimeRecovery.installerContractVerificationRequired) { [void]$failures.Add('manifest-runtime-recovery-installer-contract-not-required') }
if (-not [bool]$manifest.runtimeRecovery.installerSourceImmutable) { [void]$failures.Add('manifest-runtime-recovery-installer-source-not-immutable') }
if ([string]$manifest.runtimeRecovery.installerSourceRepository -ne 'anomalyco/opencode') { [void]$failures.Add('manifest-runtime-recovery-installer-repository-mismatch') }
if ([string]$manifest.runtimeRecovery.installerSourceCommit -ne '3a31c4ea801915c0b050df4b3842997ea62b6e93') { [void]$failures.Add('manifest-runtime-recovery-installer-commit-mismatch') }
if ([string]$manifest.runtimeRecovery.officialInstallerExecutablePath -ne '$HOME/.opencode/bin/opencode') { [void]$failures.Add('manifest-runtime-recovery-official-install-path-mismatch') }
if ([string]$manifest.runtimeRecovery.installerTempPathTemplate -ne '/tmp/agentswitchboard-opencode-<runId>.install.sh') { [void]$failures.Add('manifest-runtime-recovery-installer-temp-path-template-mismatch') }
if (-not [bool]$manifest.runtimeRecovery.installerTempPathInjectedByHost) { [void]$failures.Add('manifest-runtime-recovery-installer-temp-path-not-host-injected') }
if ([int]$manifest.runtimeRecovery.postInstallVersionProbeTimeoutSeconds -ne 30) { [void]$failures.Add('manifest-runtime-recovery-post-install-probe-timeout-mismatch') }
if ([int]$manifest.runtimeRecovery.postInstallKillAfterSeconds -ne 10) { [void]$failures.Add('manifest-runtime-recovery-post-install-kill-after-mismatch') }
$initialLocations = @($manifest.runtimeRecovery.initialDiscoveryLocations | ForEach-Object { [string]$_ })
foreach ($expectedLocation in @('$HOME/.opencode/bin','$XDG_BIN_DIR','$HOME/bin','$HOME/.local/bin')) { if ($expectedLocation -notin $initialLocations) { [void]$failures.Add("manifest-runtime-recovery-initial-location-missing:$expectedLocation") } }
$manifestProofRule = ([string]$manifest.runtimeRecovery.proofRule).ToLowerInvariant()
foreach ($token in @('immutable','host-injected','forced-kill','final shim-creation health gate','raw stderr','inherited path')) { if (-not $manifestProofRule.Contains($token)) { [void]$failures.Add("manifest-runtime-recovery-proof-rule-missing:$token") } }
foreach ($token in @("`$script:postinstallfailureclass = 'reproof-timeout'","`$script:postinstallfailureclass = 'reproof-version-failed'","`$script:postinstallhealthstate = 'healthy'","`$script:postinstallfailureclass = 'none'")) { if (-not $runtimeRecoveryRouterLower.Contains($token)) { [void]$failures.Add("runtime-recovery-final-health-evidence:$token") } }
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
$runtimeDoc = Get-Content -LiteralPath (Join-Path $RootPath 'docs/harness/opencode-lsp-workstation-setup.md') -Raw
$runtimeDocLower = $runtimeDoc.ToLowerInvariant()
foreach ($token in @('configuration proof is not lsp runtime proof','lsps will activate as files are read','powershell failure is expected','repository root','branch and head','file opened to trigger lsp','active lsp/server after opening','hover result','definition target','reference count and paths','exact errors','non-lsp semantic fallback used: must be `no`','lsp_runtime_smoke_test: pass','lsp_runtime_smoke_test: fail','correct canonical checkout selected:','supported source file opened/read:','python language server activated:')) { if (-not $runtimeDocLower.Contains($token)) { [void]$failures.Add("runtime-proof-doc-missing:$token") } }
$operatorReport = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/operator-report.template.md') -Raw
if (-not $operatorReport.Contains('proofCeiling')) { [void]$failures.Add('operator-report-missing-proof-ceiling') }
$manifestProofCeiling = ([string]$manifest.safety.proofCeiling).ToLowerInvariant()
foreach ($token in @('opening a supported file','observing runtime behavior','active lsp diagnostics')) { if (-not $manifestProofCeiling.Contains($token)) { [void]$failures.Add("manifest-proof-ceiling-missing:$token") } }
$runtimeSmokeSchemaPath = Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/schemas/opencode-lsp-runtime-smoke-receipt.schema.json'
if (-not (Test-Path -LiteralPath $runtimeSmokeSchemaPath -PathType Leaf)) { [void]$failures.Add('missing:tooling/harness/operational/opencode-lsp-setup/schemas/opencode-lsp-runtime-smoke-receipt.schema.json') }
else {
 try { $runtimeSmokeSchema = Get-Content -LiteralPath $runtimeSmokeSchemaPath -Raw | ConvertFrom-Json } catch { [void]$failures.Add('invalid-json:opencode-lsp-runtime-smoke-receipt.schema.json') }
 if ([string]$runtimeSmokeSchema.title -ne 'OpenCode LSP runtime smoke receipt') { [void]$failures.Add('runtime-smoke-schema-title-mismatch') }
 foreach ($field in @('repositoryRoot','branch','head','fileOpenedToTriggerLsp','activeLspServerAfterOpening','hoverResult','definitionTarget','referenceCount','referencePaths','exactErrors','nonLspSemanticFallbackUsed','verdict','pyrightVersion','nodeVersion','opencodeVersion','proofCeiling')) { if ($field -notin $runtimeSmokeSchema.required) { [void]$failures.Add("runtime-smoke-schema-missing-required:$field") } }
 if ([string]$runtimeSmokeSchema.properties.verdict.pattern -ne '^LSP_RUNTIME_SMOKE_TEST: (PASS|FAIL — .+)$') { [void]$failures.Add('runtime-smoke-schema-verdict-pattern-mismatch') }
 if ([string]$runtimeSmokeSchema.properties.nonLspSemanticFallbackUsed.const -ne 'No') { [void]$failures.Add('runtime-smoke-schema-fallback-const-mismatch') }
}
$runtimeSmokeTemplatePath = Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/operator-report.runtime-smoke.template.md'
if (-not (Test-Path -LiteralPath $runtimeSmokeTemplatePath -PathType Leaf)) { [void]$failures.Add('missing:tooling/harness/operational/opencode-lsp-setup/operator-report.runtime-smoke.template.md') }
else {
 $runtimeSmokeTemplate = Get-Content -LiteralPath $runtimeSmokeTemplatePath -Raw
 $runtimeSmokeLower = $runtimeSmokeTemplate.ToLowerInvariant()
 foreach ($token in @('repository root','branch','head','file opened to trigger lsp','active lsp/server after opening','hover result','definition target','reference count','reference paths','exact errors','non-lsp semantic fallback used','verdict','pyright version','node version','opencode version')) { if (-not $runtimeSmokeLower.Contains($token)) { [void]$failures.Add("runtime-smoke-template-missing:$token") } }
}
foreach ($artifactId in @('runtime-smoke-json','runtime-smoke-report')) { if ($artifactId -notin $artifactIds) { [void]$failures.Add("runtime-smoke-artifact-missing:$artifactId") } }
if ([string]$manifest.entrypoints.runtimeSmokeReceiptSchema -ne 'tooling/harness/operational/opencode-lsp-setup/schemas/opencode-lsp-runtime-smoke-receipt.schema.json') { [void]$failures.Add('manifest-runtime-smoke-schema-entrypoint-missing') }
if ([string]$manifest.entrypoints.asq005RuntimeGatesContract -ne 'tooling/harness/operational/opencode-lsp-setup/asq005-runtime-gates.contract.json') { [void]$failures.Add('manifest-asq005-runtime-gates-contract-missing') }
if ([string]$manifest.entrypoints.asq005RuntimeGatesDoc -ne 'docs/harness/asq005-fresh-tui-lsp-runtime-gates.md') { [void]$failures.Add('manifest-asq005-runtime-gates-doc-missing') }
if ([string]$manifest.entrypoints.asq005FreshTuiCertificationPrep -ne 'tooling/harness/operational/opencode-lsp-setup/Invoke-Asq005FreshTuiCertificationPrep.ps1') { [void]$failures.Add('manifest-asq005-prep-entrypoint-missing') }
$asq005ContractPath = Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/asq005-runtime-gates.contract.json'
$asq005DocPath = Join-Path $RootPath 'docs/harness/asq005-fresh-tui-lsp-runtime-gates.md'
$asq005PrepPath = Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/Invoke-Asq005FreshTuiCertificationPrep.ps1'
if (-not (Test-Path -LiteralPath $asq005ContractPath -PathType Leaf)) { [void]$failures.Add('missing:asq005-runtime-gates.contract.json') }
if (-not (Test-Path -LiteralPath $asq005DocPath -PathType Leaf)) { [void]$failures.Add('missing:asq005-fresh-tui-lsp-runtime-gates.md') }
if (-not (Test-Path -LiteralPath $asq005PrepPath -PathType Leaf)) { [void]$failures.Add('missing:Invoke-Asq005FreshTuiCertificationPrep.ps1') }
else {
 $prepTokens=$null; $prepErrors=$null; [void][Management.Automation.Language.Parser]::ParseFile($asq005PrepPath,[ref]$prepTokens,[ref]$prepErrors)
 if ($prepErrors.Count -gt 0) { [void]$failures.Add("powershell-parse:Invoke-Asq005FreshTuiCertificationPrep.ps1:$($prepErrors[0].Message)") }
 $prepRaw = Get-Content -LiteralPath $asq005PrepPath -Raw
 foreach ($token in @('ASQ005_LIVE_PROOF_STATUS','UNPROVEN','ASQ005_CONFIGURE_IS_NOT_DONE','WINDOWS_REQUIRED','never ASQ-005 DONE','24cce9e321a4913dda32f21a2d51a599dd0e4bb4','test_technician_live_cert_surface.py','read_text','LSP_RUNTIME_SMOKE_TEST: PASS','Get-NormalizedOrigin','Get-NormalizedLocalPath','NOT_ON_MAIN')) {
  if (-not $prepRaw.Contains($token)) { [void]$failures.Add("asq005-prep-missing:$token") }
 }
 $setupPath = Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1'
 $setupRaw = Get-Content -LiteralPath $setupPath -Raw
 if (-not $setupRaw.Contains('OPENCODE_EXPERIMENTAL_LSP_TOOL')) { [void]$failures.Add('asq005-launcher-missing-experimental-lsp-tool') }
}
if (Test-Path -LiteralPath $asq005ContractPath -PathType Leaf) {
 try { $asq005Contract = Get-Content -LiteralPath $asq005ContractPath -Raw | ConvertFrom-Json } catch { [void]$failures.Add('invalid-json:asq005-runtime-gates.contract.json'); $asq005Contract = $null }
 if ($null -ne $asq005Contract) {
  if ([string]$asq005Contract.schema -ne 'agentswitchboard.asq005-runtime-gates.v1') { [void]$failures.Add('asq005-contract-schema-mismatch') }
  if ([string]$asq005Contract.liveProofStatus -ne 'UNPROVEN') { [void]$failures.Add('asq005-contract-live-proof-not-unproven') }
  if (-not [bool]$asq005Contract.configureNeverPromotesToDone) { [void]$failures.Add('asq005-contract-configure-may-promote-done') }
  if ([string]$asq005Contract.runtimeOwner -ne 'Admin Box 1') { [void]$failures.Add('asq005-contract-runtime-owner-mismatch') }
  if ([string]$asq005Contract.headlessBaselineId -ne '20260912T194619Z-e3f423df') { [void]$failures.Add('asq005-contract-baseline-mismatch') }
  if ([string]$asq005Contract.liveFloorCommit -ne '24cce9e321a4913dda32f21a2d51a599dd0e4bb4') { [void]$failures.Add('asq005-contract-floor-mismatch') }
  if ([string]$asq005Contract.fixture.path -ne 'tests/test_technician_live_cert_surface.py') { [void]$failures.Add('asq005-contract-fixture-mismatch') }
  if ([string]$asq005Contract.fixture.symbol -ne 'read_text') { [void]$failures.Add('asq005-contract-symbol-mismatch') }
  if ([string]$asq005Contract.receipts.passVerdict -ne 'LSP_RUNTIME_SMOKE_TEST: PASS') { [void]$failures.Add('asq005-contract-pass-verdict-mismatch') }
  if ([string]$asq005Contract.receipts.nonLspSemanticFallbackUsed -ne 'No') { [void]$failures.Add('asq005-contract-fallback-mismatch') }
  if ([bool]$asq005Contract.receipts.tracked) { [void]$failures.Add('asq005-contract-receipts-must-be-untracked') }
  if ([string]$asq005Contract.prepEntrypoint -ne 'tooling/harness/operational/opencode-lsp-setup/Invoke-Asq005FreshTuiCertificationPrep.ps1') { [void]$failures.Add('asq005-contract-prep-entrypoint-mismatch') }
  $gateIds = @($asq005Contract.gates | ForEach-Object { [string]$_.id })
  $expectedGateIds = @('G0','G1','G2','G3','G4','G5','G6','G7','G8')
  if (($gateIds -join ',') -ne ($expectedGateIds -join ',')) { [void]$failures.Add('asq005-contract-gate-ids-mismatch') }
  $doneRequires = @($asq005Contract.doneRequiresGateIds | ForEach-Object { [string]$_ })
  if (($doneRequires -join ',') -ne ($expectedGateIds -join ',')) { [void]$failures.Add('asq005-contract-done-requires-mismatch') }
  $g1 = @($asq005Contract.gates | Where-Object { [string]$_.id -eq 'G1' })[0]
  if ($null -eq $g1 -or -not [bool]$g1.notSufficientForDone) { [void]$failures.Add('asq005-contract-g1-not-sufficient-missing') }
  $g8 = @($asq005Contract.gates | Where-Object { [string]$_.id -eq 'G8' })[0]
  if ($null -eq $g8 -or -not [bool]$g8.doneRequiresLivePassVerdict) { [void]$failures.Add('asq005-contract-g8-live-pass-required-missing') }
  $g5 = @($asq005Contract.gates | Where-Object { [string]$_.id -eq 'G5' })[0]
  $allowed = @($g5.allowedClassifications | ForEach-Object { [string]$_ })
  foreach ($cls in @('PASS_TUI_HEADLESS_DIFFERENTIAL','PASS_BOTH_MODES','FAIL_TUI_ONLY','FAIL_BOTH_MODES')) {
   if ($cls -notin $allowed) { [void]$failures.Add("asq005-contract-g5-missing:$cls") }
  }
 }
}
if (Test-Path -LiteralPath $asq005DocPath -PathType Leaf) {
 $asq005Doc = Get-Content -LiteralPath $asq005DocPath -Raw
 foreach ($token in @('G0','G8','never counts as ASQ-005 DONE','LSP_RUNTIME_SMOKE_TEST: PASS','Invoke-Asq005FreshTuiCertificationPrep.ps1','LIVE_RUNTIME_PROOF','UNPROVEN','FREEZE')) {
  if (-not $asq005Doc.Contains($token)) { [void]$failures.Add("asq005-doc-missing:$token") }
 }
}
if ([string]$manifest.entrypoints.runtimeSmokeReportTemplate -ne 'tooling/harness/operational/opencode-lsp-setup/operator-report.runtime-smoke.template.md') { [void]$failures.Add('manifest-runtime-smoke-template-entrypoint-missing') }
if (-not $runtimeDoc.Contains('opencode-lsp-runtime-smoke.json')) { [void]$failures.Add('runtime-doc-missing-recorded-receipt-json') }
if (-not $runtimeDoc.Contains('opencode-lsp-runtime-smoke.md')) { [void]$failures.Add('runtime-doc-missing-recorded-receipt-md') }
if (-not $runtimeDoc.Contains('schemas/opencode-lsp-runtime-smoke-receipt.schema.json')) { [void]$failures.Add('runtime-doc-missing-schema-ref') }
if (-not $runtimeDoc.Contains('Invoke-Asq005FreshTuiCertificationPrep.ps1')) { [void]$failures.Add('runtime-doc-missing-asq005-prep') }
if (-not $runtimeDoc.Contains('Configure/CI proof is G1 only and never counts as ASQ-005 DONE')) { [void]$failures.Add('runtime-doc-missing-configure-not-done') }
if ($failures.Count -gt 0) { Write-Host 'OPENCODE LSP HARNESS: FAIL' -ForegroundColor Red; $failures | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }; exit 1 }
Write-Host "OPENCODE LSP HARNESS: PASS ($($required.Count) required files)" -ForegroundColor Green
exit 0
