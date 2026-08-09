[CmdletBinding()]
param(
    [string]$LedgerPath = '.ai/WORK_QUEUE.md',
    [switch]$All,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-RepoPath([string]$Path) {
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $repoRoot $Path)
}

$ledger = Resolve-RepoPath $LedgerPath
if (-not (Test-Path -LiteralPath $ledger -PathType Leaf)) {
    throw "Missing repository work ledger: $ledger"
}

$source = Get-Content -LiteralPath $ledger -Raw
$canonicalHeadingRegex = [regex]'(?m)^##[ \t]+(ASQ-\d{3,})[ \t]+—[ \t]+([^\r\n]+)\r?$'
$matches = $canonicalHeadingRegex.Matches($source)
if ($matches.Count -eq 0) {
    throw 'Ledger contains no canonical ASQ task blocks.'
}

$priorityRank = @{ P0 = 0; P1 = 1; P2 = 2; P3 = 3 }
$tasks = [System.Collections.Generic.List[object]]::new()
$required = @('Status', 'Priority', 'Work class', 'Branch / PR', 'Scope', 'References', 'Acceptance gate', 'Gate', 'Next action')

for ($i = 0; $i -lt $matches.Count; $i++) {
    $match = $matches[$i]
    $id = $match.Groups[1].Value
    $title = $match.Groups[2].Value.Trim()
    $start = $match.Index
    $end = if ($i + 1 -lt $matches.Count) { $matches[$i + 1].Index } else { $source.Length }
    $block = $source.Substring($start, $end - $start)
    $fields = @{}

    foreach ($fieldMatch in [regex]::Matches($block, '(?m)^- \*\*([^*]+):\*\*[ \t]*([^\r\n]*)\r?$')) {
        $name = $fieldMatch.Groups[1].Value.Trim()
        if ($fields.ContainsKey($name)) {
            throw "$id duplicate field '$name'"
        }
        $fields[$name] = $fieldMatch.Groups[2].Value.Trim()
    }

    foreach ($field in $required) {
        if (-not $fields.ContainsKey($field) -or [string]::IsNullOrWhiteSpace($fields[$field])) {
            throw "$id missing required frontier field '$field'"
        }
    }

    $status = $fields['Status']
    $workClass = $fields['Work class']
    if ($workClass -notin @('BOUNDED', 'UNBOUNDED')) {
        throw "$id invalid Work class '$workClass'"
    }
    if (-not $priorityRank.ContainsKey($fields['Priority'])) {
        throw "$id invalid Priority '$($fields['Priority'])'"
    }

    $route = switch ($status) {
        'DONE' { 'TERMINAL' }
        'BLOCKED' { 'BLOCKED' }
        'OPERATOR' { 'OPERATOR' }
        default {
            if ($workClass -eq 'UNBOUNDED') { 'DECOMPOSE' } else { 'EXECUTE' }
        }
    }

    $number = [int]($id -replace '^ASQ-', '')
    $tasks.Add([pscustomobject][ordered]@{
        id = $id
        number = $number
        title = $title
        priority = $fields['Priority']
        workClass = $workClass
        status = $status
        route = $route
        branchPr = $fields['Branch / PR']
        scope = $fields['Scope']
        references = $fields['References']
        acceptanceGate = $fields['Acceptance gate']
        gate = $fields['Gate']
        nextAction = $fields['Next action']
    })
}

$actionable = @(
    $tasks |
        Where-Object { $_.route -in @('EXECUTE', 'DECOMPOSE') } |
        Sort-Object @{ Expression = { $priorityRank[$_.priority] } }, @{ Expression = { $_.number } }
)

$selected = if ($All) { @($actionable) } else { @($actionable | Select-Object -First 1) }
$payload = [ordered]@{
    schema = 'agentswitchboard.repository-work-ledger.frontier.v1'
    status = if ($actionable.Count -gt 0) { 'ready' } else { 'empty' }
    actionableCount = $actionable.Count
    selected = if ($actionable.Count -gt 0) { $actionable[0] } else { $null }
    items = @($selected)
}

if ($Json) {
    $payload | ConvertTo-Json -Depth 6
    exit 0
}

if ($actionable.Count -eq 0) {
    Write-Host '[repository-work-ledger-frontier] EMPTY — no EXECUTE or DECOMPOSE task is currently actionable.'
    exit 0
}

foreach ($item in $selected) {
    Write-Host "[repository-work-ledger-frontier] $($item.route) $($item.id) priority=$($item.priority) class=$($item.workClass) status=$($item.status)"
    Write-Host "SCOPE=$($item.scope)"
    Write-Host "ACCEPTANCE_GATE=$($item.acceptanceGate)"
    Write-Host "NEXT_ACTION=$($item.nextAction)"
}
