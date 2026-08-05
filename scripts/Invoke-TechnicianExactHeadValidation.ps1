[CmdletBinding()]
param(
    [string]$RepoRoot,

    [string]$RemoteRef,

    [string]$ExpectedHead,

    [string]$WorktreeRoot,

    [switch]$SkipP00,

    [switch]$RunReadiness
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw 'Unable to resolve the exact-head validator directory. Supply -RepoRoot explicitly.'
    }
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot -ErrorAction Stop).Path

function Invoke-Git {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure
    )

    $output = @(& git.exe -C $RepoRoot --no-pager @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $exitCode.`n$($output -join "`n")"
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output | ForEach-Object { [string]$_ })
    }
}

$origin = Invoke-Git -Arguments @('remote', 'get-url', 'origin')
$originUrl = ($origin.Output | Select-Object -First 1).Trim()
if ($originUrl -notin @(
    'https://github.com/EndeavorEverlasting/AgentSwitchboard.git',
    'https://github.com/EndeavorEverlasting/AgentSwitchboard',
    'git@github.com:EndeavorEverlasting/AgentSwitchboard.git'
)) {
    throw "Unexpected origin: $originUrl"
}

$currentBranchResult = Invoke-Git -Arguments @('symbolic-ref', '--quiet', '--short', 'HEAD') -AllowFailure
$currentBranch = if ($currentBranchResult.ExitCode -eq 0 -and $currentBranchResult.Output.Count -gt 0) {
    $currentBranchResult.Output[0].Trim()
}
else {
    $null
}

if ([string]::IsNullOrWhiteSpace($RemoteRef)) {
    if ([string]::IsNullOrWhiteSpace($currentBranch)) {
        throw 'The current checkout is detached. Supply -RemoteRef explicitly.'
    }
    $RemoteRef = "refs/heads/$currentBranch"
}

Write-Host '=== ORIGINAL CHECKOUT — READ ONLY ===' -ForegroundColor Cyan
Write-Host "Repository: $RepoRoot"
Write-Host "Branch:     $(if ($currentBranch) { $currentBranch } else { 'DETACHED' })"
Invoke-Git -Arguments @('status', '--short') | ForEach-Object { $_.Output }
Invoke-Git -Arguments @('log', '--oneline', '--decorate', '-5') | ForEach-Object { $_.Output }

Write-Host '=== FETCH EXACT REMOTE REF ===' -ForegroundColor Cyan
Invoke-Git -Arguments @('fetch', '--no-tags', 'origin', $RemoteRef) | Out-Null
$fetched = Invoke-Git -Arguments @('rev-parse', 'FETCH_HEAD')
$fetchedHead = ($fetched.Output | Select-Object -First 1).Trim()

if (-not [string]::IsNullOrWhiteSpace($ExpectedHead) -and $fetchedHead -ne $ExpectedHead) {
    throw "Fetched head mismatch. Expected $ExpectedHead; fetched $fetchedHead."
}
$verifiedHead = $fetchedHead

if ([string]::IsNullOrWhiteSpace($WorktreeRoot)) {
    $parent = Split-Path -Parent $RepoRoot
    $leaf = Split-Path -Leaf $RepoRoot
    $WorktreeRoot = Join-Path $parent ("{0}-exact-{1}" -f $leaf, $verifiedHead.Substring(0, 8))
}
$WorktreeRoot = [IO.Path]::GetFullPath($WorktreeRoot)

$reuse = $false
if (Test-Path -LiteralPath $WorktreeRoot) {
    $existing = @(& git.exe -C $WorktreeRoot rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $existing.Count -gt 0 -and ([string]$existing[0]).Trim() -eq $verifiedHead) {
        $reuse = $true
        Write-Host "Reusing exact-head worktree: $WorktreeRoot" -ForegroundColor Green
    }
    else {
        $WorktreeRoot = '{0}-{1}' -f $WorktreeRoot, (Get-Date -Format 'yyyyMMdd-HHmmss')
        Write-Host "Preserving existing path; using: $WorktreeRoot" -ForegroundColor Yellow
    }
}

