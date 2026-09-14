[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepositoryRoot = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [string]$FailureMessage = ''
    )
    if ($Passed) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("${Name}: $FailureMessage") }
}

$rootRelative = 'AGENTS.md'
$detailRelative = 'docs/governance/agent-operating-details.md'
$rootDocumentPath = Join-Path $RepositoryRoot $rootRelative
$detailDocumentPath = Join-Path $RepositoryRoot $detailRelative
$expectedDetailBlob = 'c94b797bef04942636af61b980c478919710e067'
$expectedDetailBytes = 27896

foreach ($entry in @(
    @{ Label='root'; Relative=$rootRelative; Path=$rootDocumentPath },
    @{ Label='details'; Relative=$detailRelative; Path=$detailDocumentPath }
)) {
    $exists = Test-Path -LiteralPath $entry.Path -PathType Leaf
    Add-Result -Passed $exists -Name "governance/$($entry.Label)-file-exists" -FailureMessage "$($entry.Relative) is missing"
    $tracked = $false
    if ($exists) {
        $null = & git -C $RepositoryRoot ls-files --error-unmatch -- $entry.Relative 2>$null
        $tracked = $LASTEXITCODE -eq 0
    }
    Add-Result -Passed $tracked -Name "governance/$($entry.Label)-file-tracked" -FailureMessage "$($entry.Relative) is not tracked by Git"
}

$rootText = if (Test-Path -LiteralPath $rootDocumentPath -PathType Leaf) { Get-Content -LiteralPath $rootDocumentPath -Raw } else { '' }
$detailText = if (Test-Path -LiteralPath $detailDocumentPath -PathType Leaf) { Get-Content -LiteralPath $detailDocumentPath -Raw } else { '' }

# Root owns ambient universal law, precedence, sprint declaration, completion,
# forbidden behavior, and progressive routing. These tokens intentionally pin
# the compact governance doctrine operators must see without loading deep detail.
foreach ($token in @(
    '# Agent Operating Contract',
    'root operating authority and single source of truth',
    '## Agent operating principles',
    'Evidence before action',
    'Floor before furniture',
    'Bounded sprints with declared scope',
    'One writer per branch',
    'Reuse before replacing',
    'No completion without proof',
    '## Precedence',
    'Platform, security, legal, and repository-owner instructions.',
    'This governance contract, triggered governance details, and the nearest nested `AGENTS.md`.',
    'Task-specific prompts.',
    'Generic defaults.',
    '## Mandatory sprint declaration',
    'repo and branch',
    'lane and mission',
    'owned scope and forbidden scope',
    'expected artifacts and validation commands',
    'proof ceiling',
    '## Universal operating law',
    'Repository knowledge is compiled state.',
    'Never weaken or skip a valid gate to manufacture a pass.',
    'Static/synthetic evidence never proves runtime, live-target, provider, deployment, or user-visible success.',
    '## Completion standard',
    'changed files are named',
    'required validation actually ran and results are recorded',
    'a commit SHA exists for repository mutation',
    'push or PR state is reported',
    'one exact next command is given unless no safe actionable work remains',
    '## Forbidden behaviors',
    'Acknowledgment without mutation',
    'Plans without execution',
    'Summaries without proof',
    'Completion claims without running checks',
    'Secret or credential exposure',
    '## Governance enforcement',
    'scripts/Test-AgentGovernanceDoctrine.ps1',
    '## Progressive disclosure reading order',
    'HARNESS.md',
    'tooling/harness/context/context.routes.json',
    'docs/governance/agent-operating-details.md',
    '## Triggered governance detail',
    '## Sprint and proof contract',
    'PR or sprint',
    'Test-RuntimeEventContract.ps1',
    'Test-DeviceProfileLauncherContract.ps1'
)) {
    Add-Result -Passed $rootText.Contains($token) -Name "governance/root-route/$token" -FailureMessage 'compact root authority/routing token is missing'
}
Add-Result -Passed ([Text.Encoding]::UTF8.GetByteCount($rootText) -le 7000) -Name 'governance/root-context-budget' -FailureMessage 'compact root AGENTS.md exceeds 7000 UTF-8 bytes'

