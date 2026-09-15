[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $tempRoot = [Environment]::GetEnvironmentVariable('RUNNER_TEMP')
    if ([string]::IsNullOrWhiteSpace($tempRoot)) {
        $tempRoot = [IO.Path]::GetTempPath()
    }
    $OutputRoot = Join-Path $tempRoot ('agentswitchboard-automated-test-floor-local-proof-' + [Guid]::NewGuid().ToString('N'))
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path

$floorRunner = Join-Path $RootPath 'scripts/Test-AutomatedTestFloor.ps1'
$canaryRel = '.ai/harness/fixtures/automated-test-floor/canary_fail.py'
$canaryPath = Join-Path $RootPath $canaryRel
if (-not (Test-Path -LiteralPath $floorRunner -PathType Leaf)) {
    throw "Missing canonical floor runner: $floorRunner"
}
if (-not (Test-Path -LiteralPath $canaryPath -PathType Leaf)) {
    throw "Missing canary fixture: $canaryPath"
}

function Get-PythonCommand {
    foreach ($candidate in @('python3', 'python')) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $cmd) { return $cmd.Source }
    }
    throw 'Python interpreter not found (python3/python).'
}

function Get-GitHead([string]$RepositoryPath) {
    $text = (& git -C $RepositoryPath rev-parse HEAD 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($text)) {
        return 'UNKNOWN'
    }
    return $text
}

function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$WorkingDirectory
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    foreach ($argument in $ArgumentList) {
        [void]$psi.ArgumentList.Add($argument)
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
            Combined = ((([string]$stdoutTask.GetAwaiter().GetResult()) + [Environment]::NewLine + ([string]$stderrTask.GetAwaiter().GetResult())).Trim())
        }
    }
    finally {
        $process.Dispose()
    }
}

$python = Get-PythonCommand
$candidateSha = Get-GitHead -RepositoryPath $RootPath
$steps = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

Write-Host ("LOCAL_PROOF candidateSha={0} outputRoot={1}" -f $candidateSha, $OutputRoot)

# 1) Meta contracts
$meta = Invoke-CapturedProcess -FilePath $python -ArgumentList @('-m', 'unittest', 'tests.test_automated_test_floor', '-q') -WorkingDirectory $RootPath
$metaOk = ($meta.ExitCode -eq 0)
$steps.Add([ordered]@{
        id       = 'meta-contracts'
        exitCode = $meta.ExitCode
        status   = $(if ($metaOk) { 'PASS' } else { 'FAIL' })
        detail   = $(if ($metaOk) { 'unittest meta contracts passed' } else { 'meta contracts failed' })
    })
if (-not $metaOk) {
    $failures.Add('meta-contracts failed')
    Write-Host $meta.Combined
}

# 2) Healthy floor
$floorOut = Join-Path $OutputRoot 'healthy-floor'
New-Item -ItemType Directory -Force -Path $floorOut | Out-Null
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$floor = Invoke-CapturedProcess -FilePath $pwsh -ArgumentList @('-NoLogo', '-NoProfile', '-File', $floorRunner, '-OutputRoot', $floorOut) -WorkingDirectory $RootPath
$floorOk = ($floor.ExitCode -eq 0)
$steps.Add([ordered]@{
        id       = 'healthy-floor'
        exitCode = $floor.ExitCode
        status   = $(if ($floorOk) { 'PASS' } else { 'FAIL' })
        detail   = $(if ($floorOk) { 'canonical floor PASS' } else { 'canonical floor FAIL' })
        receipt   = (Join-Path $floorOut 'automated-test-floor-receipt.json')
    })
if (-not $floorOk) {
    $failures.Add('healthy-floor failed')
    Write-Host $floor.Combined
}

