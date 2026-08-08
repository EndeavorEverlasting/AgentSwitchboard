[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$failures = New-Object System.Collections.Generic.List[string]
$passes = 0

function Pass([string]$Name) {
    $script:passes++
    Write-Host "[PASS] $Name"
}
function Fail([string]$Name, [string]$Detail) {
    $script:failures.Add("$Name :: $Detail")
    Write-Host "[FAIL] $Name :: $Detail"
}
function Require-File([string]$Path) {
    $full = Join-Path $root $Path
    if (Test-Path -LiteralPath $full -PathType Leaf) { Pass "required-file/$Path" } else { Fail "required-file/$Path" 'missing' }
}

$required = @(
    'tooling/harness/operational/execution-actor-routing/manifest.json',
    'tooling/harness/operational/execution-actor-routing/codebase-map.json',
    'tooling/harness/operational/execution-actor-routing/artifact-registry.json',
    'tooling/harness/operational/execution-actor-routing/workflows/bind-execute-verify.workflow.json',
    'tooling/harness/operational/execution-actor-routing/schemas/execution-actor-binding.schema.json',
    'tooling/harness/operational/execution-actor-routing/Invoke-ExecutionActorRouting.py',
    'tooling/harness/operational/execution-actor-routing/hooks/Invoke-ExecutionActorRoutingPreCommit.ps1',
    'tooling/harness/operational/execution-actor-routing/hooks/Invoke-ExecutionActorRoutingPrePush.ps1',
    '.ai/skills/execution-actor-routing/SKILL.md',
    'docs/harness/execution-actor-routing.md',
    'tests/test_execution_actor_routing_harness.py',
    '.github/workflows/execution-actor-routing-harness.yml'
)
$required | ForEach-Object { Require-File $_ }

$jsonFiles = @(
    'tooling/harness/operational/execution-actor-routing/manifest.json',
    'tooling/harness/operational/execution-actor-routing/codebase-map.json',
    'tooling/harness/operational/execution-actor-routing/artifact-registry.json',
    'tooling/harness/operational/execution-actor-routing/workflows/bind-execute-verify.workflow.json',
    'tooling/harness/operational/execution-actor-routing/schemas/execution-actor-binding.schema.json'
)
foreach ($path in $jsonFiles) {
    try {
        Get-Content -LiteralPath (Join-Path $root $path) -Raw | ConvertFrom-Json | Out-Null
        Pass "json/$path"
    } catch {
        Fail "json/$path" $_.Exception.Message
    }
}

$manifest = Get-Content -LiteralPath (Join-Path $root 'tooling/harness/operational/execution-actor-routing/manifest.json') -Raw | ConvertFrom-Json
if ($manifest.rules.explicitActorIsHardGate -eq $true) { Pass 'manifest/explicit-hard-gate' } else { Fail 'manifest/explicit-hard-gate' 'must be true' }
if ($manifest.rules.silentSubstitutionAllowed -eq $false) { Pass 'manifest/no-silent-substitution' } else { Fail 'manifest/no-silent-substitution' 'must be false' }
if ($manifest.rules.actualActorMustMatchSelectedActor -eq $true) { Pass 'manifest/actual-matches-selected' } else { Fail 'manifest/actual-matches-selected' 'must be true' }

$runner = Get-Content -LiteralPath (Join-Path $root 'tooling/harness/operational/execution-actor-routing/Invoke-ExecutionActorRouting.py') -Raw
foreach ($needle in @('actor-mismatch','actor-verified','--requested-actor','--selected-actor','--actual-actor','--evidence')) {
    if ($runner.Contains($needle)) { Pass "runner/$needle" } else { Fail "runner/$needle" 'missing' }
}

$workflow = Get-Content -LiteralPath (Join-Path $root 'tooling/harness/operational/execution-actor-routing/workflows/bind-execute-verify.workflow.json') -Raw
foreach ($needle in @('bind-selected-actor','execute-through-selected-actor','verify-actual-actor','no silent actor substitution')) {
    if ($workflow.Contains($needle)) { Pass "workflow/$needle" } else { Fail "workflow/$needle" 'missing' }
}

$skill = Get-Content -LiteralPath (Join-Path $root '.ai/skills/execution-actor-routing/SKILL.md') -Raw
foreach ($heading in @('## Trigger','## Inputs','## Procedure','## Outputs','## Deterministic validation','## Forbidden scope','## Stop and escalate')) {
    if ($skill.Contains($heading)) { Pass "skill/$heading" } else { Fail "skill/$heading" 'missing' }
}
foreach ($actor in @('chatgpt','agentswitchboard','operator','auto')) {
    $actorToken = '`' + $actor + '`'
    if ($skill.Contains($actorToken)) { Pass "skill/actor-$actor" } else { Fail "skill/actor-$actor" 'missing' }
}

$rootManifest = Get-Content -LiteralPath (Join-Path $root 'tooling/harness/operational/manifest.json') -Raw
if ($rootManifest.Contains('executionActorRoutingHarness')) { Pass 'integration/root-manifest' } else { Fail 'integration/root-manifest' 'missing entrypoint' }
$registry = Get-Content -LiteralPath (Join-Path $root 'tooling/harness/operational/workflow-registry.json') -Raw
if ($registry.Contains('execution-actor-routing')) { Pass 'integration/workflow-registry' } else { Fail 'integration/workflow-registry' 'missing specialized route' }
$validators = Get-Content -LiteralPath (Join-Path $root 'tooling/harness/operational/validator-registry.json') -Raw
if ($validators.Contains('execution-actor-routing')) { Pass 'integration/validator-registry' } else { Fail 'integration/validator-registry' 'missing validator' }
$artifacts = Get-Content -LiteralPath (Join-Path $root 'tooling/harness/operational/artifact-registry.json') -Raw
if ($artifacts.Contains('execution-actor-binding')) { Pass 'integration/artifact-registry' } else { Fail 'integration/artifact-registry' 'missing artifact' }

foreach ($hook in @(
    'tooling/harness/operational/execution-actor-routing/hooks/Invoke-ExecutionActorRoutingPreCommit.ps1',
    'tooling/harness/operational/execution-actor-routing/hooks/Invoke-ExecutionActorRoutingPrePush.ps1'
)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $hook), [ref]$tokens, [ref]$errors)
    if ($errors.Count -eq 0) { Pass "hook/parse/$hook" } else { Fail "hook/parse/$hook" ($errors -join '; ') }
    $text = Get-Content -LiteralPath (Join-Path $root $hook) -Raw
    if ($text -notmatch '(?i)\bgit\s+(reset|clean|push\s+--force|push\s+-f)\b') { Pass "hook/no-destructive/$hook" } else { Fail "hook/no-destructive/$hook" 'destructive git detected' }
}

Write-Host ""
Write-Host "Result: $passes passed / $($failures.Count) failed"
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Host $_ }
    exit 1
}
exit 0
