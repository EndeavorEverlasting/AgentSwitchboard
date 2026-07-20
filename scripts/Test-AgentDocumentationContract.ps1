[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
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

function Get-RequiredText {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [void]$failures.Add("required-file/$RelativePath`: file is missing")
        return $null
    }

    return Get-Content -LiteralPath $path -Raw
}

$requiredRootFiles = @(
    "AGENTS.md",
    "CLAUDE.md",
    "SKILLS.md",
    "CAPABILITIES.md",
    "TRIGGERS.md",
    ".ai/agent-contract.json",
    "plans/README.md",
    "plans/plan-registry.json",
    "plans/schemas/public-plan.schema.json",
    ".ai/skills/project-end-to-end-testing/SKILL.md",
    ".ai/skills/public-plan-coordination/SKILL.md",
    "scripts/Test-PublicPlanContracts.ps1",
    "docs/governance/repository-family.md",
    "templates/repository-agent-contract/README.md",
    "templates/repository-agent-contract/AGENTS.md",
    "templates/repository-agent-contract/CLAUDE.md",
    "templates/repository-agent-contract/SKILLS.md",
    "templates/repository-agent-contract/CAPABILITIES.md",
    "templates/repository-agent-contract/TRIGGERS.md",
    "templates/repository-agent-contract/.ai/agent-contract.json",
    "templates/repository-agent-contract/.ai/skills/public-plan-coordination/SKILL.md",
    "templates/repository-agent-contract/plans/README.md",
    "templates/repository-agent-contract/plans/plan-registry.json",
    "templates/repository-agent-contract/plans/schemas/public-plan.schema.json"
)

foreach ($relativePath in $requiredRootFiles) {
    Add-Result `
        -Passed (Test-Path -LiteralPath (Join-Path $RootPath $relativePath) -PathType Leaf) `
        -Name "required-file/$relativePath" `
        -FailureMessage "required contract file is missing"
}

$contractPath = Join-Path $RootPath ".ai/agent-contract.json"
try {
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    Add-Result -Passed ($contract.schemaVersion -eq 1) -Name "contract/schema-version" -FailureMessage "expected schemaVersion 1"
    Add-Result -Passed (-not [string]::IsNullOrWhiteSpace([string]$contract.contractVersion)) -Name "contract/version" -FailureMessage "contractVersion is missing"
    Add-Result -Passed ($contract.canonicalRepository -eq "EndeavorEverlasting/AgentSwitchboard") -Name "contract/canonical-root" -FailureMessage "canonical repository is incorrect"

    foreach ($entrypoint in @("universal", "claude", "skills", "capabilities", "triggers", "plans", "startupReadiness", "projectEndToEndTesting")) {
        $property = $contract.entrypoints.PSObject.Properties[$entrypoint]
        Add-Result -Passed ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) -Name "contract/entrypoint/$entrypoint" -FailureMessage "entrypoint is missing"
    }

    Add-Result -Passed ($contract.publicPlans.planIsNotPullRequest -eq $true) -Name "contract/public-plans/plan-pr-distinction" -FailureMessage "plan and PR distinction is missing"
    Add-Result -Passed ($contract.publicPlans.machineReadableRequired -eq $true) -Name "contract/public-plans/machine-readable" -FailureMessage "machine-readable plans are not required"
    Add-Result -Passed ($contract.startupReadiness.generatedOutputTracked -eq $false) -Name "contract/startup/untracked" -FailureMessage "startup reports must remain untracked"
    Add-Result -Passed ($contract.projectEndToEndTesting.focusedBeforeBroad -eq $true) -Name "contract/project-e2e/focused-before-broad" -FailureMessage "focused validation is not required before broader validation"
    Add-Result -Passed ($contract.projectEndToEndTesting.runtimeAuthorityRequired -eq $true) -Name "contract/project-e2e/runtime-authority" -FailureMessage "runtime authority is not required"
    Add-Result -Passed ($contract.projectEndToEndTesting.staticOrSyntheticCannotClaimRuntime -eq $true) -Name "contract/project-e2e/proof-boundary" -FailureMessage "static or synthetic proof can claim runtime"

    $expectedRepositories = @(
        "EndeavorEverlasting/AgentSwitchboard",
        "EndeavorEverlasting/Continuum",
        "EndeavorEverlasting/foundry",
        "EndeavorEverlasting/BlacksmithGuild",
        "EndeavorEverlasting/SysAdminSuite",
        "EndeavorEverlasting/web-excel-repair-triage"
    )
    $registered = @($contract.registeredRepositories | ForEach-Object { [string]$_.fullName })
    foreach ($repository in $expectedRepositories) {
        Add-Result -Passed ($registered -contains $repository) -Name "contract/repository/$repository" -FailureMessage "repository is not registered"
    }

    $contractSkills = @($contract.canonicalSkills | ForEach-Object { [string]$_ })
    foreach ($skill in @("project-end-to-end-testing", "public-plan-coordination", "gnhf-prompt-compilation", "powershell-interactive-execution")) {
        Add-Result `
            -Passed ($contractSkills -contains $skill) `
            -Name "contract/skill/$skill" `
            -FailureMessage "canonical skill is not registered"
    }
}
catch {
    [void]$failures.Add("contract/json`: $($_.Exception.Message)")
}

