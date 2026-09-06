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
$processPath = Join-Path $RootPath "Gnhf.Process.ps1"
$launcherPath = Join-Path $RootPath "Start-AgentSwitchboardThinker.ps1"
$cmdPath = Join-Path $RootPath "Start-AgentSwitchboardThinker.cmd"
$setupPath = Join-Path $RootPath "Setup-AgentSwitchboard.ps1"
$rateExamplePath = Join-Path $RootPath "deepseek-usage-windows.example.json"
foreach ($path in @($policyPath, $routePath, $processPath, $launcherPath, $cmdPath, $setupPath, $rateExamplePath)) {
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

$rateExample = Get-Content -LiteralPath $rateExamplePath -Raw | ConvertFrom-Json
Check ($rateExample.schema -eq "agentswitchboard.deepseek-usage-window.v1") "rate/example-schema" "DeepSeek usage template schema mismatch"
Check ($rateExample.verified -eq $false) "rate/example-fail-closed" "DeepSeek usage template must not authorize launches"

foreach ($scriptPath in @($routePath, $processPath, $launcherPath, $setupPath)) {
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

$rateTemp = Join-Path ([IO.Path]::GetTempPath()) ("agentswitchboard-rate-window-{0}.json" -f [guid]::NewGuid().ToString("N"))
$now = [DateTimeOffset]::UtcNow
try {
    [ordered]@{
        schema = "agentswitchboard.deepseek-usage-window.v1"
        verified = $true
        rateClass = "standard"
        effectiveMultiplier = 1.0
        verifiedAt = $now.AddMinutes(-1).ToString("o")
        validUntil = $now.AddMinutes(30).ToString("o")
        source = "contract fixture"
    } | ConvertTo-Json | Set-Content -LiteralPath $rateTemp -Encoding utf8NoBOM
    $rateReady = Test-AgentSwitchboardDeepSeekRateWindow -SchedulePath $rateTemp -Now $now
    Check ($rateReady.ready) "rate/standard-ready" "verified standard window was not eligible: $($rateReady.reason)"

    $double = Get-Content -LiteralPath $rateTemp -Raw | ConvertFrom-Json
    $double.rateClass = "double-usage"
    $double | ConvertTo-Json | Set-Content -LiteralPath $rateTemp -Encoding utf8NoBOM
    $rateDouble = Test-AgentSwitchboardDeepSeekRateWindow -SchedulePath $rateTemp -Now $now
    Check (-not $rateDouble.ready) "rate/double-usage-blocked" "double-usage window was incorrectly eligible"

    $expired = Get-Content -LiteralPath $rateTemp -Raw | ConvertFrom-Json
    $expired.rateClass = "discounted"
    $expired.effectiveMultiplier = 0.5
    $expired.validUntil = $now.AddMinutes(-1).ToString("o")
    $expired | ConvertTo-Json | Set-Content -LiteralPath $rateTemp -Encoding utf8NoBOM
    $rateExpired = Test-AgentSwitchboardDeepSeekRateWindow -SchedulePath $rateTemp -Now $now
    Check (-not $rateExpired.ready) "rate/expired-blocked" "expired window was incorrectly eligible"
}
finally {
    if (Test-Path -LiteralPath $rateTemp) { Remove-Item -LiteralPath $rateTemp -Force }
}
$missingRate = Test-AgentSwitchboardDeepSeekRateWindow -SchedulePath (Join-Path ([IO.Path]::GetTempPath()) ("missing-{0}.json" -f [guid]::NewGuid().ToString("N"))) -Now $now
Check (-not $missingRate.ready) "rate/missing-blocked" "missing schedule was incorrectly eligible"

$launcherText = Get-Content -LiteralPath $launcherPath -Raw
Check ($launcherText.Contains('"--sandbox", "read-only"')) "launcher/codex-read-only" "Codex thinker is not pinned read-only"
Check ($launcherText.Contains('"--permission-mode", "plan"')) "launcher/claude-plan-mode" "Claude thinker is not pinned to plan permissions"
Check ($launcherText.Contains('''*'' = "deny"')) "launcher/opencode-deny-default" "OpenCode thinker does not deny tools by default"
Check ($launcherText.Contains('[ValidateRange(1000, 26000)][int]$MaxObjectiveChars = 24000')) "launcher/objective-cap" "public objective cap can exceed the free-mode transport ceiling"
Check ($launcherText.Contains('MaxPlanChars')) "launcher/plan-cap" "plan output is unbounded"
Check ($launcherText.Contains('$maxArgvPromptChars = 28000')) "launcher/windows-argv-bound" "argv-based thinker prompt is not bounded for Windows"
Check ($launcherText.Contains('Compiled thinker prompt is')) "launcher/windows-argv-fail-closed" "compiled prompt does not fail closed before route selection"
Check ($launcherText.Contains('objectiveSha256')) "launcher/input-digest" "thinker evidence does not identify source objective"
Check ($launcherText.Contains('planSha256')) "launcher/output-digest" "thinker evidence does not identify plan artifact"
Check ($launcherText.Contains('model preflight threw')) "launcher/preflight-exception-fallback" "provider preflight exceptions can abort the fallback chain"
Check ($launcherText.Contains('Test-AgentSwitchboardDeepSeekRateWindow')) "launcher/deepseek-rate-gate" "DeepSeek route bypasses the verified usage-window gate"
Check ($launcherText.Contains('deepseek-usage-windows.json')) "launcher/deepseek-rate-path" "DeepSeek route does not use the canonical runtime schedule path"
Check ($launcherText.Contains('New-GnhfProcessStartInfo')) "launcher/shim-safe-dispatch" "thinker processes do not reuse the Windows shim-safe dispatch helper"
Check ($launcherText.Contains('[guid]::NewGuid().ToString("N")')) "launcher/collision-resistant-run-id" "plan/evidence run identity can collide at timestamp resolution"
Check ($launcherText.Contains('status = "unavailable"')) "launcher/unavailable-route-evidence" "receipts discard higher-priority unavailable routes"
Check ($launcherText.Contains('Add-ThinkerRouteEvidence')) "launcher/one-route-evidence-record" "route evidence is not deduplicated deterministically"
Check (-not $launcherText.Contains('git push')) "launcher/no-push" "thinker launcher contains push behavior"
Check (-not $launcherText.Contains('git commit')) "launcher/no-commit" "thinker launcher contains commit behavior"

$cmdText = Get-Content -LiteralPath $cmdPath -Raw
Check ($cmdText.Contains('Start-AgentSwitchboardThinker.ps1')) "install/cmd-delegates" "installed CMD launcher does not delegate to thinker PowerShell"
Check ($cmdText.Contains('exit /b %_code%')) "install/cmd-exit-code" "installed CMD launcher does not preserve exit code"

$setupText = Get-Content -LiteralPath $setupPath -Raw
foreach ($installedFile in @(
    'Gnhf.Process.ps1',
    'Thinker.Route.ps1',
    'Start-AgentSwitchboardThinker.ps1',
    'Start-AgentSwitchboardThinker.cmd',
    'thinker-route.policy.json',
    'deepseek-usage-windows.example.json',
    'THINKER_ROUTE.md'
)) {
    Check ($setupText.Contains('"' + $installedFile + '"')) "install/setup-copies/$installedFile" "setup does not install $installedFile"
}
Check ($setupText.Contains('tests\Test-ThinkerRouteContracts.ps1')) "install/setup-runs-thinker-validator" "setup does not run the thinker contract validator"
Check ($setupText.Contains('Thinker routing contract validation failed')) "install/setup-fails-closed" "setup does not fail when thinker validation fails"

Write-Host "DETERMINISTIC THINKER ROUTE CONTRACTS" -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ""
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
