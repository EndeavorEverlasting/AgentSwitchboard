[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Check([bool]$Ok, [string]$Name, [string]$Message) {
    if ($Ok) { [void]$passes.Add($Name) } else { [void]$failures.Add("$Name`: $Message") }
}
function Json([string]$Relative) {
    $path = Join-Path $RootPath $Relative
    Check (Test-Path -LiteralPath $path -PathType Leaf) "required/$Relative" 'missing'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json }
    catch { [void]$failures.Add("json/$Relative`: $($_.Exception.Message)"); $null }
}
function Text([string]$Relative) {
    $path = Join-Path $RootPath $Relative
    Check (Test-Path -LiteralPath $path -PathType Leaf) "required/$Relative" 'missing'
    if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Content -LiteralPath $path -Raw -Encoding utf8 } else { '' }
}

$policy = Json '.ai/harness/fm-asb-promptkit-protocol.policy.json'
$stateMachine = Json '.ai/harness/fm-asb-promptkit-rollover-state-machine.json'
$null = Json '.ai/harness/schemas/fm-asb-promptkit/protocol-envelope.v1.schema.json'
$null = Json '.ai/harness/schemas/fm-asb-promptkit/agent-observation.v1.schema.json'
$null = Json '.ai/harness/schemas/fm-asb-promptkit/routing-request.v1.schema.json'
$null = Json '.ai/harness/schemas/fm-asb-promptkit/routing-decision.v1.schema.json'
$null = Json '.ai/harness/schemas/fm-asb-promptkit/prompt-dispatch.v1.schema.json'
$null = Json '.ai/harness/schemas/fm-asb-promptkit/context-transition.v1.schema.json'
$null = Json '.ai/harness/fixtures/fm-asb-promptkit/agent-observation.valid.json'
$null = Json '.ai/harness/fixtures/fm-asb-promptkit/routing-request.valid.json'
$null = Json '.ai/harness/fixtures/fm-asb-promptkit/routing-decision.valid.json'
$null = Json '.ai/harness/fixtures/fm-asb-promptkit/prompt-dispatch.valid.json'
$null = Json '.ai/harness/fixtures/fm-asb-promptkit/context-transition.completed.valid.json'
$null = Json '.ai/harness/fixtures/fm-asb-promptkit/context-transition.estimated-automatic.invalid.json'
$null = Json '.ai/harness/fixtures/fm-asb-promptkit/routing-decision.switch-null-primary.invalid.json'
$null = Json '.ai/harness/fixtures/fm-asb-promptkit/receipts/context-transition.aggregate.receipt.json'
$null = Json '.ai/harness/fixtures/fm-asb-promptkit/receipts/needs-attention.checkpoint-failed.receipt.json'
$null = Json '.ai/harness/fixtures/fm-asb-promptkit/receipts/needs-attention.launch-failed-after-stop.receipt.json'

if ($policy) {
    Check ($policy.policyId -eq 'agentswitchboard.fm-asb-promptkit-protocol.v1') 'policy/id' 'unexpected'
    Check ($policy.status -eq 'contract-only') 'policy/status' 'inflated'
    Check ([bool]$policy.proof.staticProofCannotClaimRuntime) 'policy/proof-static' 'missing'
    Check ([bool]$policy.idempotency.promptDispatchRetryMustReuseDeliveryId) 'policy/deliveryId-reuse' 'missing'
    Check ($policy.semanticRules.deliveryPlane -eq 'durable-inbox') 'policy/delivery-plane' 'unexpected'
    Check ($policy.semanticRules.preferredPromptDeliveryMode -eq 'reference') 'policy/delivery-mode' 'unexpected'
    Check (@($policy.mustNotOwn.agentswitchboard) -contains 'direct-terminal-manipulation') 'policy/no-terminal' 'missing'
    Check (@($policy.mustNotOwn.agentswitchboard) -contains 'crew-scheduler') 'policy/no-crew-scheduler' 'missing'
    Check ($policy.validator -eq 'scripts/Test-FmAsbPromptKitProtocolContract.ps1') 'policy/validator' 'missing'
    Check ($policy.pythonValidator -eq 'tests/test_fm_asb_promptkit_protocol_contract.py') 'policy/python' 'missing'
}

if ($stateMachine) {
    Check ($stateMachine.stateMachineId -eq 'agentswitchboard.context-rollover.v1') 'sm/id' 'unexpected'
    Check ($stateMachine.status -eq 'contract-only') 'sm/status' 'inflated'
    Check ($stateMachine.firstSuccessorTurn.mutationAllowed -eq $false) 'sm/no-immediate-mutation' 'allowed'
    Check ($stateMachine.backendGates.tmux -eq 'automatic-crew-rollover') 'sm/tmux' 'unexpected'
    Check ($stateMachine.backendGates.Zellij -eq 'checkpoint-only') 'sm/zellij' 'unexpected'
    Check ($stateMachine.scopeGates.'primary-session' -eq 'checkpoint-and-fresh-session-packet-only') 'sm/primary' 'unexpected'
    $visible = @($stateMachine.userVisibleStates | ForEach-Object { [string]$_.id })
    foreach ($name in @('Healthy', 'Context getting full', 'Checkpointing', 'Ready to continue fresh', 'Relaunching', 'Verified & continuing', 'Needs attention')) {
        Check ($visible -contains $name) "sm/visible/$name" 'missing'
    }
    $events = @($stateMachine.events | ForEach-Object { [string]$_.id })
    foreach ($name in @('pressure.rising.verified', 'pressure.rising.estimated', 'checkpoint.failed', 'rollover.authorized', 'relaunch.launch-failed-after-stop', 'post.verify.passed')) {
        Check ($events -contains $name) "sm/event/$name" 'missing'
    }
}

