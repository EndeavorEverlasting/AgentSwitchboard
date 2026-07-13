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
        [Parameter(Mandatory)][string]$FailureMessage
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
    if (-not (Test-Path -LiteralPath $path)) {
        [void]$failures.Add("required-file/$RelativePath`: file is missing")
        return $null
    }

    return Get-Content -LiteralPath $path -Raw
}

$requiredFiles = @(
    "Install-AgentSwitchboardGnhf.ps1",
    "Install-AgentSwitchboardWorkstation.ps1",
    "Start-AgentSwitchboard.ps1",
    "Start-GnhfSprint.ps1",
    "Start-GnhfFleet.ps1",
    "Get-GnhfFleetStatus.ps1",
    "Test-GnhfFleetContracts.ps1",
    "gnhf-fleet.example.json",
    "README.md"
)

foreach ($relativePath in $requiredFiles) {
    Add-CheckResult `
        -Passed (Test-Path -LiteralPath (Join-Path $RootPath $relativePath)) `
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

$manifestPath = Join-Path $RootPath "gnhf-fleet.example.json"
try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    Add-CheckResult -Passed ($manifest.schemaVersion -eq 1) -Name "manifest/schema-version" -FailureMessage "expected schemaVersion 1"
    Add-CheckResult -Passed ($manifest.sprints.Count -eq 4) -Name "manifest/sprint-count" -FailureMessage "expected four defined sprint lanes"

    foreach ($sprint in $manifest.sprints) {
        $name = [string]$sprint.name
        Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace($name)) -Name "manifest/name" -FailureMessage "a sprint has no name"
        Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace([string]$sprint.agent)) -Name "manifest/$name/agent" -FailureMessage "agent is missing"
        Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace([string]$sprint.repoPath)) -Name "manifest/$name/repoPath" -FailureMessage "repoPath is missing"
        Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace([string]$sprint.promptPath)) -Name "manifest/$name/promptPath" -FailureMessage "promptPath is missing"
        Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace([string]$sprint.stopWhen)) -Name "manifest/$name/stopWhen" -FailureMessage "observable stop condition is missing"
    }
}
catch {
    [void]$failures.Add("manifest/json`: $($_.Exception.Message)")
}

$installer = Get-FileText "Install-AgentSwitchboardGnhf.ps1"
if ($null -ne $installer) {
    Add-CheckResult -Passed ($installer.Contains("ReadToEndAsync()")) -Name "installer/async-probe-drain" -FailureMessage "redirected output is not drained asynchronously"
    Add-CheckResult -Passed ($installer.Contains('Available = $probeSucceeded')) -Name "installer/probe-gates-readiness" -FailureMessage "command presence can still be mistaken for readiness"
    Add-CheckResult -Passed ($installer.Contains('Test-GnhfFleetContracts.ps1')) -Name "installer/copies-validator" -FailureMessage "contract validator is not installed with the fleet"
}

$workstationInstaller = Get-FileText "Install-AgentSwitchboardWorkstation.ps1"
if ($null -ne $workstationInstaller) {
    Add-CheckResult -Passed ($workstationInstaller.Contains('[string]$InstallProfile = "Core"')) -Name "workstation/core-profile-default" -FailureMessage "fresh workstation bootstrap does not default to the core profile"
    Add-CheckResult -Passed ($workstationInstaller.Contains('@("goose", "opencode", "agy")')) -Name "workstation/core-profile-members" -FailureMessage "core profile does not include goose, opencode, and agy"
    Add-CheckResult -Passed ($workstationInstaller.Contains('https://github.com/aaif-goose/goose/releases/download/stable/download_cli.ps1')) -Name "workstation/goose-official-source" -FailureMessage "Goose official Windows installer is missing"
    Add-CheckResult -Passed ($workstationInstaller.Contains('https://antigravity.google/cli/install.ps1')) -Name "workstation/agy-official-source" -FailureMessage "AGY official Windows installer is missing"
    Add-CheckResult -Passed ($workstationInstaller.Contains('https://claude.ai/install.ps1')) -Name "workstation/claude-official-source" -FailureMessage "Claude recommended Windows installer is missing"
    Add-CheckResult -Passed ($workstationInstaller.Contains('https://chatgpt.com/codex/install.ps1')) -Name "workstation/codex-official-source" -FailureMessage "Codex recommended Windows installer is missing"
    Add-CheckResult -Passed ($workstationInstaller.Contains('opencode-ai@latest')) -Name "workstation/opencode-package" -FailureMessage "OpenCode package is missing"
    Add-CheckResult -Passed ($workstationInstaller.Contains('@github/copilot@latest')) -Name "workstation/copilot-package" -FailureMessage "Copilot CLI package is missing"
    Add-CheckResult -Passed ($workstationInstaller.Contains('@earendil-works/pi-coding-agent@latest')) -Name "workstation/pi-current-package" -FailureMessage "Pi package name is stale or missing"
    Add-CheckResult -Passed ($workstationInstaller.Contains('remoteInstallerPolicy')) -Name "workstation/records-install-policy" -FailureMessage "install evidence does not record the remote installer policy"
    Add-CheckResult -Passed ($workstationInstaller.Contains('agyBoundary')) -Name "workstation/agy-truth-boundary" -FailureMessage "AGY installation can be mistaken for GNHF readiness"
    Add-CheckResult -Passed ($workstationInstaller.Contains('Remove-Item -LiteralPath $tempRoot -Recurse -Force')) -Name "workstation/temp-cleanup" -FailureMessage "downloaded installer cleanup is missing"
}

