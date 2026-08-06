[CmdletBinding()]
param(
    [string]$RootPath,
    [string]$OutputRoot,
    [switch]$KeepWorktree
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

if ($env:OS -ne 'Windows_NT') {
    Write-Host 'SKIP: CMD outer-entrypoint proof requires Windows.' -ForegroundColor Yellow
    exit 0
}
$GitCommand = 'git.exe'
if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = [string]((& $GitCommand -C $PSScriptRoot rev-parse --show-toplevel 2>$null | Select-Object -First 1))
}
if ([string]::IsNullOrWhiteSpace($RootPath)) { throw 'Unable to resolve repository root.' }
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$head = [string]((& $GitCommand -C $RootPath rev-parse HEAD | Select-Object -First 1)).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($head)) { throw 'Unable to resolve HEAD.' }
$runId = '{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'), $head.Substring(0,8)
$tempBase = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }
$worktree = Join-Path $tempBase ("AgentSwitchboard Command Delivery {0}" -f $runId)
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $tempBase ("AgentSwitchboard/command-delivery-entrypoint/{0}" -f $runId)
}
$null = New-Item -ItemType Directory -Path $OutputRoot -Force

& $GitCommand -C $RootPath worktree add --detach $worktree $head
if ($LASTEXITCODE -ne 0) { throw "Could not create detached spaced-path worktree: $worktree" }

$passed = $false
try {
    $launcher = Join-Path $worktree 'Test-SkillFactoringContracts.cmd'
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw "CMD entrypoint is missing: $launcher" }
    $skillOutput = Join-Path $OutputRoot 'skill-factoring'
    & $launcher -OutputRoot $skillOutput
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "CMD entrypoint failed with exit code $exitCode; preserved worktree: $worktree" }

    $skillReport = Join-Path $skillOutput 'skill-factoring-report.json'
    if (-not (Test-Path -LiteralPath $skillReport -PathType Leaf)) { throw "CMD entrypoint did not produce its canonical JSON report: $skillReport" }
    $skillPayload = Get-Content -LiteralPath $skillReport -Raw | ConvertFrom-Json
    if ([string]$skillPayload.status -ne 'PASS') { throw "CMD entrypoint report status was not PASS: $skillReport" }

    $dirty = @(& $GitCommand -C $worktree status --porcelain=v1 --untracked-files=normal)
    if ($LASTEXITCODE -ne 0) { throw "Could not verify worktree cleanliness: $worktree" }
    if ($dirty.Count -gt 0) { throw "CMD entrypoint changed the detached worktree: $worktree" }

    $result = [ordered]@{
        schema = 'agentswitchboard.command-delivery-entrypoint-result.v1'
        status = 'PASS'
        repositoryRoot = $RootPath
        verifiedHead = $head
        worktree = $worktree
        worktreeContainsSpaces = $worktree.Contains(' ')
        launcher = 'Test-SkillFactoringContracts.cmd'
        canonicalReport = $skillReport
        worktreeClean = $true
        proofCeiling = 'One exact CMD-to-PowerShell launcher execution from one detached path containing spaces on this Windows environment.'
    }
    $jsonPath = Join-Path $OutputRoot 'command-delivery-entrypoint-result.json'
    $mdPath = Join-Path $OutputRoot 'command-delivery-entrypoint-result.md'
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding utf8
    @(
        '# Command Delivery Entrypoint Result',
        '',
        '- Status: **PASS**',
        ('- Verified HEAD: `{0}`' -f $head),
        ('- Spaced worktree: `{0}`' -f $worktree),
        ('- Canonical report: `{0}`' -f $skillReport),
        '- Worktree clean: `true`',
        '',
        '## Proof ceiling',
        $result.proofCeiling
    ) | Set-Content -LiteralPath $mdPath -Encoding utf8
    Write-Host ("JSON: {0}" -f $jsonPath)
    Write-Host ("Report: {0}" -f $mdPath)
    $passed = $true
}
finally {
    if ($passed -and -not $KeepWorktree) {
        & $GitCommand -C $RootPath worktree remove $worktree
        if ($LASTEXITCODE -ne 0) { throw "Validation passed but clean worktree removal failed: $worktree" }
    }
    elseif (-not $passed) {
        Write-Warning "Entrypoint proof failed; preserved worktree: $worktree"
    }
}

Write-Host 'Command-delivery CMD outer-entrypoint proof passed.' -ForegroundColor Green
exit 0
