[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot,
    [string]$BaseRef = 'origin/main',
    [switch]$ListOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $tempRoot = [Environment]::GetEnvironmentVariable('RUNNER_TEMP')
    if ([string]::IsNullOrWhiteSpace($tempRoot)) {
        $tempRoot = [IO.Path]::GetTempPath()
    }
    $OutputRoot = Join-Path $tempRoot ('agentswitchboard-product-pass-local-proof-' + [Guid]::NewGuid().ToString('N'))
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path

$floorScript = Join-Path $RootPath 'scripts/Prove-AutomatedTestFloorLocal.ps1'
$mergeGateScript = Join-Path $RootPath 'scripts/Prove-MergeGateLocal.ps1'

if (-not (Test-Path -LiteralPath $floorScript -PathType Leaf)) {
    throw "Missing floor prove script: $floorScript"
}
if (-not (Test-Path -LiteralPath $mergeGateScript -PathType Leaf)) {
    throw "Missing merge-gate prove script: $mergeGateScript"
}

function Get-GitHead([string]$RepositoryPath) {
    $text = (& git -C $RepositoryPath rev-parse HEAD 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($text)) {
        return 'UNKNOWN'
    }
    return $text
}

function Get-ChangedFiles([string]$RepositoryPath, [string]$BaseReference) {
    $text = (& git -C $RepositoryPath diff --name-only $BaseReference 2>$null | Out-String)
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "git diff failed against $BaseReference; treating as no changes"
        return @()
    }
    $lines = $text -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    return @($lines)
}

function Invoke-ProveScript {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string]$OutputSubdir,
        [hashtable]$AdditionalArgs = @{}
    )

    $scriptOut = Join-Path $OutputRoot $OutputSubdir
    New-Item -ItemType Directory -Force -Path $scriptOut | Out-Null

    $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)
    if ($null -eq $pwsh) {
        throw "FAIL_CLOSED: pwsh not found"
    }

    $argList = @(
        '-NoLogo'
        '-NoProfile'
        '-File'
        $ScriptPath
        '-OutputRoot'
        $scriptOut
    )

    foreach ($key in $AdditionalArgs.Keys) {
        $argList += "-$key"
        $value = $AdditionalArgs[$key]
        if ($value -isnot [switch] -and $value -ne $true) {
            $argList += $value
        }
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $pwsh.Source
    $psi.WorkingDirectory = $RootPath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    foreach ($arg in $argList) {
        [void]$psi.ArgumentList.Add($arg)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout   = ([string]$stdoutTask.GetAwaiter().GetResult()).Trim()
            Stderr   = ([string]$stderrTask.GetAwaiter().GetResult()).Trim()
            Combined = ((([string]$stdoutTask.GetAwaiter().GetResult()) + [Environment]::NewLine + ([string]$stderrTask.GetAwaiter().GetResult())).Trim())
        }
    }
    finally {
        $process.Dispose()
    }
}

$candidateSha = Get-GitHead -RepositoryPath $RootPath
$changedFiles = Get-ChangedFiles -RepositoryPath $RootPath -BaseReference $BaseRef

Write-Host ("PRODUCT_PASS_LOCAL candidateSha={0} baseRef={1} changedFiles={2} outputRoot={3}" -f $candidateSha, $BaseRef, $changedFiles.Count, $OutputRoot)

if ($ListOnly) {
    Write-Host "`nProduct pass local orchestrates:"
    Write-Host "  1. Prove-AutomatedTestFloorLocal.ps1 (always-on)"
    Write-Host "  2. Prove-MergeGateLocal.ps1 (path-selected)"
    exit 0
}

$steps = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$blockedSteps = [System.Collections.Generic.List[string]]::new()
$flags = [System.Collections.Generic.List[string]]::new()

# 1) Always-on floor
Write-Host "`n=== Automated Test Floor (always-on) ==="
$floorResult = Invoke-ProveScript -ScriptPath $floorScript -OutputSubdir 'floor'
$floorOk = ($floorResult.ExitCode -eq 0)

Write-Host $floorResult.Combined

$steps.Add([ordered]@{
        id       = 'automated-test-floor'
        script   = 'Prove-AutomatedTestFloorLocal.ps1'
        exitCode = $floorResult.ExitCode
        status   = $(if ($floorOk) { 'PASS' } else { 'FAIL' })
        detail   = $(if ($floorOk) { 'floor passed' } else { 'floor failed' })
    })

if (-not $floorOk) {
    $failures.Add('automated-test-floor failed')
}

# 2) Path-selected merge-gate
Write-Host "`n=== Merge Gate Local (path-selected) ==="
$mergeGateArgs = @{
    BaseRef = $BaseRef
}
$mergeGateResult = Invoke-ProveScript -ScriptPath $mergeGateScript -OutputSubdir 'merge-gate' -AdditionalArgs $mergeGateArgs
$mergeGateOk = ($mergeGateResult.ExitCode -eq 0)

Write-Host $mergeGateResult.Combined

# Parse merge-gate result for BLOCKED_HOST conditions
$mergeGateHasBlockedHost = $mergeGateResult.Combined -match 'BLOCKED_HOST_REQUIRED'

