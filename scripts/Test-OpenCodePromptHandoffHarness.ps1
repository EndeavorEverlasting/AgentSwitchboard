[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param([Parameter(Mandatory)][bool]$Passed, [Parameter(Mandatory)][string]$Name, [string]$FailureMessage = '')
    if ($Passed) { [void]$passes.Add($Name) } else { [void]$failures.Add("${Name}: $FailureMessage") }
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$RelativePath)
    $path = Join-Path $RootPath $RelativePath
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
    catch { [void]$failures.Add("json/${RelativePath}: $($_.Exception.Message)"); return $null }
}

$required = @(
    'tooling/harness/operational/opencode-prompt-handoff/manifest.json',
    'tooling/harness/operational/opencode-prompt-handoff/codebase-map.json',
    'tooling/harness/operational/opencode-prompt-handoff/artifact-registry.json',
    'tooling/harness/operational/opencode-prompt-handoff/workflows/materialize-preflight-execute.workflow.json',
    'tooling/harness/operational/opencode-prompt-handoff/Invoke-OpenCodePromptHandoff.ps1',
    'tooling/harness/operational/opencode-prompt-handoff/hooks/Invoke-OpenCodePromptHandoffPreCommit.ps1',
    'tooling/harness/operational/opencode-prompt-handoff/hooks/Invoke-OpenCodePromptHandoffPrePush.ps1',
    '.ai/skills/opencode-prompt-handoff/SKILL.md',
    'docs/harness/opencode-prompt-handoff.md',
    'scripts/Test-OpenCodePromptHandoffHarness.ps1',
    'tests/test_opencode_prompt_handoff_harness.py',
    '.github/workflows/opencode-prompt-handoff-harness.yml',
    'tooling/gnhf/Start-AgentSwitchboardOpenCode.ps1'
)
foreach ($relative in $required) {
    Add-Result (Test-Path -LiteralPath (Join-Path $RootPath $relative) -PathType Leaf) "required-file/$relative" 'missing required prompt-handoff component'
}

$manifest = Read-JsonFile 'tooling/harness/operational/opencode-prompt-handoff/manifest.json'
$map = Read-JsonFile 'tooling/harness/operational/opencode-prompt-handoff/codebase-map.json'
$artifacts = Read-JsonFile 'tooling/harness/operational/opencode-prompt-handoff/artifact-registry.json'
$workflow = Read-JsonFile 'tooling/harness/operational/opencode-prompt-handoff/workflows/materialize-preflight-execute.workflow.json'

if ($null -ne $manifest) {
    Add-Result ($manifest.harnessId -eq 'agentswitchboard.opencode-prompt-handoff.v1') 'manifest/id' 'unexpected harness id'
    Add-Result ($manifest.integration.preflightAndExecutionUseSamePromptPath -eq $true) 'manifest/same-prompt-path' 'preflight/execution continuity must be explicit'
    Add-Result ($manifest.integration.clipboardMayBridgePreflightToExecution -eq $false) 'manifest/no-clipboard-bridge' 'clipboard may not bridge gates'
    Add-Result ($manifest.generatedEvidence.tracked -eq $false) 'manifest/untracked-evidence' 'generated evidence must be untracked'
    Add-Result ($manifest.hooks.implicitInstallationAllowed -eq $false) 'manifest/opt-in-hooks' 'hooks may not install implicitly'
    Add-Result ($manifest.safety.productMutationAllowed -eq $false) 'manifest/no-product-mutation' 'harness lane may not mutate product code'
    Add-Result ($manifest.safety.governanceMutationOwned -eq $false) 'manifest/no-governance-mutation' 'harness lane may not mutate governance'
    Add-Result ($manifest.safety.destructiveGitAllowed -eq $false) 'manifest/no-destructive-git' 'destructive Git must remain forbidden'
}

if ($null -ne $map) {
    Add-Result ($map.boundary -match 'harness-only') 'map/harness-only-boundary' 'boundary must remain harness-only'
    Add-Result ($map.knownFailure.harnessRule -match 'Clipboard may be an intake source only') 'map/clipboard-intake-only' 'clipboard rule missing'
    Add-Result ($map.commands.run -match 'Invoke-OpenCodePromptHandoff.ps1') 'map/canonical-run-command' 'canonical run command missing'
}

if ($null -ne $artifacts) {
    Add-Result ($artifacts.trackedGeneratedArtifacts -eq $false) 'artifacts/untracked' 'generated artifacts must remain untracked'
    $ids = @($artifacts.artifacts | ForEach-Object { [string]$_.artifactId })
    foreach ($expected in @('bounded-sprint-prompt','prompt-handoff-receipt','prompt-handoff-operator-report')) {
        Add-Result ($ids -contains $expected) "artifacts/$expected" 'artifact role missing'
    }
    $receipt = @($artifacts.artifacts | Where-Object { $_.artifactId -eq 'prompt-handoff-receipt' }) | Select-Object -First 1
    Add-Result ($null -ne $receipt -and $receipt.containsRawPrompt -eq $false) 'artifacts/no-raw-prompt-in-receipt' 'receipt must not contain raw prompt'
}

