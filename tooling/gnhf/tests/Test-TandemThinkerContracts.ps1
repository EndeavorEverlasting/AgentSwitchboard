[CmdletBinding()]
param([string]$RootPath = (Join-Path $PSScriptRoot ".."))

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$runnerPath = Join-Path $RootPath "Start-AgentSwitchboardTandemThinkers.ps1"
$cmdPath = Join-Path $RootPath "Start-AgentSwitchboardTandemThinkers.cmd"
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()
function Check { param([bool]$Condition,[string]$Name,[string]$Message) if ($Condition) { [void]$passes.Add($Name) } else { [void]$failures.Add("$Name`: $Message") } }

foreach ($path in @($runnerPath,$cmdPath)) { Check (Test-Path -LiteralPath $path -PathType Leaf) "required/$([IO.Path]::GetFileName($path))" "file missing" }
$tokens=$null; $errors=$null
[void][Management.Automation.Language.Parser]::ParseFile($runnerPath,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) "parse/tandem-runner" (($errors | ForEach-Object Message) -join "; ")

$runnerText = Get-Content -LiteralPath $runnerPath -Raw
$startIndex = $runnerText.IndexOf('foreach ($lane in $laneSpecs) { [void]$running.Add((Start-TandemLane -Lane $lane)) }')
$waitIndex = $runnerText.IndexOf('foreach ($lane in $running) { [void]$completed.Add((Complete-TandemLane -RunningLane $lane)) }')
Check ($startIndex -ge 0 -and $waitIndex -gt $startIndex) "parallel/start-all-before-wait" "runner can wait before both lanes have been started"
Check ($runnerText.Contains('launchStrategy = "start-all-before-wait"')) "parallel/receipt-strategy" "receipt does not identify concurrency strategy"
Check ($runnerText.Contains('parallelLaunchCount = 2')) "parallel/lane-count" "receipt does not pin the two-lane fan-out"
Check ($runnerText.Contains('TANDEM_PARALLELISM_NOT_OBSERVED')) "parallel/overlap-gate" "runner can claim tandem success without observed lifetime overlap"
Check ($runnerText.Contains('TANDEM_ROUTE_COLLISION')) "parallel/distinct-route-gate" "duplicate thinker identity is not rejected"
Check ($runnerText.Contains('mutationAuthority = "none-read-only-advisories"')) "safety/read-only-authority" "receipt does not deny mutation authority"
Check ($runnerText.Contains('downstreamWriterContract = "exactly-one-writer-after-deterministic-rejoin"')) "safety/one-writer-rejoin" "one-writer contract missing from receipt"
Check (-not $runnerText.Contains('Start-AgentSwitchboard.ps1')) "safety/no-builder-dispatch" "advisory runner dispatches a writer"
Check (-not $runnerText.Contains('Start-GnhfSprint.ps1')) "safety/no-gnhf-writer" "advisory runner invokes the GNHF writer"
Check ($runnerText.Contains('Reconcile conflicts against current repository evidence')) "rejoin/evidence-precedence" "builder handoff lacks conflict-to-evidence rule"
Check ($runnerText.Contains('Do not infer consensus merely because both advisers agree.')) "rejoin/no-agreement-as-proof" "agreement can be promoted to proof"

$cmdText = Get-Content -LiteralPath $cmdPath -Raw
Check ($cmdText.Contains('Start-AgentSwitchboardTandemThinkers.ps1')) "cmd/delegates" "CMD launcher target mismatch"
Check ($cmdText.Contains('exit /b %_code%')) "cmd/exit-code" "CMD launcher does not preserve exit code"

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("agentswitchboard-tandem-test-" + [guid]::NewGuid().ToString("N"))
$repoPath = Join-Path $tempRoot "repo"
$installRoot = Join-Path $tempRoot "fleet"
$objectivePath = Join-Path $tempRoot "objective.md"
$fakeThinker = Join-Path $tempRoot "fake-thinker.ps1"
$collisionThinker = Join-Path $tempRoot "collision-thinker.ps1"
New-Item -ItemType Directory -Path $repoPath,$installRoot -Force | Out-Null
Set-Content -LiteralPath $objectivePath -Value "Implement a bounded synthetic change." -Encoding utf8NoBOM

