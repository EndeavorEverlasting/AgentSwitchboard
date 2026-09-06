[CmdletBinding()]
param(
    [string]$RootPath = (Join-Path $PSScriptRoot "..")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Check {
    param([bool]$Condition, [string]$Name, [string]$Message)
    if ($Condition) { [void]$passes.Add($Name) } else { [void]$failures.Add("$Name`: $Message") }
}

$policyPath = Join-Path $RootPath "thinker-route.policy.json"
$routePath = Join-Path $RootPath "Thinker.Route.ps1"
$launcherPath = Join-Path $RootPath "Start-AgentSwitchboardThinker.ps1"
foreach ($path in @($policyPath, $routePath, $launcherPath)) {
    Check (Test-Path -LiteralPath $path -PathType Leaf) "required/$([IO.Path]::GetFileName($path))" "file missing"
}

$policy = Get-Content -LiteralPath $policyPath -Raw | ConvertFrom-Json
Check ($policy.schema -eq "agentswitchboard.thinker-route-policy.v1") "policy/schema" "unexpected schema"
$standard = @($policy.chains.standard) -join ","
$free = @($policy.chains.free) -join ","
Check ($standard -eq "claude,codex,deepseek,opencode-muse,opencode-nemotron,opencode-big-pickle") "policy/standard-order" "standard thinker priority changed: $standard"
Check ($free -eq "opencode-muse,opencode-nemotron,opencode-big-pickle") "policy/free-order" "free thinker priority changed: $free"

$routesById = @{}
foreach ($route in @($policy.routes)) { $routesById[[string]$route.id] = $route }
foreach ($routeId in @($policy.chains.free)) {
    Check ($routesById[[string]$routeId].costClass -eq "free") "policy/free-cost/$routeId" "free chain contains a non-free route"
}
Check ($routesById["deepseek"].model -eq "deepseek/deepseek-v4-pro") "policy/deepseek-model" "DeepSeek route no longer matches reviewed provider route"
Check ($routesById["opencode-muse"].model -eq "opencode/muse-spark-1.3-contributor-free") "policy/muse-free-model" "Muse free route changed"

foreach ($scriptPath in @($routePath, $launcherPath)) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    Check ($errors.Count -eq 0) "parse/$([IO.Path]::GetFileName($scriptPath))" (($errors | ForEach-Object Message) -join "; ")
}

. $routePath
$allFalse = @{
    claude = $false; codex = $false; deepseek = $false; 'opencode-muse' = $false; 'opencode-nemotron' = $false; 'opencode-big-pickle' = $false
}
$codexReady = $allFalse.Clone(); $codexReady["codex"] = $true
$resolved = Resolve-AgentSwitchboardThinkerRoute -Mode Standard -PolicyPath $policyPath -ReadinessOverride $codexReady
Check ($resolved.status -eq "selected") "resolve/standard-selected" "standard resolver did not select a route"
Check ($resolved.route.id -eq "codex") "resolve/standard-fallback" "expected Codex after unavailable Claude, got $($resolved.route.id)"

$freeReady = $allFalse.Clone(); $freeReady["opencode-muse"] = $true; $freeReady["codex"] = $true
$resolvedFree = Resolve-AgentSwitchboardThinkerRoute -Mode Free -PolicyPath $policyPath -ReadinessOverride $freeReady
Check ($resolvedFree.route.id -eq "opencode-muse") "resolve/free-ignores-paid" "free mode did not select Muse first"

$blocked = Resolve-AgentSwitchboardThinkerRoute -Mode Standard -PolicyPath $policyPath -ReadinessOverride $allFalse
Check ($blocked.status -eq "blocked") "resolve/blocked-explicit" "no-route state is not explicit"
Check (@($blocked.skipped).Count -eq 6) "resolve/blocked-evidence" "blocked result does not preserve every skipped route"

$launcherText = Get-Content -LiteralPath $launcherPath -Raw
Check ($launcherText.Contains('"--sandbox", "read-only"')) "launcher/codex-read-only" "Codex thinker is not pinned read-only"
Check ($launcherText.Contains('"--permission-mode", "plan"')) "launcher/claude-plan-mode" "Claude thinker is not pinned to plan permissions"
Check ($launcherText.Contains('''*'' = "deny"')) "launcher/opencode-deny-default" "OpenCode thinker does not deny tools by default"
Check ($launcherText.Contains('MaxObjectiveChars')) "launcher/objective-cap" "objective context is unbounded"
Check ($launcherText.Contains('MaxPlanChars')) "launcher/plan-cap" "plan output is unbounded"
Check ($launcherText.Contains('$maxArgvPromptChars = 28000')) "launcher/windows-argv-bound" "argv-based thinker prompt is not bounded for Windows"
Check ($launcherText.Contains('prompt exceeds safe Windows argv cap for this runner')) "launcher/windows-argv-fallback" "oversized argv prompts do not fall through deterministically"
Check ($launcherText.Contains('objectiveSha256')) "launcher/input-digest" "thinker evidence does not identify source objective"
Check ($launcherText.Contains('planSha256')) "launcher/output-digest" "thinker evidence does not identify plan artifact"
Check ($launcherText.Contains('model preflight threw')) "launcher/preflight-exception-fallback" "provider preflight exceptions can abort the fallback chain"
Check (-not $launcherText.Contains('git push')) "launcher/no-push" "thinker launcher contains push behavior"
Check (-not $launcherText.Contains('git commit')) "launcher/no-commit" "thinker launcher contains commit behavior"

Write-Host "DETERMINISTIC THINKER ROUTE CONTRACTS" -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ""
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
