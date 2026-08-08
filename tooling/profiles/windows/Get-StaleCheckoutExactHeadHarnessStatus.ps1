[CmdletBinding()]
param(
    [string]$RootPath,
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$GitCommand = if ($env:OS -eq 'Windows_NT') { 'git.exe' } else { 'git' }

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
    $OutputRoot = Join-Path $base 'AgentSwitchboard\stale-checkout-exact-head\harness-status'
}
$null = New-Item -ItemType Directory -Path $OutputRoot -Force

$manifestPath = Join-Path $RootPath 'tooling\profiles\windows\harness\stale-checkout-exact-head\manifest.json'
$errors = [System.Collections.Generic.List[string]]::new()
$components = @()
$manifest = $null

try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $components = @($manifest.components)
}
catch {
    [void]$errors.Add("Manifest load failed: $($_.Exception.Message)")
}

$componentResults = @()
foreach ($component in $components) {
    $path = Join-Path $RootPath ([string]$component.path)
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    $tracked = $false
    if ($exists) {
        & $GitCommand -C $RootPath ls-files --error-unmatch -- ([string]$component.path) *> $null
        $tracked = $LASTEXITCODE -eq 0
    }
    if (-not $exists) {
        [void]$errors.Add("Missing component: $($component.path)")
    }
    elseif (-not $tracked) {
        [void]$errors.Add("Untracked component: $($component.path)")
    }
    $componentResults += [pscustomobject]@{
        id = [string]$component.id
        path = [string]$component.path
        type = [string]$component.type
        exists = $exists
        tracked = $tracked
    }
}

$status = if ($errors.Count -eq 0 -and $components.Count -gt 0) { 'ready' } else { 'incomplete' }
$result = [ordered]@{
    schema = 'agentswitchboard.stale-checkout-exact-head-harness-status.v1'
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    rootPath = $RootPath
    status = $status
    componentCount = $components.Count
    components = $componentResults
    errors = @($errors)
    proofCeiling = 'Tracked focused harness completeness and report generation only. No remote fetch, exact-head validation, workstation readiness, provider response, or operator acceptance is proven.'
}

$jsonPath = Join-Path $OutputRoot 'stale-checkout-exact-head-harness-status.json'
$mdPath = Join-Path $OutputRoot 'stale-checkout-exact-head-harness-status.md'
Write-Utf8NoBom -Path $jsonPath -Content ($result | ConvertTo-Json -Depth 8)

$componentLines = @($componentResults | ForEach-Object {
    "| $($_.id) | $($_.type) | $($_.exists) | $($_.tracked) | ``$($_.path)`` |"
})
$errorLines = if ($errors.Count -eq 0) { '- none' } else { @($errors | ForEach-Object { "- $_" }) -join "`n" }

$reportText = @"
# Stale-Checkout Exact-Head Harness Status

- Status: **$($status.ToUpperInvariant())**
- Components: **$($components.Count)**
- Root: ``$RootPath``

| Component | Type | Exists | Tracked | Path |
|---|---|---:|---:|---|
$($componentLines -join "`n")

## Errors

$errorLines

## Proof ceiling

$($result.proofCeiling)
"@
Write-Utf8NoBom -Path $mdPath -Content $reportText

Write-Host "Status: $status"
Write-Host "JSON:   $jsonPath"
Write-Host "Report: $mdPath"
if ($status -ne 'ready') {
    throw "Stale-checkout exact-head harness status is incomplete. See $mdPath"
}
