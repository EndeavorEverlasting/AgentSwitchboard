[CmdletBinding()]
param(
    [string]$RootPath = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Add-CheckResult {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][AllowEmptyString()][string]$FailureMessage = ""
    )

    if ($Passed) {
        [void]$passes.Add($Name)
    }
    else {
        [void]$failures.Add("$Name`: $FailureMessage")
    }
}

function Get-FileText {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [void]$failures.Add("required-file/$RelativePath`: file is missing")
        return $null
    }

    return Get-Content -LiteralPath $path -Raw
}

$requiredFiles = @(
    "Get-WslWorkstationState.ps1",
    "Install-AgentSwitchboardWsl.ps1",
    "Test-WslBootstrapContracts.ps1",
    "wsl-workstation.example.json",
    "scripts/bootstrap-agent-workstation.sh",
    "templates/tmux.conf",
    "templates/wezterm.lua",
    "fixtures/wsl-manifest.valid.json",
    "fixtures/wsl-state.absent.json",
    "fixtures/wsl-state.installed-no-ubuntu.json",
    "fixtures/wsl-state.ubuntu-stopped.json",
    "fixtures/wsl-state.ubuntu-configured.json",
    "fixtures/wsl-state.docker-desktop-only.json",
    "fixtures/setup-summary.valid-completed.json",
    "fixtures/setup-summary.invalid-failed-probe.json",
    "fixtures/setup-summary.reboot-required.json",
    "fixtures/repo-result.wrong-remote.json",
    "fixtures/repo-result.correct-remote.json",
    "fixtures/setup-summary.plan-only.json",
    "fixtures/wsl-manifest.invalid-schema-version.json",
    "fixtures/wsl-state.missing-schema-version.json"
)

foreach ($relativePath in $requiredFiles) {
    Add-CheckResult `
        -Passed (Test-Path -LiteralPath (Join-Path $RootPath $relativePath) -PathType Leaf) `
        -Name "required-file/$relativePath" `
        -FailureMessage "file is missing"
}

$powerShellFiles = Get-ChildItem -LiteralPath $RootPath -Filter "*.ps1" -File
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )

    Add-CheckResult `
        -Passed ($parseErrors.Count -eq 0) `
        -Name "powershell-parse/$($file.Name)" `
        -FailureMessage (($parseErrors | ForEach-Object { $_.Message }) -join "; ")
}

$jsonFiles = Get-ChildItem -LiteralPath (Join-Path $RootPath "fixtures") -Filter "*.json" -File
$jsonFiles += Get-ChildItem -LiteralPath $RootPath -Filter "*.json" -File
foreach ($file in $jsonFiles) {
    try {
        $null = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
        Add-CheckResult -Passed $true -Name "json-parse/$($file.Name)"
    }
    catch {
        Add-CheckResult -Passed $false -Name "json-parse/$($file.Name)" -FailureMessage $_.Exception.Message
    }
}

