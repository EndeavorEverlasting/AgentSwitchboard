[CmdletBinding()]
param(
    [string]$RepoPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedRepo = (Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).Path
Set-Location -LiteralPath $resolvedRepo

$requiredFiles = @(
    "Repair-OpenCodeFreeDefaults.cmd",
    "tooling/wsl/AGENTS.md",
    "tooling/wsl/Invoke-OpenCodeFreeDefaultsRepair.ps1",
    "tooling/wsl/Set-OpenCodeFreeDefaults.ps1",
    "tooling/wsl/harness/opencode-free-defaults/workflow.json",
    "tooling/wsl/harness/opencode-free-defaults/artifact-catalog.json",
    "tooling/wsl/Test-OpenCodeFreeDefaultsHarness.ps1",
    "tooling/wsl/tests/test_opencode_free_defaults_harness.py"
)

$fileStatus = foreach ($relativePath in $requiredFiles) {
    $fullPath = Join-Path $resolvedRepo $relativePath
    [pscustomobject]@{
        path = $relativePath
        present = Test-Path -LiteralPath $fullPath -PathType Leaf
    }
}

$gitStatus = & git status --short
$gitExitCode = $LASTEXITCODE
if ($gitExitCode -ne 0) {
    throw "Unable to inspect repository Git status."
}
$branch = (& git branch --show-current).Trim()
$head = (& git rev-parse HEAD).Trim()

$stateRoot = Join-Path $env:LOCALAPPDATA "AgentSwitchboard\OpenCodeFreeDefaults"
$latestPointer = Join-Path $stateRoot "latest-run.txt"
$latestRun = $null
if (Test-Path -LiteralPath $latestPointer -PathType Leaf) {
    $latestRun = (Get-Content -LiteralPath $latestPointer -Raw).Trim()
}

$latestHandoff = $null
if ($latestRun) {
    $handoffPath = Join-Path $latestRun "final-handoff.json"
    if (Test-Path -LiteralPath $handoffPath -PathType Leaf) {
        $latestHandoff = Get-Content -LiteralPath $handoffPath -Raw | ConvertFrom-Json
    }
}

$manifestPath = Join-Path $resolvedRepo "tooling\wsl\tmux-gnhf-workstation.example.json"
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$distribution = [string]$manifest.distribution

$effectiveConfig = $null
$inspectionError = $null
try {
    $configText = & wsl.exe -d $distribution -e bash -lc 'test -f "$HOME/.config/opencode/opencode.json" && cat "$HOME/.config/opencode/opencode.json"'
    $inspectionExitCode = $LASTEXITCODE
    if ($inspectionExitCode -eq 0 -and $configText) {
        $parsed = ($configText -join [Environment]::NewLine) | ConvertFrom-Json
        $effectiveConfig = [pscustomobject]@{
            model = $parsed.model
            smallModel = $parsed.small_model
            share = $parsed.share
            whitelist = @($parsed.provider.opencode.whitelist)
        }
    }
    if ($inspectionExitCode -ne 0) {
        $inspectionError = "WSL config inspection returned exit code $inspectionExitCode."
    }
}
catch {
    $inspectionError = $_.Exception.Message
}

$result = [pscustomobject]@{
    schemaVersion = 1
    workflowId = "opencode-free-defaults-repair"
    repository = $resolvedRepo
    branch = $branch
    head = $head
    dirty = [bool]$gitStatus
    requiredFilesPresent = -not (@($fileStatus | Where-Object { -not $_.present }).Count -gt 0)
    files = @($fileStatus)
    distribution = $distribution
    expectedModel = [string]$manifest.opencode.defaultModel
    expectedSmallModel = [string]$manifest.opencode.smallModel
    expectedWhitelist = @($manifest.opencode.freeModelIds)
    effectiveConfig = $effectiveConfig
    inspectionError = $inspectionError
    latestRun = $latestRun
    latestHandoff = $latestHandoff
    proofCeiling = "Read-only repository and local configuration inspection; no provider response proof."
}

if ($Json) {
    $result | ConvertTo-Json -Depth 12
    return
}

Write-Host "OPENCODE FREE-DEFAULTS HARNESS STATUS" -ForegroundColor Cyan
Write-Host "Repository: $resolvedRepo"
Write-Host "Branch:     $branch"
Write-Host "Head:       $head"
Write-Host "Dirty:      $([bool]$gitStatus)"
Write-Host "Harness:    $(if ($result.requiredFilesPresent) { 'complete' } else { 'incomplete' })"
Write-Host "Expected:   $($result.expectedModel)"
if ($null -ne $effectiveConfig) {
    Write-Host "Effective:  $($effectiveConfig.model)"
    Write-Host "Small:      $($effectiveConfig.smallModel)"
    Write-Host "Share:      $($effectiveConfig.share)"
    Write-Host "Whitelist:  $(@($effectiveConfig.whitelist) -join ', ')"
}
if ($inspectionError) {
    Write-Host "Inspection: $inspectionError" -ForegroundColor Yellow
}
if ($latestRun) {
    Write-Host "Latest run: $latestRun"
}

$result
