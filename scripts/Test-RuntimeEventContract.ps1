[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Check([bool]$Ok,[string]$Name,[string]$Message) {
    if ($Ok) { [void]$passes.Add($Name) } else { [void]$failures.Add("$Name`: $Message") }
}
function Json([string]$Relative) {
    $path = Join-Path $RootPath $Relative
    Check (Test-Path -LiteralPath $path -PathType Leaf) "required/$Relative" 'missing'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
    catch { [void]$failures.Add("json/$Relative`: $($_.Exception.Message)"); $null }
}
function Text([string]$Relative) {
    $path = Join-Path $RootPath $Relative
    Check (Test-Path -LiteralPath $path -PathType Leaf) "required/$Relative" 'missing'
    if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Content -LiteralPath $path -Raw } else { '' }
}
function Uuid($Value) { $g=[Guid]::Empty; return ($null -ne $Value -and [Guid]::TryParse([string]$Value,[ref]$g)) }
function Envelope($Event) {
    if ($null -eq $Event) { return $false }
    foreach ($field in @('schema','eventId','eventType','source','occurredUtc','correlationId','causationId','sequence','payload','metadata')) {
        if ($null -eq $Event.PSObject.Properties[$field]) { return $false }
    }
    return ($Event.schema -eq 'agentswitchboard.runtime-event.v1' -and (Uuid $Event.eventId) -and (Uuid $Event.correlationId) -and ($null -eq $Event.causationId -or (Uuid $Event.causationId)) -and [int]$Event.sequence -ge 0)
}
function Root($Event) { return ((Envelope $Event) -and [string]$Event.correlationId -eq [string]$Event.eventId -and $null -eq $Event.causationId -and [int]$Event.sequence -eq 0) }
function Successor($Parent,$Child) { return ((Envelope $Parent) -and (Envelope $Child) -and [string]$Child.eventId -ne [string]$Parent.eventId -and [string]$Child.correlationId -eq [string]$Parent.correlationId -and [string]$Child.causationId -eq [string]$Parent.eventId -and [int]$Child.sequence -gt [int]$Parent.sequence) }
function Reachable([string]$Start,[string]$Target,[object[]]$Edges) {
    $queue=[System.Collections.Generic.Queue[string]]::new(); $seen=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $queue.Enqueue($Start); [void]$seen.Add($Start)
    while ($queue.Count) { $current=$queue.Dequeue(); if ($current -eq $Target) { return $true }; foreach ($edge in @($Edges | Where-Object { [string]$_.from -eq $current })) { if ($seen.Add([string]$edge.to)) { $queue.Enqueue([string]$edge.to) } } }
    return $false
}

$policy=Json '.ai/harness/runtime-event-contract.policy.json'
$envelopeSchema=Json '.ai/harness/schemas/runtime-event-envelope.schema.json'
$topology=Json '.ai/harness/runtime-event-topology.json'
$topologySchema=Json '.ai/harness/schemas/runtime-event-topology.schema.json'
$root=Json '.ai/harness/fixtures/runtime-events/root-event.json'
$successor=Json '.ai/harness/fixtures/runtime-events/successor-event.json'
$broken=Json '.ai/harness/fixtures/runtime-events/broken-chain-event.json'
$harness=Json '.ai/harness/harness-doctrine.policy.json'
$manifest=Json '.ai/harness/manifest.json'
$agent=Json '.ai/agent-contract.json'
$graph=Json '.ai/harness/app-composition.graph.json'
$template=Json 'templates/repository-agent-contract/.ai/harness/runtime-event-contract.policy.json'