# 3) Isolated negative canary (must FAIL)
$canaryDir = Join-Path $OutputRoot 'canary'
New-Item -ItemType Directory -Force -Path $canaryDir | Out-Null
$canaryManifest = Join-Path $canaryDir 'canary-manifest.json'
$canaryOut = Join-Path $canaryDir 'out'
$canaryManifestObject = [ordered]@{
    schemaVersion = 1
    manifestId    = 'agentswitchboard.automated-test-floor.v1'
    proofLevel    = 'static-test'
    proofCeiling  = 'local negative canary only'
    determinism   = [ordered]@{
        pythonHashSeed  = '0'
        timezone        = 'UTC'
        networkAllowed  = $false
        mutationAllowed = $false
    }
    failClosed    = [ordered]@{ zeroUnittestCases = $true }
    gates         = @(
        [ordered]@{
            id                   = 'script-canary-fail'
            runner               = 'python-script'
            path                 = $canaryRel
            required             = $true
            platforms            = @('windows', 'linux', 'macos')
            expectStdoutContains = @('PASS')
            proof                = 'isolated negative canary fixture'
        }
    )
}
($canaryManifestObject | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $canaryManifest -Encoding utf8
$canary = Invoke-CapturedProcess -FilePath $pwsh -ArgumentList @('-NoLogo', '-NoProfile', '-File', $floorRunner, '-ManifestPath', $canaryManifest, '-OutputRoot', $canaryOut) -WorkingDirectory $RootPath
$canaryFailedAsExpected = ($canary.ExitCode -ne 0) -and (($canary.Combined -match 'script-canary-fail') -or ($canary.Combined -match 'CANARY_DEFECT') -or ($canary.Combined -match 'AUTOMATED_TEST_FLOOR: FAIL'))
$steps.Add([ordered]@{
        id       = 'negative-canary'
        exitCode = $canary.ExitCode
        status   = $(if ($canaryFailedAsExpected) { 'PASS' } else { 'FAIL' })
        detail   = $(if ($canaryFailedAsExpected) { 'isolated canary failed as required' } else { 'canary did not fail closed' })
        receipt   = (Join-Path $canaryOut 'automated-test-floor-receipt.json')
    })
if (-not $canaryFailedAsExpected) {
    $failures.Add('negative-canary did not fail closed')
    Write-Host $canary.Combined
}

$overall = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
$packet = [ordered]@{
    schema       = 'agentswitchboard.automated-test-floor.local-proof.v1'
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    candidateSha = $candidateSha
    result       = $overall
    proofCeiling = 'Local static proof only. Does not consume GitHub Actions minutes and does not grant merge/release/deploy authority.'
    steps        = @($steps)
    failures     = @($failures)
    outputs      = [ordered]@{
        healthyFloorReceipt = (Join-Path $floorOut 'automated-test-floor-receipt.json')
        canaryReceipt       = (Join-Path $canaryOut 'automated-test-floor-receipt.json')
        packetJson          = (Join-Path $OutputRoot 'local-proof-packet.json')
        packetMd            = (Join-Path $OutputRoot 'local-proof-packet.md')
    }
}

$jsonPath = Join-Path $OutputRoot 'local-proof-packet.json'
$mdPath = Join-Path $OutputRoot 'local-proof-packet.md'
($packet | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $jsonPath -Encoding utf8

$md = [System.Collections.Generic.List[string]]::new()
[void]$md.Add('# Automated test floor local proof packet')
[void]$md.Add('')
[void]$md.Add(('Result: {0}' -f $overall))
[void]$md.Add(('Candidate SHA: {0}' -f $candidateSha))
[void]$md.Add(('Proof ceiling: {0}' -f [string]$packet.proofCeiling))
[void]$md.Add('')
[void]$md.Add('| Step | Status | Detail |')
[void]$md.Add('|---|---|---|')
foreach ($step in $steps) {
    [void]$md.Add(('| {0} | {1} | {2} |' -f $step.id, $step.status, ([string]$step.detail -replace '\|', '/')))
}
($md -join [Environment]::NewLine) | Set-Content -LiteralPath $mdPath -Encoding utf8

Write-Host ("LOCAL_PROOF_PACKET_JSON={0}" -f $jsonPath)
Write-Host ("LOCAL_PROOF_PACKET_MD={0}" -f $mdPath)
Write-Host ("AUTOMATED_TEST_FLOOR_LOCAL_PROOF: {0}" -f $overall)

if ($overall -ne 'PASS') {
    exit 1
}
exit 0
