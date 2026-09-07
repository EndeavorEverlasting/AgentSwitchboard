[CmdletBinding()]
param([string]$RootPath = (Join-Path $PSScriptRoot ".."))

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()
function Check { param([bool]$Condition,[string]$Name,[string]$Message) if ($Condition) { [void]$passes.Add($Name) } else { [void]$failures.Add("$Name`: $Message") } }

$routePath = Join-Path $RootPath "TokenSaving.Route.ps1"
$loopPath = Join-Path $RootPath "Start-AgentSwitchboardTokenSavingLoop.ps1"
$cmdPath = Join-Path $RootPath "Start-AgentSwitchboardTokenSavingLoop.cmd"
$emergencyPath = Join-Path $RootPath "Start-AgentSwitchboardEmergencyFree.ps1"
$emergencyCmdPath = Join-Path $RootPath "Start-AgentSwitchboardEmergencyFree.cmd"
$gnhfPath = Join-Path $RootPath "Start-GnhfSprint.ps1"
$setupPath = Join-Path $RootPath "Setup-AgentSwitchboard.ps1"
foreach ($path in @($routePath,$loopPath,$cmdPath,$emergencyPath,$emergencyCmdPath,$gnhfPath,$setupPath)) { Check (Test-Path -LiteralPath $path -PathType Leaf) "required/$([IO.Path]::GetFileName($path))" "file missing" }

foreach ($path in @($routePath,$loopPath,$emergencyPath,$gnhfPath,$setupPath)) {
    $tokens=$null; $errors=$null
    [void][Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) "parse/$([IO.Path]::GetFileName($path))" (($errors | ForEach-Object Message) -join "; ")
}

. $routePath
$state = [pscustomobject]@{ agents = [pscustomobject]@{
    agy = [pscustomobject]@{ available=$false; evidence="agy blocked" }
    opencode = [pscustomobject]@{ available=$true; evidence="opencode ready" }
    hermes = [pscustomobject]@{ available=$true; evidence="hermes ready" }
} }
$route = Resolve-AgentSwitchboardBuilderRoute -Requested Auto -State $state
Check ($route.route -eq "opencode") "route/auto-fallback" "expected opencode when agy is unavailable"
Check (@($route.skipped).Count -eq 1) "route/skip-evidence" "auto route did not preserve unavailable AGY evidence"
$explicit = Resolve-AgentSwitchboardBuilderRoute -Requested hermes -State $state
Check ($explicit.route -eq "hermes") "route/explicit" "explicit builder route changed"

$envelope = New-AgentSwitchboardFailureEnvelope -ValidationNumber 2 -ExitCode 1 -TimedOut $false -Output ("x" * 10000) -WorktreePath "C:\repo-wt" -HeadSha ("a" * 40) -MaxFailureChars 6000
Check ($envelope.excerpt.Length -eq 6000) "envelope/excerpt-cap" "failure excerpt is not bounded"
Check ($envelope.outputChars -eq 10000) "envelope/full-size-evidence" "full output size is not retained as evidence"
Check ($envelope.outputSha256 -match '^[a-f0-9]{64}$') "envelope/full-output-digest" "full output digest missing"

$loopText = Get-Content -LiteralPath $loopPath -Raw
Check (([regex]::Matches($loopText,'-File \$thinkerLauncher')).Count -eq 1) "loop/thinker-once" "thinker launcher is not invoked exactly once"
Check ($loopText.Contains('while (($validation.exitCode -ne 0 -or $validation.timedOut)')) "loop/bounded-repair-loop" "repair loop missing"
Check ($loopText.Contains('$repairCycle -lt $MaxRepairCycles')) "loop/repair-cap" "repair loop is unbounded"
Check ($loopText.Contains('New-AgentSwitchboardFailureEnvelope')) "loop/failure-envelope" "raw validation failure is not reduced before builder repair"
Check ($loopText.Contains('The orchestrator will rerun the deterministic validator itself.')) "loop/validator-owned-rerun" "repair agent is asked to own validation authority"
Check (-not $loopText.Contains('-PushBranch')) "loop/no-push" "token-saving orchestrator enables push"
Check (-not $loopText.Contains('git merge')) "loop/no-merge" "token-saving orchestrator contains merge behavior"
Check ($loopText.Contains('newWorktrees.Count -ne 1')) "loop/unambiguous-worktree" "orchestrator can guess among worktrees"
Check ($loopText.Contains('validationCommandSha256')) "loop/validator-command-digest" "validator identity is not recorded"

