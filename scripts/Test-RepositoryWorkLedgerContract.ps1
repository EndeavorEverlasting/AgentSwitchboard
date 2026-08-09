[CmdletBinding()]
param(
    [string]$LedgerPath = '.ai/WORK_QUEUE.md'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$ledger = Join-Path $repoRoot $LedgerPath
$policyPath = Join-Path $repoRoot '.ai/harness/repository-work-ledger.policy.json'
$adoptionPath = Join-Path $repoRoot '.ai/harness/repository-work-ledger-adoption.json'
$docPath = Join-Path $repoRoot 'docs/governance/repository-work-ledger-contract.md'

$errors = [System.Collections.Generic.List[string]]::new()
function Add-Error([string]$Message) { $errors.Add($Message) }

foreach ($path in @($ledger, $policyPath, $adoptionPath, $docPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-Error "missing required path: $path" }
}
if ($errors.Count) { $errors | ForEach-Object { Write-Error $_ }; exit 1 }

$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
$adoption = Get-Content -LiteralPath $adoptionPath -Raw | ConvertFrom-Json
$source = Get-Content -LiteralPath $ledger -Raw

if ($policy.contractId -ne 'agentswitchboard.repository-work-ledger.v1') { Add-Error 'unexpected contractId' }
if ($policy.contractVersion -ne '1.0.0') { Add-Error 'unexpected contractVersion' }
if ($policy.donor.repository -ne 'EndeavorEverlasting/AxTask') { Add-Error 'unexpected donor repository' }
if ($policy.donor.pinnedCommit -notmatch '^[0-9a-f]{40}$') { Add-Error 'donor pinnedCommit must be a full SHA' }
if ($adoption.contract.id -ne $policy.contractId -or $adoption.contract.version -ne $policy.contractVersion) { Add-Error 'adoption contract does not match policy' }
if ($adoption.donor.pinnedCommit -ne $policy.donor.pinnedCommit) { Add-Error 'adoption donor pin does not match policy' }

foreach ($phrase in @(
    'contractRef: agentswitchboard.repository-work-ledger.v1@1.0.0',
    'Continuation states are not stopping states.',
    'PR opened is not completion.',
    'DONE is strict.',
    'none; no safe actionable work remains'
)) {
    if (-not $source.Contains($phrase)) { Add-Error "missing ledger contract phrase: $phrase" }
}

$headingRegex = [regex]'(?m)^## (ASQ-\d{3,}) — (.+)$'
$matches = $headingRegex.Matches($source)
if ($matches.Count -eq 0) { Add-Error 'ledger must contain at least one canonical ASQ task block' }

$seen = @{}
$allowedStatuses = @($policy.statusVocabulary)
$continuation = @($policy.continuationStatuses)
$allowedPriorities = @($policy.priorities)
$requiredFields = @($policy.requiredFields)

for ($i = 0; $i -lt $matches.Count; $i++) {
    $match = $matches[$i]
    $id = $match.Groups[1].Value
    if ($seen.ContainsKey($id)) { Add-Error "$id duplicate task id" } else { $seen[$id] = $true }
    $start = $match.Index
    $end = if ($i + 1 -lt $matches.Count) { $matches[$i + 1].Index } else { $source.Length }
    $block = $source.Substring($start, $end - $start)
    $fields = @{}
    foreach ($fieldMatch in [regex]::Matches($block, '(?m)^- \*\*([^*]+):\*\*[ \t]*(.*)$')) {
        $fields[$fieldMatch.Groups[1].Value.Trim()] = $fieldMatch.Groups[2].Value.Trim()
    }
    foreach ($field in $requiredFields) {
        if (-not $fields.ContainsKey($field)) { Add-Error "$id missing field '$field'"; continue }
        if ([string]::IsNullOrWhiteSpace($fields[$field])) { Add-Error "$id required field '$field' must not be blank" }
    }
    $status = $fields['Status']
    $priority = $fields['Priority']
    $owner = $fields['Owner']
    $gate = $fields['Gate']
    $proof = $fields['Last proof']
    $next = $fields['Next action']
    if ($status -and $status -notin $allowedStatuses) { Add-Error "$id invalid status '$status'" }
    if ($priority -and $priority -notin $allowedPriorities) { Add-Error "$id invalid priority '$priority'" }
    if ($status -eq 'CLAIMED' -and ([string]::IsNullOrWhiteSpace($owner) -or $owner -eq 'unclaimed')) { Add-Error "$id CLAIMED requires a concrete owner" }
    if ($status -in $continuation -and $next -eq $policy.terminalNextAction) { Add-Error "$id continuation state requires an executable next action" }
    if ($status -in @('BLOCKED','OPERATOR') -and ([string]::IsNullOrWhiteSpace($gate) -or $gate -eq 'none')) { Add-Error "$id $status requires an exact Gate" }
    if ($status -eq 'DONE') {
        $durable = $proof -match '\b(?:commit|merge):[0-9a-f]{7,40}\b' -or $proof -match '\b(?:workflow|run):#?\d+\b' -or $proof -match '\bartifact:\S+' -or $proof -match '\boperator-proof:\S+'
        if (-not $durable) { Add-Error "$id DONE requires durable Last proof" }
        if ($gate -ne 'none') { Add-Error "$id DONE requires Gate: none" }
        if ($next -ne $policy.terminalNextAction) { Add-Error "$id DONE requires canonical terminal Next action" }
    }
    foreach ($reference in [regex]::Matches($fields['References'], '`([^`]+)`')) {
        $candidate = $reference.Groups[1].Value
        if ($candidate -match '^(https?://|#)') { continue }
        if ($candidate -notmatch '[*?]' -and -not (Test-Path -LiteralPath (Join-Path $repoRoot $candidate))) {
            Add-Error "$id stale local reference: $candidate"
        }
    }
}

if ($errors.Count) {
    Write-Host "[repository-work-ledger] FAIL ($($errors.Count))"
    $errors | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Host "[repository-work-ledger] PASS $LedgerPath ($($matches.Count) tasks) contract=$($policy.contractId)@$($policy.contractVersion)"
