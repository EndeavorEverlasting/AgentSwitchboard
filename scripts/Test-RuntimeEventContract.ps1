[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Check([bool]$Condition, [string]$Name, [string]$Message) {
    if ($Condition) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("$Name`: $Message") }
}

function Read-Json([string]$RelativePath) {
    $path = Join-Path $RootPath $RelativePath
    Check (Test-Path -LiteralPath $path -PathType Leaf) "required/$RelativePath" 'file missing'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
    catch { [void]$failures.Add("json/$RelativePath`: $($_.Exception.Message)"); return $null }
}

function Read-Text([string]$RelativePath) {
    $path = Join-Path $RootPath $RelativePath
    Check (Test-Path -LiteralPath $path -PathType Leaf) "required/$RelativePath" 'file missing'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '' }
    return Get-Content -LiteralPath $path -Raw
}

function Is-Uuid([object]$Value) {
    if ($null -eq $Value) { return $false }
    $parsed = [Guid]::Empty
    return [Guid]::TryParse([string]$Value, [ref]$parsed)
}

function Envelope-Valid([object]$Event) {
    if ($null -eq $Event) { return $false }
    foreach ($field in @('schema','eventId','eventType','source','occurredUtc','correlationId','causationId','sequence','payload','metadata')) {
        if ($null -eq $Event.PSObject.Properties[$field]) { return $false }
    }
    return ($Event.schema -eq 'agentswitchboard.runtime-event.v1' -and
        (Is-Uuid $Event.eventId) -and
        [string]$Event.eventType -match '^[a-z0-9]+(?:[.-][a-z0-9]+)*$' -and
        (Is-Uuid $Event.correlationId) -and
        ($null -eq $Event.causationId -or (Is-Uuid $Event.causationId)) -and
        [int]$Event.sequence -ge 0)
}

function Root-Valid([object]$Event) {
    return ((Envelope-Valid $Event) -and
        [string]$Event.correlationId -eq [string]$Event.eventId -and
        $null -eq $Event.causationId -and
        [int]$Event.sequence -eq 0)
}

function Successor-Valid([object]$Parent, [object]$Child) {
    return ((Envelope-Valid $Parent) -and (Envelope-Valid $Child) -and
        [string]$Child.eventId -ne [string]$Parent.eventId -and
        [string]$Child.correlationId -eq [string]$Parent.correlationId -and
        [string]$Child.causationId -eq [string]$Parent.eventId -and
        [int]$Child.sequence -gt [int]$Parent.sequence)
}

function Reachable([string]$Start, [string]$Target, [object[]]$Edges) {
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $queue.Enqueue($Start); [void]$seen.Add($Start)
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if ($current -eq $Target) { return $true }
        foreach ($edge in @($Edges | Where-Object { [string]$_.from -eq $current })) {
            $next = [string]$edge.to
            if ($seen.Add($next)) { $queue.Enqueue($next) }
        }
    }
    return $false
}

$policy = Read-Json '.ai/harness/runtime-event-contract.policy.json'
$envelopeSchema = Read-Json '.ai/harness/schemas/runtime-event-envelope.schema.json'
$topology = Read-Json '.ai/harness/runtime-event-topology.json'
$topologySchema = Read-Json '.ai/harness/schemas/runtime-event-topology.schema.json'
$root = Read-Json '.ai/harness/fixtures/runtime-events/root-event.json'
$successor = Read-Json '.ai/harness/fixtures/runtime-events/successor-event.json'
$broken = Read-Json '.ai/harness/fixtures/runtime-events/broken-chain-event.json'
$harnessPolicy = Read-Json '.ai/harness/harness-doctrine.policy.json'
$manifest = Read-Json '.ai/harness/manifest.json'
$agentContract = Read-Json '.ai/agent-contract.json'
$appGraph = Read-Json '.ai/harness/app-composition.graph.json'
$templatePolicy = Read-Json 'templates/repository-agent-contract/.ai/harness/runtime-event-contract.policy.json'

if ($policy) {
    Check ($policy.policyId -eq 'agentswitchboard.runtime-event-contract.v1') 'policy/id' 'unexpected ID'
    Check ([bool]$policy.envelope.immutableAfterEmission) 'policy/immutable' 'envelope mutation permitted'
    Check ([bool]$policy.causality.rootCorrelationEqualsEventId) 'policy/root-correlation' 'root correlation rule missing'
    Check ([bool]$policy.causality.successorCorrelationInherited) 'policy/successor-correlation' 'successor correlation rule missing'
    Check ([bool]$policy.causality.successorCausationEqualsParentEventId) 'policy/successor-causation' 'successor causation rule missing'
    Check ([bool]$policy.composition.allRuntimeNodesMustBeRegistered) 'policy/nodes' 'node registration not required'
    Check ([bool]$policy.composition.allRuntimeEdgesMustBeRegistered) 'policy/edges' 'edge registration not required'
    Check ([bool]$policy.evidence.staticProofCannotClaimRuntime) 'policy/proof' 'static proof may claim runtime'
}
if ($envelopeSchema) {
    Check ($envelopeSchema.additionalProperties -eq $false) 'schema/envelope-closed' 'schema is open'
    foreach ($field in @('eventId','eventType','correlationId','causationId','sequence')) {
        Check (@($envelopeSchema.required) -contains $field) "schema/required/$field" 'required field missing'
    }
}
if ($topologySchema) { Check ($topologySchema.additionalProperties -eq $false) 'schema/topology-closed' 'schema is open' }

