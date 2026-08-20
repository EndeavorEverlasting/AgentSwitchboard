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

# Root owns only ambient universal law, precedence, and progressive routing.
foreach ($token in @(
    '# Agent Operating Contract',
    '## Precedence',
    'Evidence before action',
    'This governance contract',
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