$manifestPath = Join-Path $RootPath "wsl-workstation.example.json"
try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    Add-CheckResult -Passed ($manifest.schemaVersion -eq 1) -Name "manifest/schema-version" -FailureMessage "expected schemaVersion 1"
    Add-CheckResult -Passed ($null -ne $manifest.distribution -and -not [string]::IsNullOrWhiteSpace($manifest.distribution.name)) -Name "manifest/distribution-name" -FailureMessage "distribution name is missing"
    Add-CheckResult -Passed ($null -ne $manifest.linuxDevRoot -and -not [string]::IsNullOrWhiteSpace($manifest.linuxDevRoot)) -Name "manifest/linux-dev-root" -FailureMessage "linux dev root is missing"
    Add-CheckResult -Passed ($manifest.packages.Count -gt 0) -Name "manifest/packages-not-empty" -FailureMessage "package list is empty"
    Add-CheckResult -Passed ($manifest.agents.Count -gt 0) -Name "manifest/agents-not-empty" -FailureMessage "agent list is empty"

    foreach ($agent in $manifest.agents) {
        $agentName = [string]$agent.name
        Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace($agentName)) -Name "manifest/agent-name" -FailureMessage "agent has no name"
        Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace([string]$agent.installCommand)) -Name "manifest/$agentName/install-command" -FailureMessage "installCommand is missing"
        Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace([string]$agent.probeCommand)) -Name "manifest/$agentName/probe-command" -FailureMessage "probeCommand is missing"
    }

    if ($manifest.repositories) {
        foreach ($repo in $manifest.repositories) {
            $repoName = [string]$repo.name
            Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace($repoName)) -Name "manifest/repo-name" -FailureMessage "repository has no name"
            Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace([string]$repo.url)) -Name "manifest/$repoName/url" -FailureMessage "url is missing"
            Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace([string]$repo.destination)) -Name "manifest/$repoName/destination" -FailureMessage "destination is missing"
        }
    }

    Add-CheckResult -Passed ($null -ne $manifest.dotfilePolicy) -Name "manifest/dotfile-policy" -FailureMessage "dotfilePolicy is missing"
    Add-CheckResult -Passed ($null -ne $manifest.wezterm) -Name "manifest/wezterm" -FailureMessage "wezterm config is missing"
    Add-CheckResult -Passed ($null -ne $manifest.tmux) -Name "manifest/tmux" -FailureMessage "tmux config is missing"
    Add-CheckResult -Passed ($null -ne $manifest.rebootPolicy) -Name "manifest/reboot-policy" -FailureMessage "rebootPolicy is missing"
    Add-CheckResult -Passed ($null -ne $manifest.pathMapping) -Name "manifest/path-mapping" -FailureMessage "pathMapping is missing"
}
catch {
    [void]$failures.Add("manifest/json`: $($_.Exception.Message)")
}

$invalidManifestPath = Join-Path $RootPath "fixtures\wsl-manifest.invalid-schema-version.json"
try {
    $invalidManifest = Get-Content -LiteralPath $invalidManifestPath -Raw | ConvertFrom-Json
    Add-CheckResult -Passed ($invalidManifest.schemaVersion -ne 1) -Name "fixture/invalid-manifest-rejects-wrong-version" -FailureMessage "invalid manifest should have schemaVersion != 1"
}
catch {
    [void]$failures.Add("fixture/invalid-manifest`: $($_.Exception.Message)")
}

$absentStatePath = Join-Path $RootPath "fixtures\wsl-state.absent.json"
try {
    $absentState = Get-Content -LiteralPath $absentStatePath -Raw | ConvertFrom-Json
    Add-CheckResult -Passed ($absentState.wsl.available -eq $false) -Name "fixture/absent-state-wsl-unavailable" -FailureMessage "absent state should have wsl.available = false"
    Add-CheckResult -Passed ($absentState.distributions.Count -eq 0) -Name "fixture/absent-state-no-distributions" -FailureMessage "absent state should have no distributions"
    Add-CheckResult -Passed ($absentState.developerDistributions.Count -eq 0) -Name "fixture/absent-state-no-developer-distros" -FailureMessage "absent state should have no developer distributions"
}
catch {
    [void]$failures.Add("fixture/absent-state`: $($_.Exception.Message)")
}

$dockerDesktopPath = Join-Path $RootPath "fixtures\wsl-state.docker-desktop-only.json"
try {
    $dockerState = Get-Content -LiteralPath $dockerDesktopPath -Raw | ConvertFrom-Json
    Add-CheckResult -Passed ($dockerState.dockerDesktopPresent -eq $true) -Name "fixture/docker-desktop-present" -FailureMessage "docker desktop state should indicate docker-desktop present"
    $hasDockerDesktop = @($dockerState.distributions | Where-Object { $_.isDockerDesktop -eq $true }).Count -gt 0
    Add-CheckResult -Passed $hasDockerDesktop -Name "fixture/docker-desktop-flagged" -FailureMessage "docker-desktop distribution should be flagged"
    Add-CheckResult -Passed ($dockerState.developerDistributions.Count -eq 0) -Name "fixture/docker-desktop-not-developer" -FailureMessage "docker-desktop should not appear as a developer distribution"
}
catch {
    [void]$failures.Add("fixture/docker-desktop-state`: $($_.Exception.Message)")
}

