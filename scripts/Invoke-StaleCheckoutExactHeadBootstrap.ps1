[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$SourceRepository,

    [Parameter(Mandatory)]
    [ValidatePattern('^refs/heads/[A-Za-z0-9._/-]+$')]
    [string]$RemoteRef,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$ExpectedHead,

    [ValidateSet('validate', 'ready')]
    [string]$Mode = 'ready',

    [switch]$OpenReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

$startedUtc = [DateTime]::UtcNow
$expectedNormalized = $ExpectedHead.ToLowerInvariant()
$sourceRoot = (Resolve-Path -LiteralPath $SourceRepository -ErrorAction Stop).Path
$runnerPath = Join-Path $env:TEMP ("AgentSwitchboard-ExactHead-{0}.ps1" -f $expectedNormalized.Substring(0, 8))

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = @(& git.exe -C $sourceRoot --no-pager @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "git $($Arguments -join ' ') failed with exit code $exitCode.`n$($output -join "`n")"
    }
    @($output | ForEach-Object { [string]$_ })
}

$allowedOrigins = @(
    'https://github.com/EndeavorEverlasting/AgentSwitchboard.git',
    'https://github.com/EndeavorEverlasting/AgentSwitchboard',
    'git@github.com:EndeavorEverlasting/AgentSwitchboard.git'
)

$originUrl = (Invoke-Git -Arguments @('remote', 'get-url', 'origin') | Select-Object -First 1).Trim()
if ($originUrl -notin $allowedOrigins) {
    throw "Unexpected origin: $originUrl"
}

Write-Host '=== STALE CHECKOUT — READ ONLY ===' -ForegroundColor Cyan
Write-Host "Repository: $sourceRoot"
Write-Host "Origin:     $originUrl"
Invoke-Git -Arguments @('status', '--short') | ForEach-Object { Write-Host $_ }
Invoke-Git -Arguments @('log', '--oneline', '--decorate', '-5') | ForEach-Object { Write-Host $_ }

Write-Host '=== FETCH EXACT REMOTE REF ===' -ForegroundColor Cyan
Invoke-Git -Arguments @('fetch', '--no-tags', 'origin', $RemoteRef) | Out-Null
$fetchedHead = (Invoke-Git -Arguments @('rev-parse', 'FETCH_HEAD') | Select-Object -First 1).Trim().ToLowerInvariant()
if ($fetchedHead -ne $expectedNormalized) {
    throw "Fetched head mismatch. Expected $expectedNormalized; fetched $fetchedHead."
}

$validatorSpec = "${expectedNormalized}:scripts/Invoke-TechnicianExactHeadValidation.ps1"
$validatorSource = Invoke-Git -Arguments @('show', $validatorSpec)
if ($validatorSource.Count -eq 0) {
    throw "The exact fetched head does not contain the exact-head validator: $validatorSpec"
}
[IO.File]::WriteAllLines($runnerPath, [string[]]$validatorSource, [Text.UTF8Encoding]::new($false))

try {
    $arguments = @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $runnerPath,
        '-RepoRoot', $sourceRoot,
        '-RemoteRef', $RemoteRef,
        '-ExpectedHead', $expectedNormalized
    )
    if ($Mode -eq 'ready') {
        $arguments += '-RunReadiness'
    }

    $env:AGENT_SWITCHBOARD_NO_PAUSE = '1'
    & pwsh.exe @arguments
    $validatorExitCode = $LASTEXITCODE
    if ($validatorExitCode -ne 0) {
        throw "Exact-head validation failed with exit code $validatorExitCode."
    }

    $runRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\exact-head-validation\runs'
    $validationJson = Get-ChildItem -LiteralPath $runRoot -Filter 'exact-head-validation.json' -File -Recurse |
        Where-Object { $_.LastWriteTimeUtc -ge $startedUtc } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if (-not $validationJson) {
        throw 'Exact-head validation exited successfully without producing a fresh registered JSON artifact.'
    }

    $validation = Get-Content -LiteralPath $validationJson.FullName -Raw | ConvertFrom-Json
    if ($validation.status -ne 'passed') {
        throw "Exact-head artifact status is not passed: $($validationJson.FullName)"
    }
    if (([string]$validation.verifiedHead).ToLowerInvariant() -ne $expectedNormalized) {
        throw "Exact-head artifact verified a different commit: $($validation.verifiedHead)"
    }
    if (-not $validation.worktreeClean) {
        throw "Exact-head artifact does not prove a clean worktree: $($validationJson.FullName)"
    }
    if ($Mode -eq 'ready' -and -not $validation.readinessRequested) {
        throw "Ready mode completed without readiness proof: $($validationJson.FullName)"
    }

    $validationReportPath = Join-Path $validationJson.Directory.FullName 'exact-head-validation.md'
    if (-not (Test-Path -LiteralPath $validationReportPath -PathType Leaf)) {
        throw "Exact-head Markdown report is missing: $validationReportPath"
    }

    $evidenceRoot = Join-Path $env:LOCALAPPDATA (
        "AgentSwitchboard\stale-checkout-exact-head\runs\{0}-{1}" -f
        (Get-Date -Format 'yyyyMMddTHHmmssZ'),
        $expectedNormalized.Substring(0, 8)
    )
    $null = New-Item -ItemType Directory -Path $evidenceRoot -Force

    $result = [ordered]@{
        schema = 'agentswitchboard.stale-checkout-exact-head-bootstrap.v1'
        generatedAt = (Get-Date).ToUniversalTime().ToString('o')
        sourceRepository = $sourceRoot
        origin = $originUrl
        remoteRef = $RemoteRef
        expectedHead = $expectedNormalized
        fetchedHead = $fetchedHead
        extractedValidator = $validatorSpec
        temporaryRunner = $runnerPath
        mode = $Mode
        validationArtifact = $validationJson.FullName
        validationReport = $validationReportPath
        status = 'passed'
        proofLevel = 'stale-checkout-bootstrap-delegated-exact-head-proof'
        proofCeiling = 'Proves that a stale source checkout safely fetched the named ref, extracted the repository-owned exact-head validator from the exact commit, and read back its fresh artifact. It does not exceed the proof ceiling of the delegated exact-head artifact.'
    }

    $jsonPath = Join-Path $evidenceRoot 'stale-checkout-bootstrap.json'
    $mdPath = Join-Path $evidenceRoot 'stale-checkout-bootstrap.md'
    Write-Utf8NoBom -Path $jsonPath -Content ($result | ConvertTo-Json -Depth 8)

    $reportText = @"
# AgentSwitchboard Stale-Checkout Exact-Head Bootstrap

- Status: **PASSED**
- Remote ref: ``$RemoteRef``
- Expected and fetched HEAD: ``$expectedNormalized``
- Source checkout preserved: ``$sourceRoot``
- Exact validator extracted: ``$validatorSpec``
- Delegated validation JSON: ``$($validationJson.FullName)``
- Delegated validation report: ``$validationReportPath``

## Proof ceiling

$($result.proofCeiling)
"@
    Write-Utf8NoBom -Path $mdPath -Content $reportText

    Write-Host '=== STALE-CHECKOUT BOOTSTRAP PROOF ===' -ForegroundColor Green
    Write-Host "Verified HEAD: $expectedNormalized"
    Write-Host "JSON:          $jsonPath"
    Write-Host "Report:        $mdPath"
    Get-Content -LiteralPath $mdPath

    if ($OpenReport) {
        Start-Process notepad.exe -ArgumentList ('"{0}"' -f $mdPath)
    }
}
finally {
    Remove-Item -LiteralPath $runnerPath -Force -ErrorAction SilentlyContinue
}