$steps.Add([ordered]@{
        id       = 'merge-gate-local'
        script   = 'Prove-MergeGateLocal.ps1'
        exitCode = $mergeGateResult.ExitCode
        status   = $(if ($mergeGateOk) { 'PASS' } elseif ($mergeGateHasBlockedHost) { 'BLOCKED_HOST' } else { 'FAIL' })
        detail   = $(if ($mergeGateOk) { 'merge-gate passed' } elseif ($mergeGateHasBlockedHost) { 'merge-gate blocked on host capability' } else { 'merge-gate failed' })
    })

if (-not $mergeGateOk) {
    if ($mergeGateHasBlockedHost) {
        $blockedSteps.Add('merge-gate-local blocked on host capability')
    }
    else {
        $failures.Add('merge-gate-local failed')
    }
}

# 3) Flag checks: git diff --check
Write-Host "`n=== Flag checks ==="
$git = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $git) {
    Write-Host "WARN: git not found for diff hygiene check"
    $flags.Add('git not found for diff hygiene')
}
else {
    $diffCheckOutput = (& git -C $RootPath diff --check $BaseRef 2>&1 | Out-String).Trim()
    $diffCheckOk = ($LASTEXITCODE -eq 0)
    if ($diffCheckOk) {
        Write-Host "git diff --check: PASS"
    }
    else {
        Write-Host "git diff --check: FAIL"
        if ($diffCheckOutput) {
            Write-Host $diffCheckOutput
        }
        $flags.Add('git diff --check failed (trailing whitespace or other issues)')
    }
}

# Determine overall product-pass posture
$posture = 'PROVEN'
if ($blockedSteps.Count -gt 0) {
    $posture = 'BLOCKED_HOST'
}
elseif ($flags.Count -gt 0) {
    $posture = 'FLAGGED'
}
elseif ($failures.Count -gt 0) {
    $posture = 'UNPROVEN'
}

$packet = [ordered]@{
    schema       = 'agentswitchboard.product-pass-local.proof.v1'
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    candidateSha = $candidateSha
    baseRef      = $BaseRef
    posture      = $posture
    proofCeiling = 'Local static proof orchestrator. Delegates to floor (always-on) and merge-gate-local (path-selected). Not runtime, not live-target, not GitHub mergeability, not merge/release/deploy authority.'
    steps        = @($steps)
    failures     = @($failures)
    blockedSteps = @($blockedSteps)
    flags        = @($flags)
    outputs      = [ordered]@{
        floorOutput      = (Join-Path $OutputRoot 'floor')
        mergeGateOutput  = (Join-Path $OutputRoot 'merge-gate')
        packetJson       = (Join-Path $OutputRoot 'product-pass-local-proof-packet.json')
        packetMd         = (Join-Path $OutputRoot 'product-pass-local-proof-packet.md')
    }
}

$jsonPath = Join-Path $OutputRoot 'product-pass-local-proof-packet.json'
$mdPath = Join-Path $OutputRoot 'product-pass-local-proof-packet.md'
($packet | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $jsonPath -Encoding utf8

$md = [System.Collections.Generic.List[string]]::new()
[void]$md.Add('# Product pass local proof packet')
[void]$md.Add('')
[void]$md.Add(('Posture: **{0}**' -f $posture))
[void]$md.Add(('Candidate SHA: `{0}`' -f $candidateSha))
[void]$md.Add(('Base ref: `{0}`' -f $BaseRef))
[void]$md.Add('')
[void]$md.Add(('**Proof ceiling:** {0}' -f [string]$packet.proofCeiling))
[void]$md.Add('')
[void]$md.Add('## Orchestrated steps')
[void]$md.Add('')
[void]$md.Add('| Step | Script | Status | Detail |')
[void]$md.Add('|---|---|---|---|')
foreach ($step in $steps) {
    $detail = ([string]$step.detail -replace '\|', '/') -replace '\r?\n', ' '
    [void]$md.Add(('| {0} | {1} | {2} | {3} |' -f $step.id, $step.script, $step.status, $detail))
}

if ($failures.Count -gt 0) {
    [void]$md.Add('')
    [void]$md.Add('## Failures')
    [void]$md.Add('')
    foreach ($failure in $failures) {
        [void]$md.Add(('- {0}' -f $failure))
    }
}

if ($blockedSteps.Count -gt 0) {
    [void]$md.Add('')
    [void]$md.Add('## Blocked steps')
    [void]$md.Add('')
    foreach ($blocked in $blockedSteps) {
        [void]$md.Add(('- {0}' -f $blocked))
    }
}

if ($flags.Count -gt 0) {
    [void]$md.Add('')
    [void]$md.Add('## Flags')
    [void]$md.Add('')
    foreach ($flag in $flags) {
        [void]$md.Add(('- {0}' -f $flag))
    }
}

($md -join [Environment]::NewLine) | Set-Content -LiteralPath $mdPath -Encoding utf8

Write-Host ("`nPRODUCT_PASS_LOCAL_PROOF_PACKET_JSON={0}" -f $jsonPath)
Write-Host ("PRODUCT_PASS_LOCAL_PROOF_PACKET_MD={0}" -f $mdPath)
Write-Host ("PRODUCT_PASS_LOCAL_POSTURE: {0}" -f $posture)

if ($posture -ne 'PROVEN') {
    exit 1
}
exit 0
