[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$governancePath = Join-Path $RootPath "AGENTS.md"
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [AllowEmptyString()][string]$FailureMessage = ""
    )

    if ($Passed) {
        [void]$passes.Add($Name)
    }
    else {
        [void]$failures.Add("$Name`: $FailureMessage")
    }
}

if (-not (Test-Path -LiteralPath $governancePath -PathType Leaf)) {
    Write-Error "AGENTS.md is missing at repository root"
    exit 1
}

$text = Get-Content -LiteralPath $governancePath -Raw

$requiredSections = @(
    "# Agent Operating Contract",
    "## Agent operating principles",
    "## Precedence",
    "## Mandatory sprint declaration",
    "## Completion standard",
    "## Forbidden behaviors",
    "## Governance enforcement"
)

foreach ($section in $requiredSections) {
    Add-Result -Passed ($text.Contains($section)) -Name "section/$section" -FailureMessage "required governance section is missing"
}

$principles = @(
    "Evidence before action",
    "Floor before furniture",
    "Bounded sprints with declared scope",
    "One writer per branch",
    "Reuse before replacing",
    "No completion without proof"
)
foreach ($token in $principles) {
    Add-Result -Passed ($text.Contains($token)) -Name "principle/$token" -FailureMessage "required operating principle is missing"
}

$precedence = @(
    "Platform, security, legal, and repository-owner instructions.",
    "This governance contract, triggered governance details, and the nearest nested `AGENTS.md`.",
    "Task-specific prompts.",
    "Generic defaults."
)
$previousIndex = -1
for ($i = 0; $i -lt $precedence.Count; $i++) {
    $index = $text.IndexOf($precedence[$i], [System.StringComparison]::Ordinal)
    Add-Result -Passed ($index -ge 0) -Name "precedence/present/$($i + 1)" -FailureMessage "precedence clause is missing: $($precedence[$i])"
    if ($index -ge 0) {
        Add-Result -Passed ($index -gt $previousIndex) -Name "precedence/order/$($i + 1)" -FailureMessage "precedence order is incorrect"
        $previousIndex = $index
    }
}

$sprintTokens = @(
    "repo and branch",
    "lane and mission",
    "owned scope and forbidden scope",
    "expected artifacts and validation commands",
    "proof ceiling"
)
foreach ($token in $sprintTokens) {
    Add-Result -Passed ($text.Contains($token)) -Name "sprint-declaration/$token" -FailureMessage "mandatory sprint declaration token is missing"
}

$completionTokens = @(
    "changed files are named",
    "required validation actually ran and results are recorded",
    "a commit SHA exists for repository mutation",
    "push or PR state is reported",
    "one exact next command is given unless no safe actionable work remains"
)
foreach ($token in $completionTokens) {
    Add-Result -Passed ($text.Contains($token)) -Name "completion/$token" -FailureMessage "completion standard token is missing"
}

$forbiddenTokens = @(
    "Acknowledgment without mutation",
    "Plans without execution",
    "Summaries without proof",
    "Completion claims without running checks",
    "Secret or credential exposure"
)
foreach ($token in $forbiddenTokens) {
    Add-Result -Passed ($text.Contains($token)) -Name "forbidden/$token" -FailureMessage "forbidden behavior token is missing"
}

Add-Result `
    -Passed ($text.Contains("root operating authority and single source of truth")) `
    -Name "authority/single-source-of-truth" `
    -FailureMessage "AGENTS.md does not declare itself the root governance authority"

Add-Result `
    -Passed ($text.Contains("scripts/Test-AgentGovernanceDoctrine.ps1")) `
    -Name "authority/focused-validator" `
    -FailureMessage "AGENTS.md does not name the focused governance validator"

$git = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $git) {
    Add-Result -Passed $false -Name "tracking/git-available" -FailureMessage "git is required to prove AGENTS.md is tracked"
}
else {
    & git -C $RootPath ls-files --error-unmatch AGENTS.md *> $null
    Add-Result -Passed ($LASTEXITCODE -eq 0) -Name "tracking/AGENTS.md" -FailureMessage "AGENTS.md is not tracked by git"

    & git -C $RootPath ls-files --error-unmatch scripts/Test-AgentGovernanceDoctrine.ps1 *> $null
    Add-Result -Passed ($LASTEXITCODE -eq 0) -Name "tracking/validator" -FailureMessage "governance validator is not tracked by git"
}

Write-Host "AGENT GOVERNANCE DOCTRINE" -ForegroundColor Cyan
foreach ($pass in $passes) {
    Write-Host "[PASS] $pass" -ForegroundColor Green
}
foreach ($failure in $failures) {
    Write-Host "[FAIL] $failure" -ForegroundColor Red
}

Write-Host ""
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)

if ($failures.Count -gt 0) {
    exit 1
}

exit 0