$configuredStatePath = Join-Path $RootPath "fixtures\wsl-state.ubuntu-configured.json"
try {
    $configuredState = Get-Content -LiteralPath $configuredStatePath -Raw | ConvertFrom-Json
    $hasDevDistro = $configuredState.developerDistributions.Count -gt 0
    Add-CheckResult -Passed $hasDevDistro -Name "fixture/configured-has-developer-distro" -FailureMessage "configured state should have developer distributions"
    if ($hasDevDistro) {
        $devDistro = $configuredState.developerDistributions[0]
        Add-CheckResult -Passed ($devDistro.accessible -eq $true) -Name "fixture/configured-distro-accessible" -FailureMessage "configured distro should be accessible"
        Add-CheckResult -Passed ($null -ne $devDistro.git -and $devDistro.git.available -eq $true) -Name "fixture/configured-git-available" -FailureMessage "configured state should show git available"
        Add-CheckResult -Passed ($null -ne $devDistro.node -and $devDistro.node.available -eq $true) -Name "fixture/configured-node-available" -FailureMessage "configured state should show node available"
    }
}
catch {
    [void]$failures.Add("fixture/configured-state`: $($_.Exception.Message)")
}

$completedSummaryPath = Join-Path $RootPath "fixtures\setup-summary.valid-completed.json"
try {
    $completedSummary = Get-Content -LiteralPath $completedSummaryPath -Raw | ConvertFrom-Json
    Add-CheckResult -Passed ($completedSummary.status -eq "completed") -Name "fixture/completed-summary-status" -FailureMessage "valid completed summary should have status 'completed'"
    Add-CheckResult -Passed ($completedSummary.rebootRequired -eq $false) -Name "fixture/completed-no-reboot" -FailureMessage "completed summary should not require reboot"
    Add-CheckResult -Passed ($completedSummary.commandResults.Count -gt 0) -Name "fixture/completed-has-results" -FailureMessage "completed summary should have command results"
    Add-CheckResult -Passed ($completedSummary.repoResults.Count -gt 0) -Name "fixture/completed-has-repo-results" -FailureMessage "completed summary should have repo results"
}
catch {
    [void]$failures.Add("fixture/completed-summary`: $($_.Exception.Message)")
}

$rebootSummaryPath = Join-Path $RootPath "fixtures\setup-summary.reboot-required.json"
try {
    $rebootSummary = Get-Content -LiteralPath $rebootSummaryPath -Raw | ConvertFrom-Json
    Add-CheckResult -Passed ($rebootSummary.rebootRequired -eq $true) -Name "fixture/reboot-summary-requires-reboot" -FailureMessage "reboot summary should require reboot"
    Add-CheckResult -Passed ($rebootSummary.status -eq "reboot-required") -Name "fixture/reboot-summary-status" -FailureMessage "reboot summary status should be 'reboot-required'"
}
catch {
    [void]$failures.Add("fixture/reboot-summary`: $($_.Exception.Message)")
}

$planSummaryPath = Join-Path $RootPath "fixtures\setup-summary.plan-only.json"
try {
    $planSummary = Get-Content -LiteralPath $planSummaryPath -Raw | ConvertFrom-Json
    Add-CheckResult -Passed ($planSummary.planMode -eq $true) -Name "fixture/plan-summary-plan-mode" -FailureMessage "plan summary should have planMode = true"
    Add-CheckResult -Passed ($planSummary.status -eq "plan-only") -Name "fixture/plan-summary-status" -FailureMessage "plan summary status should be 'plan-only'"
    $allPlanned = @($planSummary.commandResults | Where-Object { $_.status -ne "planned" }).Count -eq 0
    Add-CheckResult -Passed $allPlanned -Name "fixture/plan-summary-all-planned" -FailureMessage "plan summary should only have planned steps"
}
catch {
    [void]$failures.Add("fixture/plan-summary`: $($_.Exception.Message)")
}

