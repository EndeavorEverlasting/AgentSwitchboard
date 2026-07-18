[CmdletBinding()]
param(
    [string]$RootPath = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Check {
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

function Get-RequiredText {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [void]$failures.Add("required-file/$RelativePath`: file is missing")
        return $null
    }
    return Get-Content -LiteralPath $path -Raw
}

$setup = Get-RequiredText "Setup-AgentSwitchboard.ps1"
$setupCmd = Get-RequiredText "Setup-AgentSwitchboard.cmd"
$operator = Get-RequiredText "Start-AgentSwitchboard.ps1"
$prompt = Get-RequiredText "prompts/hermes-implementation.md"

if ($null -ne $setup) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $RootPath "Setup-AgentSwitchboard.ps1"),
        [ref]$tokens,
        [ref]$parseErrors
    )
    Add-Check -Passed ($parseErrors.Count -eq 0) -Name "setup/powershell-parse" -FailureMessage (($parseErrors | ForEach-Object { $_.Message }) -join "; ")

    Add-Check -Passed ($setup.Contains('https://hermes-agent.nousresearch.com/install.ps1')) -Name "setup/official-hermes-installer" -FailureMessage "official Hermes installer URL is missing"
    Add-Check -Passed ($setup.Contains('Start-Transcript -LiteralPath $transcriptPath')) -Name "setup/transcript" -FailureMessage "setup transcript is not started"
    Add-Check -Passed ($setup.Contains('setup-summary.json')) -Name "setup/json-summary" -FailureMessage "setup summary JSON is not written"
    Add-Check -Passed ($setup.Contains('ReadToEndAsync()')) -Name "setup/async-probe-drain" -FailureMessage "probe output is not drained asynchronously"
    Add-Check -Passed ($setup.Contains('@("acp", "--help")')) -Name "setup/hermes-acp-probe" -FailureMessage "Hermes ACP capability is not probed"
    Add-Check -Passed ($setup.Contains('agentSpec = "acp:hermes acp"')) -Name "setup/hermes-agent-spec" -FailureMessage "Hermes ACP agent specification is missing"
    Add-Check -Passed ($setup.Contains('Add-Member -NotePropertyName "hermes"')) -Name "setup/hermes-state-record" -FailureMessage "Hermes readiness is not persisted in state.json"
    Add-Check -Passed ($setup.Contains('Core fleet setup will continue and Hermes will be recorded as BLOCKED')) -Name "setup/graceful-hermes-failure" -FailureMessage "Hermes installation failure can abort the entire setup"
    Add-Check -Passed ($setup.Contains('Test-GnhfFleetContracts.ps1')) -Name "setup/core-validator" -FailureMessage "core validator is not executed"
    Add-Check -Passed ($setup.Contains('Test-HermesSetupContracts.ps1')) -Name "setup/hermes-validator" -FailureMessage "Hermes validator is not executed"
    Add-Check -Passed ($setup.Contains('"gnhf-fleet.example.json"')) -Name "setup/preserves-manifest-template" -FailureMessage "repeat setup from the installed directory can lose the manifest template"
    Add-Check -Passed ($setup.Contains('Copy-SetupFile')) -Name "setup/idempotent-copy" -FailureMessage "setup bundle is not copied with a self-copy guard"
}

if ($null -ne $setupCmd) {
    Add-Check -Passed ($setupCmd.Contains('where pwsh')) -Name "cmd/pwsh-preflight" -FailureMessage "click launcher does not verify PowerShell 7"
    Add-Check -Passed ($setupCmd.Contains('Setup-AgentSwitchboard.ps1')) -Name "cmd/delegates-to-setup" -FailureMessage "click launcher does not invoke the setup orchestrator"
    Add-Check -Passed ($setupCmd.Contains('-InstallOpenCodeAndCopilot')) -Name "cmd/installs-native-agents" -FailureMessage "click launcher does not request native agent installation/repair"
    Add-Check -Passed ($setupCmd.Contains('setup-logs')) -Name "cmd/log-guidance" -FailureMessage "failure output does not point to logs"
    Add-Check -Passed ($setupCmd.Contains('pause')) -Name "cmd/remains-visible" -FailureMessage "double-clicked window can close before the operator sees the result"
    Add-Check -Passed ($setupCmd.Contains('exit /b %_code%')) -Name "cmd/preserves-exit-code" -FailureMessage "launcher does not preserve the setup exit code"
}

if ($null -ne $operator) {
    Add-Check -Passed ($operator.Contains('[ValidateSet("opencode", "deepseek", "goose", "agy", "copilot", "hermes")]')) -Name "operator/hermes-allowed" -FailureMessage "operator ValidateSet does not preserve Hermes while adding provider aliases"
    Add-Check -Passed ($operator.Contains('@("opencode", "deepseek", "goose", "agy", "copilot", "hermes")')) -Name "operator/hermes-readiness" -FailureMessage "readiness output omits Hermes"
    Add-Check -Passed ($operator.Contains('hermes = "hermes-implementation.md"')) -Name "operator/hermes-prompt" -FailureMessage "Hermes default prompt mapping is missing"
    Add-Check -Passed ($operator.Contains('Setup-AgentSwitchboard.ps1')) -Name "operator/bootstrap-delegates-to-robust-setup" -FailureMessage "bootstrap bypasses the robust setup and can erase Hermes state"
    Add-Check -Passed ($operator.Contains('Setup logs:')) -Name "operator/setup-log-discovery" -FailureMessage "readiness output does not reveal setup log location"
}

if ($null -ne $prompt) {
    Add-Check -Passed ($prompt.Contains('LANE: Hermes implementation')) -Name "prompt/lane" -FailureMessage "Hermes lane is not named"
    Add-Check -Passed ($prompt.Contains('OWNED SCOPE:')) -Name "prompt/owned-scope" -FailureMessage "owned scope is missing"
    Add-Check -Passed ($prompt.Contains('FORBIDDEN SCOPE:')) -Name "prompt/forbidden-scope" -FailureMessage "forbidden scope is missing"
    Add-Check -Passed ($prompt.Contains('VALIDATION:')) -Name "prompt/validation" -FailureMessage "validation contract is missing"
    Add-Check -Passed ($prompt.Contains('STOP ONLY WHEN:')) -Name "prompt/stop-condition" -FailureMessage "observable stop condition is missing"
}

Write-Host "HERMES SETUP CONTRACT VALIDATION" -ForegroundColor Cyan
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