$entrypointExpectations = @{
    "AGENTS.md" = @("CLAUDE.md", "SKILLS.md", "CAPABILITIES.md", "TRIGGERS.md", ".ai/agent-contract.json", "plans/plan-registry.json", "public-plan-coordination", "project-end-to-end-testing")
    "CLAUDE.md" = @("AGENTS.md", "proof")
    "SKILLS.md" = @(".ai/skills", "repo-intake", "bounded-sprint", "project-end-to-end-testing", "public-plan-coordination", "gnhf-prompt-compilation", "powershell-interactive-execution", "evidence-validation", "pr-integration", "runtime-proof")
    "CAPABILITIES.md" = @("Capabilities describe", "verified", "plan.registry.read", "startup.readiness.report")
    "TRIGGERS.md" = @("Triggers", "repo.dirty-or-conflicted", "validation.end-to-end-request", "plan.coordination-request", "startup.readiness-request", "powershell.interactive-snippet", "gnhf.prompt-request", "live-target-mutation")
}

foreach ($file in $entrypointExpectations.Keys) {
    $text = Get-RequiredText -RelativePath $file
    if ($null -eq $text) {
        continue
    }

    foreach ($token in $entrypointExpectations[$file]) {
        Add-Result -Passed ($text.Contains($token)) -Name "entrypoint/$file/$token" -FailureMessage "required contract reference is missing"
    }
}

$expectedSkills = @(
    "repo-intake",
    "bounded-sprint",
    "project-end-to-end-testing",
    "public-plan-coordination",
    "gnhf-prompt-compilation",
    "powershell-interactive-execution",
    "evidence-validation",
    "pr-integration",
    "runtime-proof"
)
$requiredSkillSections = @(
    "## Trigger",
    "## Inputs",
    "## Procedure",
    "## Outputs",
    "## Deterministic validation",
    "## Forbidden scope",
    "## Stop and escalate"
)

foreach ($skill in $expectedSkills) {
    $relativePath = ".ai/skills/$skill/SKILL.md"
    $text = Get-RequiredText -RelativePath $relativePath
    if ($null -eq $text) {
        continue
    }

    Add-Result -Passed ($text.Contains("id: $skill")) -Name "skill/$skill/id" -FailureMessage "skill metadata ID does not match directory"
    Add-Result -Passed ($text.Contains("status: canonical")) -Name "skill/$skill/status" -FailureMessage "skill is not canonical"
    foreach ($section in $requiredSkillSections) {
        Add-Result -Passed ($text.Contains($section)) -Name "skill/$skill/$section" -FailureMessage "required section is missing"
    }
}

