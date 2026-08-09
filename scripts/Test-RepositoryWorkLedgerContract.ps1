[CmdletBinding()]
param(
    [string]$LedgerPath = '.ai/WORK_QUEUE.md',
    [string]$PolicyPath = '.ai/harness/repository-work-ledger.policy.json'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
function Resolve-RepoPath([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $repoRoot $Path)
}

$ledger = Resolve-RepoPath $LedgerPath
$policyPathResolved = Resolve-RepoPath $PolicyPath
$adoptionPath = Join-Path $repoRoot '.ai/harness/repository-work-ledger-adoption.json'
$docPath = Join-Path $repoRoot 'docs/governance/repository-work-ledger-contract.md'
$frontierPath = Join-Path $repoRoot 'scripts/Get-RepositoryWorkLedgerFrontier.ps1'

$errors = [System.Collections.Generic.List[string]]::new()
function Add-Error([string]$Message) { $errors.Add($Message) }
function Write-ValidationErrors {
    param([System.Collections.Generic.List[string]]$Messages)
    foreach ($message in $Messages) { [Console]::Error.WriteLine($message) }
}
function Test-ExactSequence {
    param([object[]]$Actual, [object[]]$Expected, [string]$Label)
    $actualValues = @($Actual | ForEach-Object { [string]$_ })
    $expectedValues = @($Expected | ForEach-Object { [string]$_ })
    if ($actualValues.Count -ne $expectedValues.Count -or (Compare-Object -ReferenceObject $expectedValues -DifferenceObject $actualValues)) {
        Add-Error "$Label does not match immutable v1 contract"
    }
}

foreach ($path in @($ledger, $policyPathResolved, $adoptionPath, $docPath, $frontierPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-Error "missing required path: $path" }
}
if ($errors.Count) { Write-ValidationErrors -Messages $errors; exit 1 }

$policy = Get-Content -LiteralPath $policyPathResolved -Raw | ConvertFrom-Json
$adoption = Get-Content -LiteralPath $adoptionPath -Raw | ConvertFrom-Json
$source = Get-Content -LiteralPath $ledger -Raw

$expectedContractId = 'agentswitchboard.repository-work-ledger.v1'
$expectedContractVersion = '1.0.0'
$expectedStatuses = @('READY', 'CLAIMED', 'VERIFY', 'REVIEW', 'MERGE', 'OPERATOR', 'BLOCKED', 'DONE')
$expectedContinuation = @('READY', 'CLAIMED', 'VERIFY', 'REVIEW', 'MERGE')
$expectedPriorities = @('P0', 'P1', 'P2', 'P3')
$expectedRequiredFields = @('Status', 'Priority', 'Owner', 'Branch / PR', 'Scope', 'Forbidden', 'Dependencies', 'References', 'Acceptance gate', 'Gate', 'Last proof', 'Next action', 'Updated')
$expectedLocalRequiredFields = @('Work class')
$expectedWorkClasses = @('BOUNDED', 'UNBOUNDED')
$expectedUnboundedStatuses = @('READY', 'BLOCKED', 'OPERATOR', 'DONE')
$expectedTerminalNextAction = 'none; no safe actionable work remains'

if ($policy.contractId -ne $expectedContractId) { Add-Error 'unexpected contractId' }
if ($policy.contractVersion -ne $expectedContractVersion) { Add-Error 'unexpected contractVersion' }
if ($policy.donor.repository -ne 'EndeavorEverlasting/AxTask') { Add-Error 'unexpected donor repository' }
if ($policy.donor.pinnedCommit -notmatch '^[0-9a-f]{40}$') { Add-Error 'donor pinnedCommit must be a full SHA' }
Test-ExactSequence -Actual @($policy.statusVocabulary) -Expected $expectedStatuses -Label 'statusVocabulary'
Test-ExactSequence -Actual @($policy.continuationStatuses) -Expected $expectedContinuation -Label 'continuationStatuses'
Test-ExactSequence -Actual @($policy.priorities) -Expected $expectedPriorities -Label 'priorities'
Test-ExactSequence -Actual @($policy.requiredFields) -Expected $expectedRequiredFields -Label 'requiredFields'
Test-ExactSequence -Actual @($policy.localExecutionProfile.requiredFields) -Expected $expectedLocalRequiredFields -Label 'localExecutionProfile.requiredFields'
Test-ExactSequence -Actual @($policy.localExecutionProfile.workClasses) -Expected $expectedWorkClasses -Label 'localExecutionProfile.workClasses'
Test-ExactSequence -Actual @($policy.localExecutionProfile.unboundedAllowedStatuses) -Expected $expectedUnboundedStatuses -Label 'localExecutionProfile.unboundedAllowedStatuses'
if ($policy.localExecutionProfile.derivedRoutes.boundedContinuation -ne 'EXECUTE') { Add-Error 'localExecutionProfile bounded route must be EXECUTE' }
if ($policy.localExecutionProfile.derivedRoutes.unboundedReady -ne 'DECOMPOSE') { Add-Error 'localExecutionProfile unbounded route must be DECOMPOSE' }
if ($policy.terminalNextAction -ne $expectedTerminalNextAction) { Add-Error 'terminalNextAction does not match immutable v1 contract' }
if ($adoption.contract.id -ne $expectedContractId -or $adoption.contract.version -ne $expectedContractVersion) { Add-Error 'adoption contract does not match immutable v1 contract' }
if ($adoption.donor.pinnedCommit -ne $policy.donor.pinnedCommit) { Add-Error 'adoption donor pin does not match policy' }
if ($adoption.local.frontier -ne 'scripts/Get-RepositoryWorkLedgerFrontier.ps1') { Add-Error 'adoption must register the local frontier reader' }

foreach ($phrase in @(
    'contractRef: agentswitchboard.repository-work-ledger.v1@1.0.0',
    'Continuation states are not stopping states.',
    'PR opened is not completion.',
    'DONE is strict.',
    'Work class',
    $expectedTerminalNextAction
)) {
    if (-not $source.Contains($phrase)) { Add-Error "missing ledger contract phrase: $phrase" }
}

$canonicalHeadingRegex = [regex]'(?m)^##[ \t]+(ASQ-\d{3,})[ \t]+—[ \t]+([^\r\n]+)\r?$'
$taskLikeHeadingRegex = [regex]'(?m)^##[ \t]+(ASQ-[^\r\n]+)\r?$'
$matches = $canonicalHeadingRegex.Matches($source)
foreach ($taskLikeHeading in $taskLikeHeadingRegex.Matches($source)) {
    if (-not $canonicalHeadingRegex.IsMatch($taskLikeHeading.Value)) {
        Add-Error "malformed ASQ heading: '$($taskLikeHeading.Groups[1].Value)' (expected '## ASQ-### — Title')"
    }
}
if ($matches.Count -eq 0) { Add-Error 'ledger must contain at least one canonical ASQ task block' }

$seen = @{}
$allowedStatuses = $expectedStatuses
$continuation = $expectedContinuation
$allowedPriorities = $expectedPriorities
$requiredFields = @($expectedRequiredFields + $expectedLocalRequiredFields)
$unassignedOwners = @('unclaimed', 'none', 'unknown', 'tbd', 'n/a')
$nonActions = @($expectedTerminalNextAction, 'none', 'tbd', 'status unchanged', 'pr opened', 'tests passed', 'ci green', 'wait', 'wait for review', 'review later', 'merge later', 'test later')
$actionPattern = '^(?:(?:after|once)\b.+?,\s*)?(?:operator\s+)?(?:run|execute|create|decompose|split|update|repair|resolve|merge|fetch|inspect|open|verify|validate|test|commit|push|rebase|retarget|compare|generate|record|obtain|install|apply|build|launch|deploy|restore|export|import|review|reconcile|invoke|edit|write|move|copy|sync|check)\b'

for ($i = 0; $i -lt $matches.Count; $i++) {
    $match = $matches[$i]
    $id = $match.Groups[1].Value
    if ($seen.ContainsKey($id)) { Add-Error "$id duplicate task id" } else { $seen[$id] = $true }
    $start = $match.Index
    $end = if ($i + 1 -lt $matches.Count) { $matches[$i + 1].Index } else { $source.Length }
    $block = $source.Substring($start, $end - $start)
    $fields = @{}
    foreach ($fieldMatch in [regex]::Matches($block, '(?m)^- \*\*([^*]+):\*\*[ \t]*([^\r\n]*)\r?$')) {
        $fieldName = $fieldMatch.Groups[1].Value.Trim()
        if ($fields.ContainsKey($fieldName)) { Add-Error "$id duplicate field '$fieldName'"; continue }
        $fields[$fieldName] = $fieldMatch.Groups[2].Value.Trim()
    }
    foreach ($field in $requiredFields) {
        if (-not $fields.ContainsKey($field)) { Add-Error "$id missing field '$field'"; continue }
        if ([string]::IsNullOrWhiteSpace($fields[$field])) { Add-Error "$id required field '$field' must not be blank" }
    }

    $status = $fields['Status']
    $priority = $fields['Priority']
    $owner = $fields['Owner']
    $workClass = $fields['Work class']
    $gate = $fields['Gate']
    $proof = $fields['Last proof']
    $next = $fields['Next action']

    if ($status -and $status -notin $allowedStatuses) { Add-Error "$id invalid status '$status'" }
    if ($priority -and $priority -notin $allowedPriorities) { Add-Error "$id invalid priority '$priority'" }
    if ($workClass -and $workClass -notin $expectedWorkClasses) { Add-Error "$id invalid Work class '$workClass'" }
    if ($status -eq 'CLAIMED' -and ([string]::IsNullOrWhiteSpace($owner) -or $owner.ToLowerInvariant() -in $unassignedOwners)) { Add-Error "$id CLAIMED requires a concrete owner" }

    if ($workClass -eq 'UNBOUNDED') {
        if ($status -and $status -notin $expectedUnboundedStatuses) {
            Add-Error "$id UNBOUNDED tasks may only use READY, BLOCKED, OPERATOR, or DONE; decompose before implementation continuation"
        }
        if ($status -eq 'READY') {
            if ([string]::IsNullOrWhiteSpace($next) -or $next -notmatch '^(?:decompose|split|create)\b' -or $next -notmatch '\bbounded\b') {
                Add-Error "$id UNBOUNDED READY requires a next action that creates bounded child work"
            }
        }
    }

    if ($status -in $continuation) {
        $normalizedNext = if ($next) { $next.Trim().ToLowerInvariant() } else { '' }
        if ([string]::IsNullOrWhiteSpace($next) -or $normalizedNext -in $nonActions -or $next -notmatch $actionPattern) {
            Add-Error "$id continuation state requires an executable next action beginning with a concrete action verb"
        }
    }
    if ($status -in @('BLOCKED','OPERATOR') -and ([string]::IsNullOrWhiteSpace($gate) -or $gate -eq 'none')) { Add-Error "$id $status requires an exact Gate" }
    if ($status -eq 'DONE') {
        $durable = $proof -match '\b(?:commit|merge):[0-9a-f]{7,40}\b' -or $proof -match '\b(?:workflow|run):#?\d+\b' -or $proof -match '\bartifact:\S+' -or $proof -match '\boperator-proof:\S+'
        if (-not $durable) { Add-Error "$id DONE requires durable Last proof" }
        if ($gate -ne 'none') { Add-Error "$id DONE requires Gate: none" }
        if ($next -ne $expectedTerminalNextAction) { Add-Error "$id DONE requires canonical terminal Next action" }
    }
    foreach ($reference in [regex]::Matches($fields['References'], '`([^`]+)`')) {
        $candidate = $reference.Groups[1].Value
        if ($candidate -match '^(https?://|#)') { continue }
        if ($candidate -notmatch '[*?]' -and -not (Test-Path -LiteralPath (Join-Path $repoRoot $candidate))) { Add-Error "$id stale local reference: $candidate" }
    }
}

if ($errors.Count) {
    Write-Host "[repository-work-ledger] FAIL ($($errors.Count))"
    Write-ValidationErrors -Messages $errors
    exit 1
}
Write-Host "[repository-work-ledger] PASS $LedgerPath ($($matches.Count) tasks) contract=$expectedContractId@$expectedContractVersion local-profile=bounded-frontier"
