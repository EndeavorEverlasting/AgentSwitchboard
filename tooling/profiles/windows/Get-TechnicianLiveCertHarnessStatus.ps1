[CmdletBinding()]
param(
    [string]$RootPath,
    [string]$OutputRoot,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw 'Unable to resolve status reporter directory. Supply -RootPath explicitly.'
    }
    $RootPath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $base = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\technician-live-cert\harness-status'
    } else {
        Join-Path ([System.IO.Path]::GetTempPath()) 'AgentSwitchboard/technician-live-cert/harness-status'
    }
    $OutputRoot = $base
}
if (-not (Test-Path -LiteralPath $OutputRoot -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $OutputRoot -Force
}

$manifestPath = Join-Path $RootPath 'tooling\profiles\windows\harness\technician-live-cert\manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

$toolchainResult = $null
$gitPath = $null
$toolchainJson = $null
$toolchainMarkdown = $null
if ($env:OS -eq 'Windows_NT') {
    $toolchainScript = Join-Path $RootPath ([string]$manifest.entrypoints.toolchainPreflightValidator)
    $toolchainOutput = Join-Path $OutputRoot 'toolchain-preflight'
    try {
        $toolchainResult = & $toolchainScript -OutputRoot $toolchainOutput -PassThru
        $toolchainJson = Join-Path $toolchainOutput 'windows-toolchain-launch-preflight.json'
        $toolchainMarkdown = Join-Path $toolchainOutput 'windows-toolchain-launch-preflight.md'
        if ($toolchainResult.status -eq 'passed' -and -not [string]::IsNullOrWhiteSpace([string]$toolchainResult.selectedGit)) {
            $gitPath = [string]$toolchainResult.selectedGit
        }
    }
    catch {
        $toolchainResult = [pscustomobject]@{ status = 'blocked'; selectedGit = $null; error = $_.Exception.Message }
    }
}
else {
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) { $gitPath = $git.Source }
    $toolchainResult = [pscustomobject]@{ status = if($gitPath){'not-applicable'}else{'blocked'}; selectedGit = $gitPath; error = $null }
}

$componentRows = @()
foreach ($component in $manifest.components) {
    $relativePath = [string]$component.path
    $fullPath = Join-Path $RootPath $relativePath
    $exists = Test-Path -LiteralPath $fullPath -PathType Leaf
    $tracked = $false
    if ($exists -and $gitPath) {
        & $gitPath -C $RootPath ls-files --error-unmatch -- $relativePath *> $null
        $tracked = ($LASTEXITCODE -eq 0)
    }
    $componentRows += [pscustomobject]@{
        id = [string]$component.id
        type = [string]$component.type
        path = $relativePath
        exists = $exists
        tracked = $tracked
        status = if ($exists -and $tracked) { 'ready' } elseif($exists -and -not $gitPath) { 'blocked-git-unavailable' } else { 'blocked' }
    }
}

$p00Text = Get-Content -LiteralPath (Join-Path $RootPath 'tooling\profiles\windows\technician-live-cert\stages\P00-Preflight.ps1') -Raw
$surfaceText = Get-Content -LiteralPath (Join-Path $RootPath 'scripts\Test-TechnicianLiveCertSurface.ps1') -Raw
$toolchainText = Get-Content -LiteralPath (Join-Path $RootPath ([string]$manifest.entrypoints.toolchainPreflightValidator)) -Raw
$surfaceStrictIndex = $surfaceText.IndexOf('Set-StrictMode')
$surfaceParameterText = if ($surfaceStrictIndex -gt 0) {
    $surfaceText.Substring(0, $surfaceStrictIndex)
}
else {
    $surfaceText
}
$guardRows = @(
    [pscustomobject]@{
        id = 'git-executable-launch'
        passed = ($toolchainResult.status -in @('passed','not-applicable'))
        detail = if($gitPath){"Concrete Git executable launch path: $gitPath"}else{"No usable Git executable was proven. $([string]$toolchainResult.error)"}
    },
    [pscustomobject]@{
        id = 'git-executable-launch-contract'
        passed = ($toolchainText.Contains('System.Diagnostics.ProcessStartInfo') -and $toolchainText.Contains('$psi.UseShellExecute = $false') -and $toolchainText.Contains('$process.WaitForExit($TimeoutSeconds * 1000)'))
        detail = 'Preflight launches a concrete executable without shell mediation and bounds the wait.'
    },
    [pscustomobject]@{
        id = 'ambiguous-dotnet-overload'
        passed = (-not $p00Text.Contains(".Replace([char]0, '')") -and $p00Text.Contains(".Replace(([char]0).ToString(), [string]::Empty)"))
        detail = 'P00 forces string/string Replace for NUL removal.'
    },
    [pscustomobject]@{
        id = 'psscriptroot-param-default'
        passed = (-not $surfaceParameterText.Contains('$PSScriptRoot)'))
        detail = 'Validator resolves repository root in the script body.'
    },
    [pscustomobject]@{
        id = 'interactive-git-pager'
        passed = ((Get-Content -LiteralPath (Join-Path $RootPath '.github\workflows\technician-live-cert-surface.yml') -Raw).Contains('git --no-pager diff --check'))
        detail = 'Automation disables the Git pager.'
    }
)