$projectEndToEndSkillText = Get-RequiredText -RelativePath ".ai/skills/project-end-to-end-testing/SKILL.md"
if ($null -ne $projectEndToEndSkillText) {
    foreach ($token in @(
        "focused checks before broader safe validation",
        "Test-AppHarness.cmd",
        "exact-head CI",
        "Process exit code zero alone is not delivery proof",
        "evidence-validation",
        "runtime-proof",
        "Static or synthetic proof does not establish runtime or live-target behavior",
        "Do not weaken tests",
        "Stop when repository state is unsafe or ambiguous"
    )) {
        Add-Result `
            -Passed ($projectEndToEndSkillText.Contains($token)) `
            -Name "skill/project-end-to-end-testing/$token" `
            -FailureMessage "project end-to-end testing contract token is missing"
    }
}

$publicPlanSkillText = Get-RequiredText -RelativePath ".ai/skills/public-plan-coordination/SKILL.md"
if ($null -ne $publicPlanSkillText) {
    foreach ($token in @(
        "plans/plan-registry.json",
        "plan and pull request distinct",
        "same branch or PR",
        "product behavior in deterministic code",
        "scripts/Test-PublicPlanContracts.ps1",
        "using a pull request description as the only coordination record"
    )) {
        Add-Result `
            -Passed ($publicPlanSkillText.Contains($token)) `
            -Name "skill/public-plan-coordination/$token" `
            -FailureMessage "public plan coordination token is missing"
    }
}

$gnhfSkillText = Get-RequiredText -RelativePath ".ai/skills/gnhf-prompt-compilation/SKILL.md"
if ($null -ne $gnhfSkillText) {
    foreach ($token in @(
        "Canonical command shape:",
        "gnhf",
        "--agent",
        "--worktree",
        "--max-iterations",
        "--max-tokens",
        "--prevent-sleep on",
        "--stop-when",
        "positive, observable",
        "one repository per GNHF process",
        "Process exit code zero alone is not delivery proof",
        "not a sprint map"
    )) {
        Add-Result `
            -Passed ($gnhfSkillText.Contains($token)) `
            -Name "skill/gnhf-prompt-compilation/format/$token" `
            -FailureMessage "canonical GNHF format token is missing"
    }
}

$powerShellSkillText = Get-RequiredText -RelativePath ".ai/skills/powershell-interactive-execution/SKILL.md"
if ($null -ne $powerShellSkillText) {
    foreach ($token in @(
        "Set-Location -LiteralPath",
        "guard clause",
        "same syntactic submission",
        "Never instruct the operator to submit a closing",
        "No standalone",
        "hardcoded workstation username"
    )) {
        Add-Result `
            -Passed ($powerShellSkillText.Contains($token)) `
            -Name "skill/powershell-interactive-execution/$token" `
            -FailureMessage "interactive PowerShell safety token is missing"
    }
}

$templateContractPath = Join-Path $RootPath "templates/repository-agent-contract/.ai/agent-contract.json"
try {
    $templateContract = Get-Content -LiteralPath $templateContractPath -Raw | ConvertFrom-Json
    Add-Result -Passed ($templateContract.canonicalRepository -eq "EndeavorEverlasting/AgentSwitchboard") -Name "template/canonical-root" -FailureMessage "template does not point to AgentSwitchboard"
    Add-Result -Passed ($templateContract.localRulesMayWeaken -eq $false) -Name "template/no-silent-weakening" -FailureMessage "template permits local weakening"
    Add-Result -Passed ($templateContract.entrypoints.plans -eq "plans/plan-registry.json") -Name "template/public-plan-entrypoint" -FailureMessage "template plan entrypoint is missing"
    Add-Result -Passed ($templateContract.publicPlans.planIsNotPullRequest -eq $true) -Name "template/plan-pr-distinction" -FailureMessage "template does not distinguish plans from PRs"
}
catch {
    [void]$failures.Add("template/json`: $($_.Exception.Message)")
}

Write-Host "AGENT DOCUMENTATION CONTRACT" -ForegroundColor Cyan
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