if (-not $reuse) {
    & git.exe -C $RepoRoot worktree add --detach $WorktreeRoot $verifiedHead
    if ($LASTEXITCODE -ne 0) {
        throw 'Could not create the detached exact-head worktree.'
    }
}

$actualHead = (@(& git.exe -C $WorktreeRoot rev-parse HEAD) | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0 -or $actualHead -ne $verifiedHead) {
    throw "Exact-head worktree mismatch. Fetched $verifiedHead; actual $actualHead."
}
$verifiedHead = $actualHead

$dirty = @(& git.exe -C $WorktreeRoot status --porcelain=v1 --untracked-files=normal)
if ($LASTEXITCODE -ne 0) {
    throw 'Could not verify exact-head worktree cleanliness.'
}
if ($dirty.Count -gt 0) {
    throw "Exact-head worktree is dirty. No cleanup was attempted.`n$($dirty -join "`n")"
}

$evidenceRoot = if ($env:LOCALAPPDATA) {
    Join-Path $env:LOCALAPPDATA ("AgentSwitchboard\exact-head-validation\runs\{0}-{1}" -f (Get-Date -Format 'yyyyMMddTHHmmssZ'), $verifiedHead.Substring(0, 8))
}
else {
    Join-Path ([IO.Path]::GetTempPath()) ("AgentSwitchboard/exact-head-validation/{0}-{1}" -f (Get-Date -Format 'yyyyMMddTHHmmssZ'), $verifiedHead.Substring(0, 8))
}
$null = New-Item -ItemType Directory -Path $evidenceRoot -Force

$checks = [System.Collections.Generic.List[object]]::new()
function Invoke-Check {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    Write-Host "=== $Name ===" -ForegroundColor Cyan
    $started = Get-Date
    try {
        & $Action
        if ($LASTEXITCODE -ne 0) {
            throw "$Name exited with code $LASTEXITCODE."
        }
        [void]$checks.Add([pscustomobject]@{
            name = $Name
            status = 'passed'
            startedAt = $started.ToUniversalTime().ToString('o')
            completedAt = (Get-Date).ToUniversalTime().ToString('o')
            error = $null
        })
    }
    catch {
        [void]$checks.Add([pscustomobject]@{
            name = $Name
            status = 'failed'
            startedAt = $started.ToUniversalTime().ToString('o')
            completedAt = (Get-Date).ToUniversalTime().ToString('o')
            error = $_.Exception.Message
        })
        throw
    }
}

Push-Location $WorktreeRoot
try {
    Invoke-Check -Name 'Python live-cert surface contracts' -Action {
        & python -m unittest tests.test_technician_live_cert_surface
    }
    Invoke-Check -Name 'Python live-cert harness contracts' -Action {
        & python -m unittest tests.test_technician_live_cert_harness
    }
    Invoke-Check -Name 'Python technician AgentSwitchboard readiness contracts' -Action {
        & python -m unittest tests.test_technician_agentswitchboard_ready
    }
    Invoke-Check -Name 'Windows PowerShell 5.1 surface validator' -Action {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $WorktreeRoot 'scripts\Test-TechnicianLiveCertSurface.ps1') `
            -RootPath $WorktreeRoot
    }
    Invoke-Check -Name 'Windows PowerShell 5.1 harness validator' -Action {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $WorktreeRoot 'scripts\Test-TechnicianLiveCertHarness.ps1') `
            -RootPath $WorktreeRoot
    }
    Invoke-Check -Name 'Windows PowerShell 5.1 readiness validator' -Action {
        & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
            -File (Join-Path $WorktreeRoot 'scripts\Test-TechnicianAgentSwitchboardReady.ps1') `
            -RootPath $WorktreeRoot
    }
    Invoke-Check -Name 'PowerShell 7 surface validator' -Action {
        & pwsh.exe -NoLogo -NoProfile `
            -File (Join-Path $WorktreeRoot 'scripts\Test-TechnicianLiveCertSurface.ps1') `
            -RootPath $WorktreeRoot
    }
    Invoke-Check -Name 'PowerShell 7 harness validator' -Action {
        & pwsh.exe -NoLogo -NoProfile `
            -File (Join-Path $WorktreeRoot 'scripts\Test-TechnicianLiveCertHarness.ps1') `
            -RootPath $WorktreeRoot
    }
    Invoke-Check -Name 'PowerShell 7 readiness validator' -Action {
        & pwsh.exe -NoLogo -NoProfile `
            -File (Join-Path $WorktreeRoot 'scripts\Test-TechnicianAgentSwitchboardReady.ps1') `
            -RootPath $WorktreeRoot
    }
    Invoke-Check -Name 'Harness status artifact' -Action {
        & pwsh.exe -NoLogo -NoProfile `
            -File (Join-Path $WorktreeRoot 'tooling\profiles\windows\Get-TechnicianLiveCertHarnessStatus.ps1') `
            -RootPath $WorktreeRoot
    }

    $preflightArtifact = $null
    if (-not $SkipP00) {
        $p00StartedUtc = [DateTime]::UtcNow
        Invoke-Check -Name 'Exact-head P00 runtime' -Action {
            $env:AGENT_SWITCHBOARD_NO_PAUSE = '1'
            Remove-Item Env:TECHNICIAN_LIVE_CERT_CI_SURFACE -ErrorAction SilentlyContinue
            & cmd.exe /d /c 'call Technician-LiveCert-P00-Preflight.cmd'
        }

        $runRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\technician-live-cert\runs'
        $preflightArtifact = Get-ChildItem -LiteralPath $runRoot -Filter 'preflight-summary.json' -File -Recurse |
            Where-Object { $_.LastWriteTimeUtc -ge $p00StartedUtc } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if (-not $preflightArtifact) {
            throw 'Exact-head P00 passed without producing a new preflight artifact.'
        }
        $preflight = Get-Content -LiteralPath $preflightArtifact.FullName -Raw | ConvertFrom-Json
        if (-not $preflight.passed -or -not $preflight.ubuntuInitialized) {
            throw "Exact-head P00 artifact does not prove initialized Ubuntu: $($preflightArtifact.FullName)"
        }
    }

    $readinessArtifact = $null
    $readinessStatus = $null
    if ($RunReadiness) {
        $readinessCmd = Join-Path $WorktreeRoot 'Technician-AgentSwitchboard-Ready.cmd'
        if (-not (Test-Path -LiteralPath $readinessCmd -PathType Leaf)) {
            throw "Exact-head worktree is missing the readiness command: $readinessCmd"
        }

        $readinessStartedUtc = [DateTime]::UtcNow
        Invoke-Check -Name 'Exact-head AgentSwitchboard readiness' -Action {
            $env:AGENT_SWITCHBOARD_NO_PAUSE = '1'
            Remove-Item Env:TECHNICIAN_AGENTSWITCHBOARD_CI_SURFACE -ErrorAction SilentlyContinue
            & cmd.exe /d /c "call `"$readinessCmd`" setup `"$WorktreeRoot`" `"$RemoteRef`""
        }

        $readinessRunRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\technician-ready\runs'
        $readinessArtifact = Get-ChildItem -LiteralPath $readinessRunRoot -Filter 'technician-ready-summary.json' -File -Recurse |
            Where-Object { $_.LastWriteTimeUtc -ge $readinessStartedUtc } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if (-not $readinessArtifact) {
            throw 'Exact-head readiness completed without producing a new technician-ready summary.'
        }

        $readiness = Get-Content -LiteralPath $readinessArtifact.FullName -Raw | ConvertFrom-Json
        if ($readiness.status -ne 'success') {
            throw "Exact-head readiness summary is not successful: $($readinessArtifact.FullName)"
        }
        if (-not $readiness.startupReadiness.stateObserved) {
            throw "Exact-head readiness did not observe canonical fleet state: $($readinessArtifact.FullName)"
        }
        if ($readiness.startupReadiness.overallStatus -in @('not-configured', 'blocked')) {
            throw "Exact-head readiness left AgentSwitchboard unusable: $($readiness.startupReadiness.overallStatus)"
        }
        if (-not $readiness.commands.AgentSwitchboard.shim -or -not (Test-Path -LiteralPath $readiness.commands.AgentSwitchboard.shim -PathType Leaf)) {
            throw "Exact-head readiness did not produce a resolvable AgentSwitchboard command shim: $($readinessArtifact.FullName)"
        }
        if (-not (Test-Path -LiteralPath $readiness.fleetStatePath -PathType Leaf)) {
            throw "Exact-head readiness did not preserve canonical fleet state: $($readiness.fleetStatePath)"
        }
        $readinessStatus = $readiness.startupReadiness.overallStatus
    }

    & git.exe --no-pager diff --check
    if ($LASTEXITCODE -ne 0) {
        throw 'Exact-head repository hygiene validation failed.'
    }

    $proofLevel = if ($RunReadiness) {
        'exact-head-cross-shell-p00-and-agentswitchboard-readiness'
    }
    else {
        'exact-head-cross-shell-and-p00-field-validation'
    }
    $proofCeiling = if ($RunReadiness) {
        'Proves the named tracked head, validators, repository cleanliness, P00 workstation prerequisites, real technician setup, canonical fleet-state observation, and fresh-shell AgentSwitchboard readiness. It does not prove provider authentication, quota, hosted model availability, hosted response, agent task quality, visible-window focus, or operator acceptance.'
    }
    else {
        'Proves the named tracked head, validators, repository cleanliness, and optional P00 workstation prerequisites. It does not prove technician setup, AgentSwitchboard fleet readiness, provider authentication, hosted response, or operator acceptance.'
    }

    $result = [ordered]@{
        schema = 'agentswitchboard.exact-head-field-validation.v1'
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        repositoryRoot = $RepoRoot
        remoteRef = $RemoteRef
        fetchedHead = $fetchedHead
        verifiedHead = $actualHead
        worktree = $WorktreeRoot
        worktreeClean = $true
        checks = $checks
        p00Artifact = if ($preflightArtifact) { $preflightArtifact.FullName } else { $null }
        readinessRequested = [bool]$RunReadiness
        readinessStatus = $readinessStatus
        readinessArtifact = if ($readinessArtifact) { $readinessArtifact.FullName } else { $null }
        status = 'passed'
        proofLevel = $proofLevel
        proofCeiling = $proofCeiling
    }

    $jsonPath = Join-Path $evidenceRoot 'exact-head-validation.json'
    $mdPath = Join-Path $evidenceRoot 'exact-head-validation.md'
    $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM

    $checkLines = @($checks | ForEach-Object { "| $($_.name) | $($_.status) | $($_.error) |" })
    @"