$fakeSource = @'
param(
    [string]$RepoPath,
    [string]$PromptPath,
    [ValidateSet("Auto","Standard","Free")][string]$Mode,
    [string]$OutputPath,
    [int]$MaxPlanChars,
    [int]$TimeoutSeconds,
    [string]$InstallRoot
)
Start-Sleep -Milliseconds 1200
$route = if ($Mode -eq "Standard") { "fixture-standard" } else { "fixture-free" }
Set-Content -LiteralPath $OutputPath -Value ("# SYSTEM PLAN`nmode=" + $Mode + "`nroute=" + $route) -Encoding utf8NoBOM
Write-Host "THINKER ROUTE COMPLETE"
Write-Host "Mode:     $Mode"
Write-Host "Thinker:  $route"
Write-Host "Plan:     $OutputPath"
exit 0
'@
Set-Content -LiteralPath $fakeThinker -Value $fakeSource -Encoding utf8NoBOM

$collisionSource = $fakeSource -replace '\$route = if \(\$Mode -eq "Standard"\) \{ "fixture-standard" \} else \{ "fixture-free" \}', '$route = "fixture-collision"'
Set-Content -LiteralPath $collisionThinker -Value $collisionSource -Encoding utf8NoBOM

try {
    $successPlan = Join-Path $tempRoot "TANDEM_PLAN.md"
    $successReceipt = Join-Path $tempRoot "tandem-receipt.json"
    & pwsh -NoLogo -NoProfile -NonInteractive -File $runnerPath `
        -RepoPath $repoPath `
        -PromptPath $objectivePath `
        -OutputPath $successPlan `
        -ReceiptPath $successReceipt `
        -MaxPlanCharsPerLane 4000 `
        -MaxCombinedPlanChars 12000 `
        -LaneTimeoutSeconds 10 `
        -InstallRoot $installRoot `
        -ThinkerLauncherPath $fakeThinker *> $null
    $successExit = $LASTEXITCODE
    Check ($successExit -eq 0) "runtime/synthetic-exit" "synthetic tandem run exited $successExit"
    Check (Test-Path -LiteralPath $successReceipt -PathType Leaf) "runtime/receipt-created" "synthetic tandem receipt missing"
    Check (Test-Path -LiteralPath $successPlan -PathType Leaf) "runtime/rejoin-created" "synthetic tandem plan missing"
    if (Test-Path -LiteralPath $successReceipt -PathType Leaf) {
        $receipt = Get-Content -LiteralPath $successReceipt -Raw | ConvertFrom-Json
        Check ($receipt.schema -eq "agentswitchboard.tandem-thinkers.v1") "runtime/schema" "unexpected receipt schema"
        Check ($receipt.status -eq "success") "runtime/status" "synthetic tandem run did not report success"
        Check ([bool]$receipt.overlapObserved) "runtime/overlap-observed" "two sleeping fixture lanes did not overlap"
        Check (@($receipt.lanes).Count -eq 2) "runtime/two-lanes" "receipt did not preserve two lane records"
        $routes = @($receipt.lanes | ForEach-Object { [string]$_.selectedRoute })
        Check (@($routes | Select-Object -Unique).Count -eq 2) "runtime/distinct-routes" "fixture lanes were not independently attributed"
        Check ($receipt.outputSha256 -match '^[a-f0-9]{64}$') "runtime/rejoin-digest" "rejoined plan digest missing"
    }
    if (Test-Path -LiteralPath $successPlan -PathType Leaf) {
        $planText = Get-Content -LiteralPath $successPlan -Raw
        Check ($planText.Contains('route: fixture-standard')) "runtime/standard-attribution" "standard attribution missing from rejoin"
        Check ($planText.Contains('route: fixture-free')) "runtime/free-attribution" "free attribution missing from rejoin"
        Check ($planText.Contains('exactly one downstream writer')) "runtime/one-writer-handoff" "rejoin does not reserve one downstream writer"
    }

    $collisionReceipt = Join-Path $tempRoot "collision-receipt.json"
    & pwsh -NoLogo -NoProfile -NonInteractive -File $runnerPath `
        -RepoPath $repoPath `
        -PromptPath $objectivePath `
        -OutputPath (Join-Path $tempRoot "collision-plan.md") `
        -ReceiptPath $collisionReceipt `
        -MaxPlanCharsPerLane 4000 `
        -MaxCombinedPlanChars 12000 `
        -LaneTimeoutSeconds 10 `
        -InstallRoot $installRoot `
        -ThinkerLauncherPath $collisionThinker *> $null
    $collisionExit = $LASTEXITCODE
    Check ($collisionExit -ne 0) "runtime/collision-fails" "duplicate route attribution returned success"
    if (Test-Path -LiteralPath $collisionReceipt -PathType Leaf) {
        $collision = Get-Content -LiteralPath $collisionReceipt -Raw | ConvertFrom-Json
        Check ($collision.failureCode -eq "TANDEM_ROUTE_COLLISION") "runtime/collision-code" "route collision did not emit the typed failure"
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "TANDEM THINKER CONTRACTS" -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ""
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count,$failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
