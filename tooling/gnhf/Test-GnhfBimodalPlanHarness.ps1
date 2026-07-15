[CmdletBinding()]
param(
    [string]$RootPath = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("agent-switchboard-bimodal-plan-{0}" -f [guid]::NewGuid().ToString("N"))
$repoPath = Join-Path $tempRoot "target"
$installRoot = Join-Path $tempRoot "install"
$objectivePath = Join-Path $tempRoot "objective.md"
$snapshotPath = Join-Path $tempRoot "usage.json"
$configPath = Join-Path $tempRoot "bimodal.json"

function Invoke-GitChecked {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $output = & git -C $repoPath @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed:`n$($output -join [Environment]::NewLine)"
    }
    return @($output)
}

try {
    New-Item -ItemType Directory -Path $repoPath, $installRoot -Force | Out-Null
    & git init $repoPath | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "git init failed" }
    [void](Invoke-GitChecked -Arguments @("config", "user.name", "AgentSwitchboard Fixture"))
    [void](Invoke-GitChecked -Arguments @("config", "user.email", "fixture@example.invalid"))
    Set-Content -LiteralPath (Join-Path $repoPath "README.md") -Value "fixture" -Encoding utf8NoBOM
    [void](Invoke-GitChecked -Arguments @("add", "README.md"))
    [void](Invoke-GitChecked -Arguments @("commit", "-m", "test: create disposable scheduler target"))
    $headBefore = ((Invoke-GitChecked -Arguments @("rev-parse", "HEAD")) | Select-Object -First 1).Trim()

    Set-Content -LiteralPath $objectivePath -Encoding utf8NoBOM -Value @'
Improve one bounded fixture concern, validate it, and stop without broadening scope.
'@
    Copy-Item -LiteralPath (Join-Path $RootPath "fixtures\gnhf-usage-completion.json") -Destination $snapshotPath
    Copy-Item -LiteralPath (Join-Path $RootPath "Start-GnhfSprint.ps1") -Destination (Join-Path $installRoot "Start-GnhfSprint.ps1")
    [ordered]@{
        schemaVersion = 1
        installedAt = (Get-Date).ToString("o")
        installRoot = $installRoot
        gnhf = [ordered]@{ commandPath = "fixture-gnhf"; versionOutput = "fixture" }
        agents = [ordered]@{}
        safety = [ordered]@{}
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $installRoot "state.json") -Encoding utf8NoBOM

    $config = Get-Content -LiteralPath (Join-Path $RootPath "gnhf-bimodal.example.json") -Raw | ConvertFrom-Json -Depth 40
    $config.repoPath = $repoPath
    $config.objectivePath = $objectivePath
    $config.usageSnapshotPath = $snapshotPath
    $config.session.worktreeRoot = Join-Path $tempRoot "worktrees"
    $config | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $configPath -Encoding utf8NoBOM

    $scheduler = Join-Path $RootPath "Invoke-GnhfBimodalScheduler.ps1"
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source

    & $pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $scheduler -ConfigPath $configPath -InstallRoot $installRoot -PlanOnly
    if ($LASTEXITCODE -ne 0) { throw "completion plan failed with exit code $LASTEXITCODE" }
    $completionDecision = Get-ChildItem -LiteralPath (Join-Path $installRoot "bimodal-runs") -Filter "routing-decision-000.json" -File -Recurse |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $completionDecision) { throw "completion routing decision was not generated" }
    $completion = Get-Content -LiteralPath $completionDecision.FullName -Raw | ConvertFrom-Json -Depth 20
    if ($completion.mode -ne "maximize-sprint-completion" -or $completion.selectedProfile.profileId -ne "opencode-primary") {
        throw "completion mode selected an unexpected profile"
    }
    if ($completion.selectedAgent -ne "opencode" -or $completion.selectedModel -ne "configured-primary-model" -or [long]$completion.tokenAvailability -ne 900000) {
        throw "completion routing decision did not expose runtime-compatible agent, model, and token fields"
    }
    if ($completion.switchReason -ne $completion.reason) {
        throw "completion routing decision switchReason diverged from the policy reason"
    }

    & $pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $scheduler -ConfigPath $configPath -InstallRoot $installRoot -Mode maximize-token-efficiency -UsageSnapshotPath (Join-Path $RootPath "fixtures\gnhf-usage-efficiency.json") -PlanOnly
    if ($LASTEXITCODE -ne 0) { throw "efficiency plan failed with exit code $LASTEXITCODE" }
    $efficiencyDecision = Get-ChildItem -LiteralPath (Join-Path $installRoot "bimodal-runs") -Filter "routing-decision-000.json" -File -Recurse |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    $efficiency = Get-Content -LiteralPath $efficiencyDecision.FullName -Raw | ConvertFrom-Json -Depth 20
    if ($efficiency.mode -ne "maximize-token-efficiency" -or $efficiency.selectedProfile.profileId -ne "goose-efficient") {
        throw "efficiency mode selected an unexpected profile"
    }
    if ($efficiency.selectedAgent -ne "goose" -or $efficiency.selectedModel -ne "configured-efficient-model" -or [long]$efficiency.tokenAvailability -ne 600000) {
        throw "efficiency routing decision did not expose runtime-compatible agent, model, and token fields"
    }
    if ([long]$efficiency.segmentBudget -ne 75000) {
        throw "efficiency segment budget was not reserve-aware: $($efficiency.segmentBudget)"
    }

    $headAfter = ((Invoke-GitChecked -Arguments @("rev-parse", "HEAD")) | Select-Object -First 1).Trim()
    $statusAfter = @((Invoke-GitChecked -Arguments @("status", "--porcelain=v1")) | Where-Object { $_ })
    $worktreeCount = @((Invoke-GitChecked -Arguments @("worktree", "list", "--porcelain")) | Where-Object { $_ -like "worktree *" }).Count
    if ($headAfter -ne $headBefore -or $statusAfter.Count -ne 0 -or $worktreeCount -ne 1) {
        throw "plan mode mutated the target repository or created a worktree"
    }

    Write-Host "PASS: bimodal plan harness" -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