$emergencyText = Get-Content -LiteralPath $emergencyPath -Raw
Check ($emergencyText.Contains('[ValidateRange(1, 2)][int]$MaxInitialIterations = 2')) "emergency/initial-iteration-cap" "emergency initial iterations can exceed 2"
Check ($emergencyText.Contains('[ValidateRange(0, 1)][int]$MaxRepairCycles = 1')) "emergency/repair-cap" "emergency repair cycles can exceed 1"
Check ($emergencyText.Contains('[ValidateRange(1000, 50000)][int]$MaxTokensPerBuilderRun = 50000')) "emergency/token-cap" "emergency builder token cap can exceed 50000"
Check ($emergencyText.Contains('[ValidateRange(500, 3000)][int]$MaxFailureChars = 3000')) "emergency/failure-cap" "emergency failure envelope can exceed 3000 chars"
Check ($emergencyText.Contains('@($policy.chains.free)')) "emergency/free-policy-chain" "emergency route does not consume the canonical free chain"
Check ($emergencyText.Contains('$route.costClass -ne "free"')) "emergency/free-cost-gate" "emergency route does not reject non-free routes"
Check ($emergencyText.Contains('-ThinkerMode Free')) "emergency/free-thinker" "emergency mode does not force the free thinker chain"
Check ($emergencyText.Contains('-BuilderAgent opencode')) "emergency/opencode-builder" "emergency mode does not force the probed OpenCode builder"
Check ($emergencyText.Contains('OPENCODE_CONFIG_CONTENT')) "emergency/model-pin" "emergency builder does not pin the selected free model"
Check ($emergencyText.Contains('AGENT_SWITCHBOARD_FREE_MODE')) "emergency/free-env" "emergency mode does not set the process free-mode guard"
Check ($emergencyText.Contains('finally {')) "emergency/environment-restore" "emergency environment restoration is not fail-safe"
Check ($emergencyText.Contains('No verified free OpenCode model is currently available')) "emergency/fail-closed" "emergency mode can silently fall back when free models are unavailable"

$gnhfText = Get-Content -LiteralPath $gnhfPath -Raw
Check ($gnhfText.Contains('[switch]$RepairCurrentGnhfBranch')) "repair/guard-switch" "repair mode switch missing"
Check ($gnhfText.Contains('may run only inside an existing gnhf/* worktree')) "repair/gnhf-branch-gate" "repair mode can mutate arbitrary current branches"
Check ($gnhfText.Contains('"--current-branch"')) "repair/current-branch" "repair mode does not use GNHF current-branch execution"
Check ($gnhfText.Contains('"--worktree"')) "repair/default-worktree" "default isolated worktree mode was removed"

$cmdText = Get-Content -LiteralPath $cmdPath -Raw
Check ($cmdText.Contains('Start-AgentSwitchboardTokenSavingLoop.ps1')) "cmd/delegates" "CMD launcher target mismatch"
Check ($cmdText.Contains('exit /b %_code%')) "cmd/exit-code" "CMD launcher does not preserve exit code"
$emergencyCmdText = Get-Content -LiteralPath $emergencyCmdPath -Raw
Check ($emergencyCmdText.Contains('Start-AgentSwitchboardEmergencyFree.ps1')) "emergency-cmd/delegates" "emergency CMD launcher target mismatch"
Check ($emergencyCmdText.Contains('exit /b %_code%')) "emergency-cmd/exit-code" "emergency CMD launcher does not preserve exit code"

$setupText = Get-Content -LiteralPath $setupPath -Raw
foreach ($installedFile in @(
    'TokenSaving.Route.ps1',
    'Start-AgentSwitchboardTokenSavingLoop.ps1',
    'Start-AgentSwitchboardTokenSavingLoop.cmd',
    'Start-AgentSwitchboardEmergencyFree.ps1',
    'Start-AgentSwitchboardEmergencyFree.cmd',
    'TOKEN_SAVING_LOOP.md'
)) {
    Check ($setupText.Contains('"' + $installedFile + '"')) "setup/copies/$installedFile" "normal setup does not install $installedFile"
}
Check ($setupText.Contains('tests\Test-TokenSavingLoopContracts.ps1')) "setup/runs-token-validator" "normal setup does not run the token-saving validator"
Check ($setupText.Contains('Token-saving loop contract validation failed')) "setup/fails-closed" "normal setup does not fail closed on token-saving contract failure"

Write-Host "TOKEN-SAVING LOOP CONTRACTS" -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ""
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count,$failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