$wrongRemotePath = Join-Path $RootPath "fixtures\repo-result.wrong-remote.json"
try {
    $wrongRemote = Get-Content -LiteralPath $wrongRemotePath -Raw | ConvertFrom-Json
    Add-CheckResult -Passed ($wrongRemote.repoResults[0].status -eq "wrong-remote") -Name "fixture/wrong-remote-status" -FailureMessage "wrong remote should have status 'wrong-remote'"
    Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace($wrongRemote.repoResults[0].expectedRemote)) -Name "fixture/wrong-remote-has-expected" -FailureMessage "wrong remote should include expectedRemote"
}
catch {
    [void]$failures.Add("fixture/wrong-remote`: $($_.Exception.Message)")
}

$correctRemotePath = Join-Path $RootPath "fixtures\repo-result.correct-remote.json"
try {
    $correctRemote = Get-Content -LiteralPath $correctRemotePath -Raw | ConvertFrom-Json
    Add-CheckResult -Passed ($correctRemote.repoResults[0].status -eq "already-exists-correct-remote") -Name "fixture/correct-remote-status" -FailureMessage "correct remote should have status 'already-exists-correct-remote'"
}
catch {
    [void]$failures.Add("fixture/correct-remote`: $($_.Exception.Message)")
}

$failedProbePath = Join-Path $RootPath "fixtures\setup-summary.invalid-failed-probe.json"
try {
    $failedProbe = Get-Content -LiteralPath $failedProbePath -Raw | ConvertFrom-Json
    Add-CheckResult -Passed ($failedProbe.status -eq "completed-with-errors") -Name "fixture/failed-probe-status" -FailureMessage "failed probe summary should have status 'completed-with-errors'"
    $hasFailure = @($failedProbe.commandResults | Where-Object { $_.status -eq "failed" }).Count -gt 0
    Add-CheckResult -Passed $hasFailure -Name "fixture/failed-probe-has-failure" -FailureMessage "failed probe summary should contain at least one failed step"
}
catch {
    [void]$failures.Add("fixture/failed-probe`: $($_.Exception.Message)")
}

$missingSchemaPath = Join-Path $RootPath "fixtures\wsl-state.missing-schema-version.json"
try {
    $missingSchema = Get-Content -LiteralPath $missingSchemaPath -Raw | ConvertFrom-Json
    Add-CheckResult -Passed ($null -eq $missingSchema.schemaVersion) -Name "fixture/missing-schema-version-null" -FailureMessage "missing schema version fixture should have null schemaVersion"
}
catch {
    [void]$failures.Add("fixture/missing-schema`: $($_.Exception.Message)")
}

$stateScript = Get-FileText "Get-WslWorkstationState.ps1"
if ($null -ne $stateScript) {
    Add-CheckResult -Passed ($stateScript.Contains("Set-StrictMode -Version Latest")) -Name "state/strict-mode" -FailureMessage "state script does not use strict mode"
    Add-CheckResult -Passed ($stateScript.Contains("ReadToEndAsync()")) -Name "state/async-probe-drain" -FailureMessage "state script does not drain output asynchronously"
    Add-CheckResult -Passed ($stateScript.Contains("docker-desktop")) -Name "state/distinguishes-docker-desktop" -FailureMessage "state script does not distinguish docker-desktop"
    Add-CheckResult -Passed ($stateScript.Contains("ConvertTo-Json")) -Name "state/emits-json" -FailureMessage "state script does not emit JSON"
    Add-CheckResult -Passed ($stateScript.Contains("schemaVersion")) -Name "state/includes-schema-version" -FailureMessage "state output does not include schemaVersion"
}