$operatorLauncher = Get-FileText "Start-AgentSwitchboard.ps1"
if ($null -ne $operatorLauncher) {
    Add-CheckResult -Passed ($operatorLauncher.Contains('[switch]$Bootstrap')) -Name "operator/explicit-bootstrap" -FailureMessage "bootstrap is not explicit"
    Add-CheckResult -Passed ($operatorLauncher.Contains('[switch]$PushBranch')) -Name "operator/explicit-push" -FailureMessage "push is not an explicit switch"
    Add-CheckResult -Passed ($operatorLauncher.Contains('[ValidateRange(1, 1000000000)]')) -Name "operator/requires-token-cap" -FailureMessage "operator permits an unbounded zero token cap"
    Add-CheckResult -Passed ($operatorLauncher.Contains('Start-GnhfSprint.ps1')) -Name "operator/delegates-to-bounded-sprint" -FailureMessage "operator launcher bypasses the bounded sprint launcher"
    Add-CheckResult -Passed ($operatorLauncher.Contains('agent-switchboard.cmd')) -Name "operator/installs-reusable-command" -FailureMessage "reusable command launcher is not installed"
    Add-CheckResult -Passed ($operatorLauncher.Contains('repoName.Equals("AgentSwitchboard"')) -Name "operator/restricts-bundled-prompts" -FailureMessage "AgentSwitchboard-specific prompts can be silently applied to another repo"
    Add-CheckResult -Passed ($operatorLauncher.Contains('Get-Clipboard -Raw')) -Name "operator/external-prompt-guidance" -FailureMessage "external repos do not receive actionable prompt guidance"
    Add-CheckResult -Passed ($operatorLauncher.Contains('opencode-implementation.md')) -Name "operator/default-opencode-prompt" -FailureMessage "OpenCode default prompt is missing"
    Add-CheckResult -Passed ($operatorLauncher.Contains('goose-validation.md')) -Name "operator/default-goose-prompt" -FailureMessage "Goose default prompt is missing"
    Add-CheckResult -Passed ($operatorLauncher.Contains('agy-architecture.md')) -Name "operator/default-agy-prompt" -FailureMessage "AGY default prompt is missing"
    Add-CheckResult -Passed ($operatorLauncher.Contains('copilot-tests.md')) -Name "operator/default-copilot-prompt" -FailureMessage "Copilot default prompt is missing"
    Add-CheckResult -Passed (-not $operatorLauncher.Contains('PushBranch = $true')) -Name "operator/no-default-push" -FailureMessage "branch push is enabled by default"
    Add-CheckResult -Passed ($operatorLauncher.Contains('Install-AgentSwitchboardWorkstation.ps1')) -Name "operator/workstation-bootstrap" -FailureMessage "operator bootstrap does not install workstation agents"
    Add-CheckResult -Passed ($operatorLauncher.Contains('[string]$InstallProfile = "Core"')) -Name "operator/core-install-profile" -FailureMessage "operator does not expose the safe core install profile"
    Add-CheckResult -Passed (-not $operatorLauncher.Contains('$Bootstrap -and -not (Test-Path')) -Name "operator/bootstrap-refreshes-state" -FailureMessage "bootstrap cannot install missing agents after state already exists"
    Add-CheckResult -Passed ($operatorLauncher.Contains('@("claude", "codex", "pi")')) -Name "operator/native-agent-expansion" -FailureMessage "installed native GNHF agents cannot be launched"
}

$sprintLauncher = Get-FileText "Start-GnhfSprint.ps1"
if ($null -ne $sprintLauncher) {
    Add-CheckResult -Passed ($sprintLauncher.Contains('$objective | & $gnhfPath @gnhfArguments')) -Name "sprint/stdin-prompt" -FailureMessage "prompt is not streamed through stdin"
    Add-CheckResult -Passed (-not $sprintLauncher.Contains('[void]$gnhfArguments.Add($objective)')) -Name "sprint/no-prompt-argv" -FailureMessage "prompt is still appended to argv"
    Add-CheckResult -Passed ($sprintLauncher.Contains('Write-Error -ErrorRecord $_ -ErrorAction Continue')) -Name "sprint/controlled-error-path" -FailureMessage "catch block can terminate before the explicit exit path"
}

$fleetLauncher = Get-FileText "Start-GnhfFleet.ps1"
if ($null -ne $fleetLauncher) {
    Add-CheckResult -Passed ($fleetLauncher.Contains('if ($Wait -and $KeepWindowsOpen)')) -Name "fleet/rejects-deadlock-flags" -FailureMessage "-Wait and -KeepWindowsOpen can still be combined"
    Add-CheckResult -Passed ($fleetLauncher.Contains('New-Item -ItemType Directory -Path $reportsRoot -Force')) -Name "fleet/recreates-report-directory" -FailureMessage "launch report directory is not recreated"
}

$statusReporter = Get-FileText "Get-GnhfFleetStatus.ps1"
if ($null -ne $statusReporter) {
    Add-CheckResult -Passed ($statusReporter.Contains('New-Item -ItemType Directory -Path $reportsRoot -Force')) -Name "status/recreates-report-directory" -FailureMessage "morning report directory is not recreated"
}

Write-Host "GNHF FLEET CONTRACT VALIDATION" -ForegroundColor Cyan
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