$protocolDoc = Text 'docs/architecture/fm-asb-promptkit-protocol-v1.md'
$uxDoc = Text 'docs/harness/context-rollover-ux.md'
$codeMap = Text 'CODEBASE_MAP.md'
Check ($protocolDoc.Contains('asb.prompt-dispatch/v1')) 'docs/protocol-dispatch' 'missing'
Check ($protocolDoc.Contains('groundingEpisodeId')) 'docs/protocol-grounding' 'missing'
Check ($uxDoc.Contains('Nothing was relaunched')) 'docs/ux-checkpoint-fail' 'missing'
Check ($uxDoc.Contains('Agent stopped; work is preserved')) 'docs/ux-launch-fail' 'missing'
Check ($uxDoc.Contains('firstmate-relaunch') -or $uxDoc.Contains('FirstMate relaunch')) 'docs/ux-relaunch' 'missing'
Check ($codeMap.Contains('fm-asb-promptkit')) 'docs/codebase-map' 'missing'

$obs = Json '.ai/harness/fixtures/fm-asb-promptkit/agent-observation.valid.json'
$req = Json '.ai/harness/fixtures/fm-asb-promptkit/routing-request.valid.json'
$dec = Json '.ai/harness/fixtures/fm-asb-promptkit/routing-decision.valid.json'
$dispatch = Json '.ai/harness/fixtures/fm-asb-promptkit/prompt-dispatch.valid.json'
$ctx = Json '.ai/harness/fixtures/fm-asb-promptkit/context-transition.completed.valid.json'
$badCtx = Json '.ai/harness/fixtures/fm-asb-promptkit/context-transition.estimated-automatic.invalid.json'
$badDec = Json '.ai/harness/fixtures/fm-asb-promptkit/routing-decision.switch-null-primary.invalid.json'

if ($obs -and $req -and $dec -and $dispatch -and $ctx) {
    Check ($obs.schema -eq 'asb.agent-observation/v1') 'fixture/obs-schema' 'unexpected'
    Check ($obs.output.rawIncluded -eq $false) 'fixture/obs-raw' 'raw included'
    Check ($req.constraints.rawTranscriptIncluded -eq $false) 'fixture/req-transcript' 'transcript included'
    Check ($req.correlationId -eq $obs.correlationId) 'fixture/corr-req' 'broken'
    Check ($dec.correlationId -eq $obs.correlationId) 'fixture/corr-dec' 'broken'
    Check ($dispatch.correlationId -eq $obs.correlationId) 'fixture/corr-dispatch' 'broken'
    Check ($ctx.correlationId -eq $obs.correlationId) 'fixture/corr-ctx' 'broken'
    Check ($req.causationId -eq $obs.eventId) 'fixture/cause-req' 'broken'
    Check ($dec.causationId -eq $req.eventId) 'fixture/cause-dec' 'broken'
    Check ($dispatch.causationId -eq $dec.eventId) 'fixture/cause-dispatch' 'broken'
    Check ($dec.decision.routeAction -eq 'SWITCH_PROMPT') 'fixture/dec-action' 'unexpected'
    Check ($null -ne $dec.decision.primaryPrompt) 'fixture/dec-primary' 'null'
    Check ($dispatch.target.deliveryPlane -eq 'durable-inbox') 'fixture/dispatch-plane' 'unexpected'
    Check ($dispatch.prompt.deliveryMode -eq 'reference') 'fixture/dispatch-mode' 'unexpected'
    Check ($ctx.state -eq 'COMPLETED') 'fixture/ctx-state' 'unexpected'
    Check ($ctx.checkpoint.state -eq 'complete') 'fixture/ctx-checkpoint' 'unexpected'
    Check ($null -ne $ctx.post) 'fixture/ctx-post' 'missing'
    Check ($null -ne $ctx.verification) 'fixture/ctx-verification' 'missing'
    Check ($null -eq $ctx.error) 'fixture/ctx-error' 'non-null'
    Check ($ctx.post.groundingEpisodeId -ne $ctx.semantic.groundingEpisodeId) 'fixture/ctx-ge-advance' 'unchanged'
}

if ($badCtx) {
    Check ($badCtx.pressure.observationSource -eq 'estimated') 'neg/ctx-source' 'unexpected'
    Check ($badCtx.transition.automatic -eq $true) 'neg/ctx-automatic' 'fixture not invalid'
}
if ($badDec) {
    Check ($badDec.decision.routeAction -eq 'SWITCH_PROMPT') 'neg/dec-action' 'unexpected'
    Check ($null -eq $badDec.decision.primaryPrompt) 'neg/dec-primary' 'fixture not invalid'
}

$checkpointFail = Json '.ai/harness/fixtures/fm-asb-promptkit/receipts/needs-attention.checkpoint-failed.receipt.json'
if ($checkpointFail) {
    Check ($checkpointFail.oldAgentPreserved -eq $true) 'receipt/checkpoint-preserve' 'missing'
    Check ($checkpointFail.relaunchAttempted -eq $false) 'receipt/checkpoint-no-relaunch' 'relaunched'
}

Write-Host 'FM-ASB-PROMPTKIT PROTOCOL CONTRACT' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host "`nResult: $($passes.Count) passed / $($failures.Count) failed"
if ($failures.Count) { exit 1 }
exit 0