$installerScript = Get-FileText "Install-AgentSwitchboardWsl.ps1"
if ($null -ne $installerScript) {
    Add-CheckResult -Passed ($installerScript.Contains("Set-StrictMode -Version Latest")) -Name "installer/strict-mode" -FailureMessage "installer does not use strict mode"
    Add-CheckResult -Passed ($installerScript.Contains("SupportsShouldProcess")) -Name "installer/supports-whatif" -FailureMessage "installer does not support -WhatIf"
    Add-CheckResult -Passed ($installerScript.Contains("PlanOnly")) -Name "installer/plan-only-switch" -FailureMessage "installer does not have -PlanOnly switch"
    Add-CheckResult -Passed ($installerScript.Contains("ReadToEndAsync()")) -Name "installer/async-probe-drain" -FailureMessage "installer does not drain output asynchronously"
    Add-CheckResult -Passed ($installerScript.Contains("setup-summary.json")) -Name "installer/writes-summary" -FailureMessage "installer does not write setup-summary.json"
    Add-CheckResult -Passed ($installerScript.Contains("reboot-required")) -Name "installer/reboot-status" -FailureMessage "installer does not handle reboot-required status"
    Add-CheckResult -Passed ($installerScript.Contains("Backup-ManagedFile")) -Name "installer/backs-up-dotfiles" -FailureMessage "installer does not back up managed dotfiles"
    Add-CheckResult -Passed ($installerScript.Contains("bootstrap-agent-workstation.sh")) -Name "installer/invokes-bootstrap" -FailureMessage "installer does not invoke the Linux bootstrap script"
    Add-CheckResult -Passed ($installerScript.Contains("schemaVersion")) -Name "installer/schema-version-check" -FailureMessage "installer does not validate manifest schemaVersion"
    Add-CheckResult -Passed ($installerScript.Contains("wrong-remote")) -Name "installer/detects-wrong-remote" -FailureMessage "installer does not detect wrong repository remotes"
}

$bootstrapScript = Get-FileText "scripts\bootstrap-agent-workstation.sh"
if ($null -ne $bootstrapScript) {
    Add-CheckResult -Passed ($bootstrapScript.Contains("set -euo pipefail")) -Name "bootstrap/strict-error-handling" -FailureMessage "bootstrap script does not use strict error handling"
    Add-CheckResult -Passed ($bootstrapScript.Contains("apt")) -Name "bootstrap/detects-apt" -FailureMessage "bootstrap script does not detect apt"
    Add-CheckResult -Passed ($bootstrapScript.Contains("mkdir -p")) -Name "bootstrap/creates-dev-root" -FailureMessage "bootstrap script does not create dev root"
    Add-CheckResult -Passed ($bootstrapScript.Contains("backup_file")) -Name "bootstrap/backs-up-dotfiles" -FailureMessage "bootstrap script does not have backup function"
    Add-CheckResult -Passed ($bootstrapScript.Contains("git clone")) -Name "bootstrap/clones-repos" -FailureMessage "bootstrap script does not clone repositories"
    Add-CheckResult -Passed ($bootstrapScript.Contains("remote get-url")) -Name "bootstrap/checks-remote" -FailureMessage "bootstrap script does not check existing remotes"
    Add-CheckResult -Passed (-not $bootstrapScript.Contains("credentials")) -Name "bootstrap/no-credentials" -FailureMessage "bootstrap script contains 'credentials'"
    Add-CheckResult -Passed ($bootstrapScript.Contains("probe")) -Name "bootstrap/probes-commands" -FailureMessage "bootstrap script does not probe installed commands"
}

$wrongRemoteResult = Get-FileText "fixtures\repo-result.wrong-remote.json"
if ($null -ne $wrongRemoteResult) {
    $parsed = $wrongRemoteResult | ConvertFrom-Json
    Add-CheckResult -Passed ($parsed.repoResults[0].status -eq "wrong-remote") -Name "contract/wrong-remote-recognized" -FailureMessage "wrong remote fixture does not have wrong-remote status"
}

Write-Host "WSL WORKSTATION BOOTSTRAP CONTRACT VALIDATION" -ForegroundColor Cyan
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