if ($policy) {
    Check ($policy.policyId -eq 'agentswitchboard.runtime-event-contract.v1') 'policy/id' 'unexpected'
    Check ([bool]$policy.envelope.immutableAfterEmission) 'policy/immutable' 'not required'
    Check ([bool]$policy.causality.rootCorrelationEqualsEventId) 'policy/root-correlation' 'missing'
    Check ([bool]$policy.causality.successorCorrelationInherited) 'policy/successor-correlation' 'missing'
    Check ([bool]$policy.causality.successorCausationEqualsParentEventId) 'policy/successor-causation' 'missing'
    Check ([bool]$policy.composition.allRuntimeNodesMustBeRegistered) 'policy/nodes' 'not required'
    Check ([bool]$policy.composition.allRuntimeEdgesMustBeRegistered) 'policy/edges' 'not required'
    Check ([bool]$policy.evidence.staticProofCannotClaimRuntime) 'policy/proof' 'inflated'
}
if ($envelopeSchema) { Check ($envelopeSchema.additionalProperties -eq $false) 'schema/envelope-closed' 'open'; foreach ($field in @('eventId','eventType','correlationId','causationId','sequence')) { Check (@($envelopeSchema.required) -contains $field) "schema/$field" 'missing' } }
if ($topologySchema) { Check ($topologySchema.additionalProperties -eq $false) 'schema/topology-closed' 'open' }
if ($topology) {
    $nodes=@($topology.nodes); $edges=@($topology.edges); $ids=@($nodes | ForEach-Object { [string]$_.id })
    Check ($topology.status -eq 'contract-only') 'topology/status' 'inflated'
    Check (@($ids | Select-Object -Unique).Count -eq $ids.Count) 'topology/unique' 'duplicate'
    foreach ($kind in @('source','observer','handler','sink')) { Check (@($nodes | Where-Object kind -eq $kind).Count -gt 0) "topology/node/$kind" 'missing' }
    foreach ($kind in @('emits','observes','dispatches','emits-successor','records')) { Check (@($edges | Where-Object kind -eq $kind).Count -gt 0) "topology/edge/$kind" 'missing' }
    foreach ($edge in $edges) { Check ($ids -contains [string]$edge.from) "topology/from/$($edge.id)" 'missing'; Check ($ids -contains [string]$edge.to) "topology/to/$($edge.id)" 'missing' }
    $source=@($nodes | Where-Object kind -eq 'source')[0]; $sink=@($nodes | Where-Object { $_.kind -eq 'sink' -and $_.evidenceSink })[0]
    Check (Reachable ([string]$source.id) ([string]$sink.id) $edges) 'topology/reachability' 'disconnected'
}
Check (Root $root) 'fixture/root' 'invalid'
Check (Successor $root $successor) 'fixture/successor' 'invalid'
Check (-not (Root $broken)) 'fixture/broken-root' 'accepted'
Check (-not (Successor $root $broken)) 'fixture/broken-successor' 'accepted'
if ($harness) { Check ($harness.runtimeEventContract.validator -eq 'scripts/Test-RuntimeEventContract.ps1') 'wiring/harness' 'missing' }
if ($manifest) { Check ($manifest.entrypoints.runtimeEventValidator -eq 'scripts/Test-RuntimeEventContract.ps1') 'wiring/manifest' 'missing'; Check ($manifest.runtimeEvents.contractOnly -eq $true) 'wiring/boundary' 'missing' }
if ($agent) { Check ($agent.entrypoints.runtimeEvents -eq 'docs/governance/runtime-event-contract.md') 'wiring/agent' 'missing' }
if ($graph) { $ids=@($graph.nodes | ForEach-Object { [string]$_.id }); foreach ($id in @('contract.runtime-event-policy','contract.runtime-event-topology','validator.runtime-events','schema.runtime-event-envelope','schema.runtime-event-topology')) { Check ($ids -contains $id) "wiring/graph/$id" 'missing' } }
if ($template) { Check ($template.policyId -eq 'agentswitchboard.runtime-event-contract.v1') 'template/id' 'missing'; Check ($template.localRulesMayWeaken -eq $false) 'template/no-weakening' 'weakening allowed' }
foreach ($path in @('docs/governance/runtime-event-contract.md','docs/governance/harness-doctrine.md','AGENTS.md','CODEBASE_MAP.md')) { $text=Text $path; Check ($text.Contains('runtime-event-contract')) "docs/path/$path" 'reference missing'; Check ($text.Contains('Test-RuntimeEventContract.ps1')) "docs/validator/$path" 'reference missing' }
$templateText=Text 'templates/repository-agent-contract/AGENTS.md'
Check ($templateText.Contains('runtime-event doctrine')) 'docs/template-doctrine' 'reference missing'
Check ($templateText.Contains('Test-RuntimeEventContract.ps1')) 'docs/template-validator' 'reference missing'

Write-Host 'RUNTIME EVENT CONTRACT' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host "`nResult: $($passes.Count) passed / $($failures.Count) failed"
if ($failures.Count) { exit 1 }
exit 0
