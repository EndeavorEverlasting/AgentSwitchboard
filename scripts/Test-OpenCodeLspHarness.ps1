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
 'tooling/harness/operational/opencode-lsp-setup/Resolve-AgentSwitchboardCheckout.ps1',
 'tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1',
 'tooling/harness/operational/opencode-lsp-setup/hooks/Invoke-OpenCodeLspPreCommit.ps1',
 'tooling/harness/operational/opencode-lsp-setup/hooks/Invoke-OpenCodeLspPrePush.ps1',
 '.ai/skills/opencode-lsp-workstation-setup/SKILL.md',
 'docs/harness/opencode-lsp-workstation-setup.md',
 'tests/test_opencode_lsp_harness.py','scripts/Test-OpenCodeLspHarness.ps1','Test-OpenCodeLspHarness.cmd','.github/workflows/opencode-lsp-harness.yml'
)
$failures = [Collections.Generic.List[string]]::new()
foreach ($p in $required) { if (-not (Test-Path -LiteralPath (Join-Path $RootPath $p) -PathType Leaf)) { [void]$failures.Add("missing:$p") } }
foreach ($p in @('manifest.json','codebase-map.json','workflows.json','artifact-registry.json')) {
 try { $null = Get-Content -LiteralPath (Join-Path $RootPath "tooling/harness/operational/opencode-lsp-setup/$p") -Raw | ConvertFrom-Json }
 catch { [void]$failures.Add("invalid-json:$p") }
}
foreach ($p in @('tooling/harness/operational/opencode-lsp-setup/Resolve-AgentSwitchboardCheckout.ps1','tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1','tooling/harness/operational/opencode-lsp-setup/hooks/Invoke-OpenCodeLspPreCommit.ps1','tooling/harness/operational/opencode-lsp-setup/hooks/Invoke-OpenCodeLspPrePush.ps1','scripts/Test-OpenCodeLspHarness.ps1')) {
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
$resolver = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/Resolve-AgentSwitchboardCheckout.ps1') -Raw
$resolverLower = $resolver.ToLowerInvariant()
foreach ($token in @('preferredpath','expectedbranch','expectedhead','canonicaloriginpattern','bounded-existing-checkout','created-isolated-clone','worktree add --detach','remote_head_mismatch','opencode-lsp-checkout-resolution.json')) { if (-not $resolverLower.Contains($token)) { [void]$failures.Add("resolver-contract:$token") } }
foreach ($forbidden in @('git reset','git clean','git stash','push --force','remove-item')) { if ($resolverLower.Contains($forbidden)) { [void]$failures.Add("resolver-forbidden-token:$forbidden") } }
$runner = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/Invoke-OpenCodeLspWorkstationSetup.ps1') -Raw
$runnerLower = $runner.ToLowerInvariant()
foreach ($token in @('opencode_config_content','opencode/nemotron-3-ultra-free','opencode_v2_lsp_unavailable','configurationdirectory','configuration_directory_already_owned','launcher_mismatch','canonicaloriginpattern','modelprovider','localappdata','lsp=$true','free trial','wrong_repository')) { if (-not $runnerLower.Contains($token)) { [void]$failures.Add("runner-contract:$token") } }
if ($runner.Contains('Set-Content -LiteralPath $globalConfig')) { [void]$failures.Add('runner-contract:existing-global-config-mutation') }
foreach ($forbidden in @('git reset','git clean','git stash','push --force','apikey','password=')) { if ($runnerLower.Contains($forbidden)) { [void]$failures.Add("forbidden-token:$forbidden") } }
$cmd = Get-Content -LiteralPath (Join-Path $RootPath 'Test-OpenCodeLspHarness.cmd') -Raw
foreach ($token in @('python.exe -c','py.exe -3 -c','if not errorlevel 1 set "PY_KIND=python"','if not errorlevel 1 set "PY_KIND=py"','Test-AgentDocumentationContract.ps1')) { if (-not $cmd.Contains($token)) { [void]$failures.Add("cmd-contract:$token") } }
$preCommit = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/hooks/Invoke-OpenCodeLspPreCommit.ps1') -Raw
foreach ($token in @('--diff-filter=ACMRD','git -C $RootPath diff --quiet -- $path')) { if (-not $preCommit.Contains($token)) { [void]$failures.Add("precommit-contract:$token") } }
$prePush = Get-Content -LiteralPath (Join-Path $RootPath 'tooling/harness/operational/opencode-lsp-setup/hooks/Invoke-OpenCodeLspPrePush.ps1') -Raw
foreach ($token in @('[Parameter(Mandatory=$true)][string]$BaseRef','rev-parse --verify')) { if (-not $prePush.Contains($token)) { [void]$failures.Add("prepush-contract:$token") } }
if ($failures.Count -gt 0) { Write-Host 'OPENCODE LSP HARNESS: FAIL' -ForegroundColor Red; $failures | ForEach-Object { Write-Host "- $_" -ForegroundColor Red }; exit 1 }
Write-Host "OPENCODE LSP HARNESS: PASS ($($required.Count) required files)" -ForegroundColor Green
exit 0