if ($null -ne $workflow) {
    Add-Result ($workflow.workflowId -eq 'opencode-prompt-handoff-materialize-preflight-execute') 'workflow/id' 'unexpected workflow id'
    $steps = @($workflow.steps) -join "`n"
    Add-Result ($steps -match 'Read the prompt exactly once') 'workflow/read-once' 'read-once rule missing'
    Add-Result ($steps -match 'same -PromptPath') 'workflow/same-prompt-path' 'same prompt path rule missing'
    Add-Result ($steps -match 'Recompute SHA-256 after preflight') 'workflow/rehash-before-execute' 'digest continuity gate missing'
}

$runnerPath = Join-Path $RootPath 'tooling/harness/operational/opencode-prompt-handoff/Invoke-OpenCodePromptHandoff.ps1'
if (Test-Path -LiteralPath $runnerPath -PathType Leaf) {
    $tokens = $null; $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$tokens, [ref]$parseErrors)
    Add-Result ($parseErrors.Count -eq 0) 'runner/powershell-parse' ($parseErrors -join '; ')
    $runnerText = Get-Content -LiteralPath $runnerPath -Raw
    Add-Result (([regex]::Matches($runnerText, 'Get-Clipboard')).Count -eq 1) 'runner/clipboard-read-once' 'runner must read clipboard exactly once'
    Add-Result ($runnerText.Contains("Set-Content -LiteralPath `$promptArtifact")) 'runner/materializes-prompt' 'prompt artifact write missing'
    Add-Result ($runnerText.Contains("'-PromptPath', `$promptArtifact")) 'runner/delegates-prompt-path' 'delegated launcher must receive prompt artifact path'
    Add-Result ($runnerText.Contains("if (`$PlanOnly) { [void]`$arguments.Add('-PlanOnly') }")) 'runner/preflight-mode' 'PlanOnly delegation missing'
    Add-Result ($runnerText.Contains('Prompt artifact changed during preflight')) 'runner/preflight-hash-gate' 'preflight hash gate missing'
    Add-Result ($runnerText.Contains('Prompt artifact changed between preflight and execution')) 'runner/execution-hash-gate' 'execution hash gate missing'
    Add-Result ($runnerText.Contains('rawPromptRecordedInReceipt = $false')) 'runner/no-raw-prompt-receipt' 'receipt privacy marker missing'
    Add-Result ($runnerText -notmatch '(?i)reset\s+--hard|git\s+clean|force-push|core\.hooksPath') 'runner/no-destructive-git' 'runner contains forbidden Git behavior'
}

foreach ($relative in @(
    'tooling/harness/operational/opencode-prompt-handoff/hooks/Invoke-OpenCodePromptHandoffPreCommit.ps1',
    'tooling/harness/operational/opencode-prompt-handoff/hooks/Invoke-OpenCodePromptHandoffPrePush.ps1'
)) {
    $path = Join-Path $RootPath $relative
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $tokens = $null; $parseErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
        Add-Result ($parseErrors.Count -eq 0) "hook/parse/$relative" ($parseErrors -join '; ')
        $text = Get-Content -LiteralPath $path -Raw
        Add-Result ($text.Contains('Test-OpenCodePromptHandoffHarness.ps1')) "hook/owning-validator/$relative" 'owning validator missing'
        Add-Result ($text -notmatch '(?i)core\.hooksPath|git\s+config|reset\s+--hard|git\s+clean|force-push') "hook/no-implicit-or-destructive/$relative" 'hook contains forbidden behavior'
    }
}

$productPath = Join-Path $RootPath 'tooling/gnhf/Start-AgentSwitchboardOpenCode.ps1'
if (Test-Path -LiteralPath $productPath -PathType Leaf) {
    $product = Get-Content -LiteralPath $productPath -Raw
    Add-Result ($product.Contains('[string]$PromptPath')) 'integration/product-supports-prompt-path' 'existing launcher must accept PromptPath'
    Add-Result ($product.Contains('[switch]$PlanOnly')) 'integration/product-supports-plan-only' 'existing launcher must accept PlanOnly'
}

$skillPath = Join-Path $RootPath '.ai/skills/opencode-prompt-handoff/SKILL.md'
if (Test-Path -LiteralPath $skillPath -PathType Leaf) {
    $skill = Get-Content -LiteralPath $skillPath -Raw
    foreach ($token in @('id: opencode-prompt-handoff','status: canonical','## Trigger','## Inputs','## Procedure','## Outputs','## Deterministic validation','## Forbidden scope','## Stop and escalate')) {
        Add-Result ($skill.Contains($token)) "skill/$token" 'required skill token missing'
    }
}

Write-Host 'OPENCODE PROMPT HANDOFF HARNESS' -ForegroundColor Cyan
foreach ($pass in $passes) { Write-Host "[PASS] $pass" -ForegroundColor Green }
foreach ($failure in $failures) { Write-Host "[FAIL] $failure" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