$head = 'UNAVAILABLE'
$branch = 'UNAVAILABLE'
if ($gitPath) {
    $headOutput = @(& $gitPath -C $RootPath rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $headOutput.Count -gt 0) { $head = ([string]$headOutput[0]).Trim() }
    $branchOutput = @(& $gitPath -C $RootPath symbolic-ref --quiet --short HEAD 2>$null)
    $branch = if ($LASTEXITCODE -eq 0 -and $branchOutput.Count -gt 0) { ([string]$branchOutput[0]).Trim() } else { 'DETACHED' }
}
$blocked = @($componentRows | Where-Object { $_.status -ne 'ready' })
$failedGuards = @($guardRows | Where-Object { -not $_.passed })
$status = if ($blocked.Count -eq 0 -and $failedGuards.Count -eq 0) { 'READY_FOR_VALIDATION' } else { 'BLOCKED' }

$nextCommand = if (-not $gitPath) {
    'call "' + (Join-Path $RootPath 'Test-Technician-Toolchain-Preflight.cmd') + '"'
} elseif ($status -eq 'READY_FOR_VALIDATION') {
    'powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $RootPath 'scripts\Test-TechnicianLiveCertHarness.ps1') + '" -RootPath "' + $RootPath + '"'
} else {
    'pwsh -NoLogo -NoProfile -File "' + (Join-Path $RootPath 'tooling\profiles\windows\Get-TechnicianLiveCertHarnessStatus.ps1') + '" -RootPath "' + $RootPath + '"'
}

$result = [ordered]@{
    schema = 'agentswitchboard.technician-live-cert-harness-status.v1'
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    repository = 'EndeavorEverlasting/AgentSwitchboard'
    root = $RootPath
    branch = $branch
    head = $head
    status = $status
    toolchain = [ordered]@{
        status = [string]$toolchainResult.status
        selectedGit = $gitPath
        json = $toolchainJson
        markdown = $toolchainMarkdown
    }
    components = $componentRows
    guards = $guardRows
    blockedCount = $blocked.Count
    failedGuardCount = $failedGuards.Count
    proofCeiling = [string]$manifest.proofCeiling
    nextCommand = $nextCommand
}

$jsonPath = Join-Path $OutputRoot 'technician-live-cert-harness-status.json'
$mdPath = Join-Path $OutputRoot 'technician-live-cert-harness-status.md'
$json = $result | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($jsonPath, $json, (New-Object System.Text.UTF8Encoding($false)))

$componentLines = @($componentRows | ForEach-Object { '| {0} | {1} | {2} | `{3}` |' -f $_.id, $_.type, $_.status, $_.path })
$guardLines = @($guardRows | ForEach-Object { "| $($_.id) | $($_.passed) | $($_.detail) |" })
$markdown = @"
# Technician Live-Cert Harness Status

- Repository: `EndeavorEverlasting/AgentSwitchboard`
- Branch: `$branch`
- HEAD: `$head`
- Generated: `$($result.generatedAt)`
- Status: **$status**
- Git launch: `$($result.toolchain.status)`
- Selected Git: `$(if($gitPath){$gitPath}else{'none'})`
- Toolchain JSON: `$(if($toolchainJson){$toolchainJson}else{'unavailable'})`
- Proof ceiling: $($result.proofCeiling)

## Components

| ID | Type | Status | Path |
|---|---|---|---|
$($componentLines -join "`n")

## Runtime-compatibility guards

| Guard | Passed | Detail |
|---|---:|---|
$($guardLines -join "`n")

## Exact next command

~~~cmd
$($result.nextCommand)
~~~
"@
[System.IO.File]::WriteAllText($mdPath, $markdown, (New-Object System.Text.UTF8Encoding($false)))

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Technician Live-Cert Harness Status' -ForegroundColor White
Write-Host " Status: $status"
Write-Host " Git launch: $($result.toolchain.status)"
Write-Host " Selected Git: $(if($gitPath){$gitPath}else{'none'})"
Write-Host " Components blocked: $($blocked.Count)"
Write-Host " Guards failed: $($failedGuards.Count)"
Write-Host " JSON: $jsonPath"
Write-Host " Report: $mdPath"
Write-Host '============================================================' -ForegroundColor Cyan

if ($PassThru) {
    return [pscustomobject]$result
}
if ($status -ne 'READY_FOR_VALIDATION') {
    exit 1
}
exit 0