if ($topology) {
    $nodes = @($topology.nodes); $edges = @($topology.edges)
    $nodeIds = @($nodes | ForEach-Object { [string]$_.id })
    Check ($topology.status -eq 'contract-only') 'topology/status' 'topology overclaims runtime'
    Check (@($nodeIds | Select-Object -Unique).Count -eq $nodeIds.Count) 'topology/unique-nodes' 'duplicate nodes'
    foreach ($kind in @('source','observer','handler','sink')) {
        Check (@($nodes | Where-Object { $_.kind -eq $kind }).Count -gt 0) "topology/node/$kind" 'node kind missing'
    }
    foreach ($kind in @('emits','observes','dispatches','emits-successor','records')) {
        Check (@($edges | Where-Object { $_.kind -eq $kind }).Count -gt 0) "topology/edge/$kind" 'edge kind missing'
    }
    foreach ($edge in $edges) {
        Check ($nodeIds -contains [string]$edge.from) "topology/source/$($edge.id)" 'source missing'
        Check ($nodeIds -contains [string]$edge.to) "topology/target/$($edge.id)" 'target missing'
    }
    $source = @($nodes | Where-Object kind -eq 'source')[0]
    $sink = @($nodes | Where-Object { $_.kind -eq 'sink' -and $_.evidenceSink })[0]
    Check (Reachable ([string]$source.id) ([string]$sink.id) $edges) 'topology/reachability' 'source cannot reach sink'
}

Check (Root-Valid $root) 'fixture/root-valid' 'root chain invalid'
Check (Successor-Valid $root $successor) 'fixture/successor-valid' 'successor chain invalid'
Check (-not (Root-Valid $broken)) 'fixture/broken-root-rejected' 'broken root accepted'
Check (-not (Successor-Valid $root $broken)) 'fixture/broken-successor-rejected' 'broken successor accepted'

if ($harnessPolicy) { Check ($harnessPolicy.runtimeEventContract.validator -eq 'scripts/Test-RuntimeEventContract.ps1') 'wiring/harness-policy' 'validator missing' }
if ($manifest) {
    Check ($manifest.entrypoints.runtimeEventValidator -eq 'scripts/Test-RuntimeEventContract.ps1') 'wiring/manifest-validator' 'validator missing'
    Check ($manifest.runtimeEvents.contractOnly -eq $true) 'wiring/manifest-boundary' 'contract-only boundary missing'
}
if ($agentContract) { Check ($agentContract.entrypoints.runtimeEvents -eq 'docs/governance/runtime-event-contract.md') 'wiring/agent-contract' 'entrypoint missing' }
if ($appGraph) {
    $ids = @($appGraph.nodes | ForEach-Object { [string]$_.id })
    foreach ($id in @('contract.runtime-event-policy','contract.runtime-event-topology','validator.runtime-events','schema.runtime-event-envelope','schema.runtime-event-topology')) {
        Check ($ids -contains $id) "wiring/app-graph/$id" 'node missing'
    }
}
if ($templatePolicy) {
    Check ($templatePolicy.policyId -eq 'agentswitchboard.runtime-event-contract.v1') 'template/id' 'template policy missing'
    Check ($templatePolicy.localRulesMayWeaken -eq $false) 'template/no-weakening' 'template may weaken doctrine'
}

foreach ($text in @(
    (Read-Text 'docs/governance/runtime-event-contract.md'),
    (Read-Text 'docs/governance/harness-doctrine.md'),
    (Read-Text 'AGENTS.md'),
    (Read-Text 'templates/repository-agent-contract/AGENTS.md'),
    (Read-Text 'CODEBASE_MAP.md')
)) {
    Check ($text.Contains('runtime-event-contract')) 'docs/runtime-reference' 'runtime event contract reference missing'
    Check ($text.Contains('Test-RuntimeEventContract.ps1')) 'docs/validator-reference' 'runtime event validator reference missing'
}

Write-Host 'RUNTIME EVENT CONTRACT' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host "`nResult: $($passes.Count) passed / $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