# Prove precedence ordering within the precedence section itself. Scoping the
# search prevents duplicated explanatory text elsewhere from hiding a bad order.
$precedenceHeader = '## Precedence'
$precedenceNextHeader = '## Mandatory sprint declaration'
$precedenceStart = $rootText.IndexOf($precedenceHeader, [System.StringComparison]::Ordinal)
$precedenceEnd = $rootText.IndexOf($precedenceNextHeader, [System.StringComparison]::Ordinal)
$precedenceBoundsValid = $precedenceStart -ge 0 -and $precedenceEnd -gt $precedenceStart
Add-Result -Passed $precedenceBoundsValid -Name 'governance/precedence-section-bounds' -FailureMessage 'precedence section is missing or malformed'
$precedenceText = if ($precedenceBoundsValid) {
    $rootText.Substring($precedenceStart, $precedenceEnd - $precedenceStart)
} else {
    ''
}
$precedenceTokens = @(
    'Platform, security, legal, and repository-owner instructions.',
    'This governance contract, triggered governance details, and the nearest nested `AGENTS.md`.',
    'Task-specific prompts.',
    'Generic defaults.'
)
$previousIndex = -1
for ($i = 0; $i -lt $precedenceTokens.Count; $i++) {
    $index = $precedenceText.IndexOf($precedenceTokens[$i], [System.StringComparison]::Ordinal)
    Add-Result -Passed ($index -gt $previousIndex) -Name "governance/precedence-order/$($i + 1)" -FailureMessage 'instruction precedence order is missing or incorrect inside the precedence section'
    if ($index -ge 0) { $previousIndex = $index }
}

# Detailed pre-factor governance remains normative when triggered. Validate the
# tracked Git object instead of checkout bytes so CRLF normalization cannot create
# a false loss-of-authority result.
$detailBlob = $null
$detailBlobBytes = $null
if (Test-Path -LiteralPath $detailDocumentPath -PathType Leaf) {
    $blobLines = @(& git -C $RepositoryRoot rev-parse "HEAD:$detailRelative" 2>&1)
    if ($LASTEXITCODE -eq 0 -and $blobLines.Count -gt 0) {
        $detailBlob = ([string]$blobLines[0]).Trim()
        $sizeLines = @(& git -C $RepositoryRoot cat-file -s $detailBlob 2>&1)
        if ($LASTEXITCODE -eq 0 -and $sizeLines.Count -gt 0) { $detailBlobBytes = [int](([string]$sizeLines[0]).Trim()) }
    }
}
Add-Result -Passed ($detailBlob -eq $expectedDetailBlob) -Name 'governance/details-exact-git-blob' -FailureMessage "expected $expectedDetailBlob, got $detailBlob"
Add-Result -Passed ($detailBlobBytes -eq $expectedDetailBytes) -Name 'governance/details-exact-size' -FailureMessage "expected $expectedDetailBytes bytes, got $detailBlobBytes"

# Readable anchor failures complement the exact-object preservation proof above.
foreach ($token in @(
    '## Agent operating principles',
    '## Instruction precedence',
    '## Mandatory sprint declaration',
    '## Launch order and dependency gates',
    '## Broad-stride execution and principle reuse',
    '## Continuous execution and transport independence',
    '## Agent-facing interface doctrine (AXI)',
    '## Multi-agent and local-model governance',
    '## Forbidden behaviors',
    '## Completion standard',
    'Floor before furniture',
    'One prompt panel goes into one new chat.',
    'A launch order coordinates work; it does not grant authority',
    'Application behavior remains in code',
    'inspect -> decide -> mutate -> validate -> observe -> reconcile -> continue',
    'Token-efficient output',
    'Prove privacy; do not infer it',
    'Acknowledgment without mutation',
    'one exact next command is given'
)) {
    Add-Result -Passed $detailText.Contains($token) -Name "governance/details-anchor/$token" -FailureMessage 'preserved governance anchor is missing'
}

Write-Host 'AGENT GOVERNANCE DOCTRINE' -ForegroundColor Cyan
foreach ($pass in $passes) { Write-Host "[PASS] $pass" -ForegroundColor Green }
foreach ($failure in $failures) { Write-Host "[FAIL] $failure" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)

if ($failures.Count -gt 0) { exit 1 }
exit 0