# AgentSwitchboard Exact-Head Field Validation

- Status: **PASSED**
- Remote ref: ``$RemoteRef``
- Verified HEAD: ``$actualHead``
- Worktree: ``$WorktreeRoot``
- P00 artifact: ``$(if ($preflightArtifact) { $preflightArtifact.FullName } else { 'skipped' })``
- Readiness requested: **$([bool]$RunReadiness)**
- Readiness status: ``$(if ($readinessStatus) { $readinessStatus } else { 'not-run' })``
- Readiness artifact: ``$(if ($readinessArtifact) { $readinessArtifact.FullName } else { 'not-run' })``

| Check | Status | Error |
|---|---|---|
$($checkLines -join "`n")

## Proof ceiling

$proofCeiling
"@ | Set-Content -LiteralPath $mdPath -Encoding utf8NoBOM

    Write-Host '=== EXACT-HEAD FIELD PROOF ===' -ForegroundColor Green
    Write-Host "Verified HEAD:      $actualHead"
    Write-Host "Worktree:           $WorktreeRoot"
    Write-Host "JSON:               $jsonPath"
    Write-Host "Report:             $mdPath"
    if ($preflightArtifact) {
        Write-Host "P00 artifact:       $($preflightArtifact.FullName)"
    }
    if ($readinessArtifact) {
        Write-Host "Readiness status:   $readinessStatus"
        Write-Host "Readiness artifact: $($readinessArtifact.FullName)"
    }
}
finally {
    Pop-Location
}
