[CmdletBinding()]
param(
    [string]$RootPath = $PSScriptRoot,
    [string]$RepositoryRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [string]$FailureMessage = ""
    )

    if ($Passed) {
        [void]$passes.Add($Name)
    }
    else {
        [void]$failures.Add("$Name`: $FailureMessage")
    }
}

function Get-RequiredText {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        [void]$failures.Add("required-file/$Path`: file is missing")
        return $null
    }
    return Get-Content -LiteralPath $Path -Raw
}

$requiredFiles = @(
    (Join-Path $RepositoryRoot "Configure-NapSprint.cmd"),
    (Join-Path $RepositoryRoot "Start-NapSprint.cmd"),
    (Join-Path $RootPath "Configure-NapSprint.ps1"),
    (Join-Path $RootPath "Start-AgentSwitchboardNap.ps1"),
    (Join-Path $RootPath "Test-NapSprintContracts.ps1"),
    (Join-Path $RootPath "nap-sprint.example.json"),
    (Join-Path $RootPath "README.md")
)

foreach ($file in $requiredFiles) {
    Add-Result -Passed (Test-Path -LiteralPath $file -PathType Leaf) -Name "required-file/$file" -FailureMessage "file is missing"
}

foreach ($file in @(Get-ChildItem -LiteralPath $RootPath -Filter "*.ps1" -File)) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )
    Add-Result `
        -Passed ($parseErrors.Count -eq 0) `
        -Name "powershell-parse/$($file.Name)" `
        -FailureMessage (($parseErrors | ForEach-Object { $_.Message }) -join "; ")
}

$configPath = Join-Path $RootPath "nap-sprint.example.json"
try {
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    Add-Result -Passed ($config.schemaVersion -eq 1) -Name "config/schema-version" -FailureMessage "expected schemaVersion 1"
    Add-Result -Passed ([string]$config.repoPath -eq "__REPO_PATH__") -Name "config/no-machine-local-repo" -FailureMessage "example config must use the placeholder repo path"
    Add-Result -Passed (@($config.preferredAgents).Count -ge 1) -Name "config/agent-order" -FailureMessage "preferredAgents is empty"
    Add-Result -Passed (@($config.preferredAgents) -contains "hermes") -Name "config/hermes-preferred" -FailureMessage "Hermes is absent from the preferred order"
    Add-Result -Passed ([int]$config.maxIterations -ge 1) -Name "config/iteration-cap" -FailureMessage "maxIterations is unbounded or invalid"
    Add-Result -Passed ([int]$config.maxTokens -ge 1) -Name "config/token-cap" -FailureMessage "maxTokens is unbounded or invalid"
    Add-Result -Passed (-not [bool]$config.pushBranch) -Name "config/push-off-by-default" -FailureMessage "example config enables push"
    Add-Result -Passed ([bool]$config.bootstrapIfMissing) -Name "config/setup-repair" -FailureMessage "missing setup is not repairable"
    Add-Result -Passed (-not [string]::IsNullOrWhiteSpace([string]$config.stopWhen)) -Name "config/observable-stop" -FailureMessage "stopWhen is blank"
}
catch {
    Add-Result -Passed $false -Name "config/json-parse" -FailureMessage $_.Exception.Message
}

$configureText = Get-RequiredText -Path (Join-Path $RootPath "Configure-NapSprint.ps1")
if ($null -ne $configureText) {
    Add-Result -Passed ($configureText.Contains('"$env:LOCALAPPDATA\AgentSwitchboard\Nap\nap-sprint.json"')) -Name "configure/local-untracked-config" -FailureMessage "config is not written outside the repository"
    Add-Result -Passed ($configureText.Contains('git -C $resolved rev-parse --is-inside-work-tree')) -Name "configure/git-repo-validation" -FailureMessage "repository is not validated"
    Add-Result -Passed ($configureText.Contains('[bool]$PushBranch = $false')) -Name "configure/push-default-off" -FailureMessage "wizard defaults to push"
    Add-Result -Passed ($configureText.Contains('Allowed: $($allowedAgents -join')) -Name "configure/agent-allowlist" -FailureMessage "agent preference is not allowlisted"
    Add-Result -Passed (-not $configureText.Contains('apiKey')) -Name "configure/no-key-field" -FailureMessage "configuration introduces an API key field"
}

$launcherText = Get-RequiredText -Path (Join-Path $RootPath "Start-AgentSwitchboardNap.ps1")
if ($null -ne $launcherText) {
    Add-Result -Passed ($launcherText.Contains('@("status", "--porcelain=v1")')) -Name "launcher/clean-tree-preflight" -FailureMessage "dirty checkout detection is missing"
    Add-Result -Passed ($launcherText.Contains('Detached HEAD is not allowed')) -Name "launcher/no-detached-head" -FailureMessage "detached HEAD is not rejected"
    Add-Result -Passed ($launcherText.Contains('Get-Clipboard -Raw')) -Name "launcher/clipboard-prompt" -FailureMessage "clipboard prompt mode is missing"
    Add-Result -Passed ($launcherText.Contains('Get-TextSha256')) -Name "launcher/prompt-hash" -FailureMessage "prompt identity is not hashed"
    Add-Result -Passed ($launcherText.Contains('promptSha256 = $null')) -Name "launcher/no-prompt-text-in-summary" -FailureMessage "summary prompt hash field is missing"
    Add-Result -Passed ($launcherText.Contains('Get-AgentSelection')) -Name "launcher/readiness-selection" -FailureMessage "ready-agent selection is missing"
    Add-Result -Passed ($launcherText.Contains('No configured agent is ready')) -Name "launcher/blocked-agent-evidence" -FailureMessage "all-blocked state is not explicit"
    Add-Result -Passed ($launcherText.Contains('Setup-AgentSwitchboard.ps1')) -Name "launcher/setup-repair-path" -FailureMessage "missing setup cannot be repaired"
    Add-Result -Passed ($launcherText.Contains('PlanOnly will not install software')) -Name "launcher/plan-only-no-install" -FailureMessage "PlanOnly can trigger installation"
    Add-Result -Passed ($launcherText.Contains('"-PromptPath", $runtimePromptPath')) -Name "launcher/prompt-file-boundary" -FailureMessage "child process does not receive an ephemeral prompt file"
    Add-Result -Passed (-not $launcherText.Contains('"-Prompt", $objective')) -Name "launcher/no-prompt-argv" -FailureMessage "full prompt is placed on Windows argv"
    Add-Result -Passed ($launcherText.Contains('Remove-Item -LiteralPath $runtimePromptPath')) -Name "launcher/ephemeral-prompt-cleanup" -FailureMessage "temporary prompt is not deleted"
    Add-Result -Passed ($launcherText.Contains('Automatic failover is disabled after execution begins')) -Name "launcher/no-unsafe-runtime-failover" -FailureMessage "runtime failover boundary is absent"
    Add-Result -Passed ($launcherText.Contains('preventSleep = $true')) -Name "launcher/prevent-sleep-evidence" -FailureMessage "prevent-sleep contract is absent"
    Add-Result -Passed ($launcherText.Contains('nap-summary.json')) -Name "launcher/json-summary" -FailureMessage "JSON summary is missing"
    Add-Result -Passed ($launcherText.Contains('nap-transcript.txt')) -Name "launcher/transcript" -FailureMessage "transcript is missing"
    Add-Result -Passed ($launcherText.Contains('if ([bool]$config.pushBranch)')) -Name "launcher/explicit-push" -FailureMessage "push is not gated by config"
}

$startCmd = Get-RequiredText -Path (Join-Path $RepositoryRoot "Start-NapSprint.cmd")
if ($null -ne $startCmd) {
    Add-Result -Passed ($startCmd.Contains('where pwsh')) -Name "cmd/pwsh-preflight" -FailureMessage "PowerShell 7 presence is not checked"
    Add-Result -Passed ($startCmd.Contains('Configure-NapSprint.ps1')) -Name "cmd/first-run-config" -FailureMessage "missing config is not repaired"
    Add-Result -Passed ($startCmd.Contains('Start-AgentSwitchboardNap.ps1')) -Name "cmd/delegates-launch" -FailureMessage "CMD bypasses the nap launcher"
    Add-Result -Passed ($startCmd.Contains('pause')) -Name "cmd/keeps-result-visible" -FailureMessage "double-click window closes immediately"
    Add-Result -Passed ($startCmd.Contains('exit /b %_code%')) -Name "cmd/preserves-exit-code" -FailureMessage "exit code is not preserved"
}

Write-Host "NAP SPRINT CONTRACT VALIDATION" -ForegroundColor Cyan
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
