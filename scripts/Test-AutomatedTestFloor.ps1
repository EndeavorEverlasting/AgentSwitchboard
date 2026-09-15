[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot),
    [string]$ManifestPath,
    [string]$OutputRoot,
    [switch]$ListOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path $RootPath '.ai/harness/automated-test-floor.manifest.json'
}
$ManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $tempRoot = [Environment]::GetEnvironmentVariable('RUNNER_TEMP')
    if ([string]::IsNullOrWhiteSpace($tempRoot)) {
        $tempRoot = [IO.Path]::GetTempPath()
    }
    $OutputRoot = Join-Path $tempRoot ('agentswitchboard-automated-test-floor-' + [Guid]::NewGuid().ToString('N'))
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$OutputRoot = (Resolve-Path -LiteralPath $OutputRoot).Path

function Get-PlatformId {
    if ($IsWindows -or $env:OS -match 'Windows') { return 'windows' }
    if ($IsLinux) { return 'linux' }
    if ($IsMacOS) { return 'macos' }
    return 'unknown'
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
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [hashtable]$Environment
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
    if ($null -ne $Environment) {
        foreach ($key in $Environment.Keys) {
            $psi.Environment[$key] = [string]$Environment[$key]
        }
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            StdOut   = [string]$stdout
            StdErr   = [string]$stderr
            Combined = ((([string]$stdout) + [Environment]::NewLine + ([string]$stderr)).Trim())
        }
    }
    finally {
        $process.Dispose()
    }
}

function Get-UnittestCaseCount([string]$CombinedOutput) {
    if ($CombinedOutput -match '(?m)^Ran\s+(\d+)\s+tests?\b') {
        return [int]$Matches[1]
    }
    return $null
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
if ($manifest.manifestId -ne 'agentswitchboard.automated-test-floor.v1') {
    throw "Unexpected manifestId: $($manifest.manifestId)"
}
if ($null -eq $manifest.gates -or @($manifest.gates).Count -lt 1) {
    throw 'FAIL-CLOSED: automated test floor manifest declares zero gates.'
}

$platform = Get-PlatformId
$python = Get-PythonCommand
$candidateSha = Get-GitHead -RepositoryPath $RootPath
$envMap = @{
    PYTHONHASHSEED                 = [string]$manifest.determinism.pythonHashSeed
    TZ                             = [string]$manifest.determinism.timezone
    PYTHONUTF8                     = '1'
    PYTHONIOENCODING               = 'utf-8'
    AGENTSWITCHBOARD_TEST_FLOOR    = '1'
}

$results = [System.Collections.Generic.List[object]]::new()
$failures = [System.Collections.Generic.List[string]]::new()
$passCount = 0
$failCount = 0
$skipCount = 0

Write-Host ("AUTOMATED_TEST_FLOOR candidateSha={0} platform={1} manifest={2}" -f $candidateSha, $platform, $ManifestPath)

foreach ($gate in @($manifest.gates)) {
    $gateId = [string]$gate.id
    $runner = [string]$gate.runner
    $required = [bool]$gate.required
    $platforms = @($gate.platforms | ForEach-Object { [string]$_ })
    $status = 'PASS'
    $detail = ''
    $exitCode = $null
    $testsRan = $null
    $combined = ''

    if ($ListOnly) {
        Write-Host ("[LIST] {0} runner={1} required={2} platforms={3}" -f $gateId, $runner, $required, ($platforms -join ','))
        continue
    }

    if ($platforms.Count -gt 0 -and ($platforms -notcontains $platform)) {
        $status = 'SKIP'
        $detail = "platform '$platform' not in [$($platforms -join ', ')]"
        $skipCount += 1
        Write-Host ("[SKIP] {0}: {1}" -f $gateId, $detail)
        $results.Add([ordered]@{
                id       = $gateId
                runner   = $runner
                required = $required
                status   = $status
                detail   = $detail
                exitCode = $exitCode
                testsRan = $testsRan
            })
        continue
    }

    try {
        switch ($runner) {
            'python-script' {
                $rel = [string]$gate.path
                $full = Join-Path $RootPath $rel
                if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                    throw "missing required path: $rel"
                }
                $proc = Invoke-CapturedProcess -FilePath $python -ArgumentList @($full) -WorkingDirectory $RootPath -Environment $envMap
                $exitCode = [int]$proc.ExitCode
                $combined = [string]$proc.Combined
                if ($exitCode -ne 0) {
                    throw "exit $exitCode"
                }
                foreach ($token in @($gate.expectStdoutContains)) {
                    if ($combined -notlike ("*{0}*" -f [string]$token)) {
                        throw "stdout missing expected token: $token"
                    }
                }
            }
            'python-unittest' {
                $modules = @($gate.modules | ForEach-Object { [string]$_ })
                if ($modules.Count -lt 1) {
                    throw 'unittest gate declares zero modules'
                }
                $args = @('-m', 'unittest') + $modules + @('-q')
                $proc = Invoke-CapturedProcess -FilePath $python -ArgumentList $args -WorkingDirectory $RootPath -Environment $envMap
                $exitCode = [int]$proc.ExitCode
                $combined = [string]$proc.Combined
                $testsRan = Get-UnittestCaseCount -CombinedOutput $combined
                if ($combined -match 'NO TESTS RAN' -or $null -eq $testsRan -or $testsRan -lt 1) {
                    throw "FAIL-CLOSED: zero unittest cases (testsRan=$testsRan exit=$exitCode)"
                }
                $minTests = 1
                if ($null -ne $gate.minTests) { $minTests = [int]$gate.minTests }
                if ($testsRan -lt $minTests) {
                    throw "FAIL-CLOSED: testsRan=$testsRan below minTests=$minTests"
                }
                if ($exitCode -ne 0) {
                    throw "exit $exitCode after $testsRan tests"
                }
            }
            'pwsh-file' {
                $rel = [string]$gate.path
                $full = Join-Path $RootPath $rel
                if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
                    throw "missing required path: $rel"
                }
                $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
                $proc = Invoke-CapturedProcess -FilePath $pwsh -ArgumentList @('-NoLogo', '-NoProfile', '-File', $full) -WorkingDirectory $RootPath -Environment $envMap
                $exitCode = [int]$proc.ExitCode
                $combined = [string]$proc.Combined
                if ($exitCode -ne 0) {
                    throw "exit $exitCode"
                }
            }
            default {
                throw "unsupported runner: $runner"
            }
        }
        $passCount += 1
        Write-Host ("[PASS] {0}" -f $gateId)
    }
    catch {
        $detail = [string]$_.Exception.Message
        if ($required) {
            $status = 'FAIL'
            $failCount += 1
            $failures.Add("$gateId`: $detail")
            Write-Host ("[FAIL] {0}: {1}" -f $gateId, $detail)
            if (-not [string]::IsNullOrWhiteSpace($combined)) {
                $tail = if ($combined.Length -gt 1500) { $combined.Substring($combined.Length - 1500) } else { $combined }
                Write-Host $tail
            }
        }
        else {
            $status = 'SKIP'
            $skipCount += 1
            $detail = "optional gate failed: $detail"
            Write-Host ("[SKIP] {0}: {1}" -f $gateId, $detail)
        }
    }

    $results.Add([ordered]@{
            id       = $gateId
            runner   = $runner
            required = $required
            status   = $status
            detail   = $detail
            exitCode = $exitCode
            testsRan = $testsRan
        })
}

if ($ListOnly) {
    Write-Host ("LISTED {0} gates" -f @($manifest.gates).Count)
    exit 0
}

$requiredGateCount = @($manifest.gates | Where-Object { [bool]$_.required }).Count
if ($requiredGateCount -lt 1) {
    $failures.Add('FAIL-CLOSED: manifest declares zero required gates')
    $failCount += 1
}

$requiredExecuted = @($results | Where-Object { $_.required -and $_.status -in @('PASS', 'FAIL') }).Count
$requiredPass = @($results | Where-Object { $_.required -and $_.status -eq 'PASS' }).Count
if ($requiredExecuted -lt 1) {
    $failures.Add('FAIL-CLOSED: zero required gates executed (all missing or platform-skipped)')
    $failCount += 1
}

$overall = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }

$generatorPath = $MyInvocation.MyCommand.Path
$manifestSha = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
$generatorSha = (Get-FileHash -LiteralPath $generatorPath -Algorithm SHA256).Hash.ToLowerInvariant()
$trigger = if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_ACTIONS) -and $env:GITHUB_ACTIONS -eq 'true') {
    'github-actions'
} else {
    'local-cli'
}

$receipt = [ordered]@{
    schema           = 'agentswitchboard.automated-test-floor.receipt.v1'
    generatedUtc     = [DateTime]::UtcNow.ToString('o')
    candidateSha     = $candidateSha
    platform         = $platform
    manifestId       = [string]$manifest.manifestId
    manifestPath     = $ManifestPath
    proofLevel       = [string]$manifest.proofLevel
    proofCeiling     = [string]$manifest.proofCeiling
    result           = $overall
    provenance       = [ordered]@{
        trigger              = $trigger
        inputManifestSha256  = $manifestSha
        generatorPath        = $generatorPath
        generatorSha256      = $generatorSha
        ownedOutputs         = @(
            'automated-test-floor-receipt.json'
            'automated-test-floor-receipt.md'
        )
        outputPolicy         = 'ephemeral-outside-checkout-by-default'
        committedGeneratedCode = $false
        loopGuard            = 'receipts are not tracked; generation cannot create a generate-commit-generate cycle'
    }
    summary          = [ordered]@{
        requiredGates = $requiredGateCount
        pass          = $passCount
        fail          = $failCount
        skip          = $skipCount
        requiredPass  = $requiredPass
    }
    determinism      = $manifest.determinism
    gates            = @($results)
    failures         = @($failures)
}

$jsonPath = Join-Path $OutputRoot 'automated-test-floor-receipt.json'
$mdPath = Join-Path $OutputRoot 'automated-test-floor-receipt.md'
($receipt | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $jsonPath -Encoding utf8

$md = [System.Collections.Generic.List[string]]::new()
[void]$md.Add('# Automated test floor receipt')
[void]$md.Add('')
[void]$md.Add(('Result: {0}' -f $overall))
[void]$md.Add(('Candidate SHA: {0}' -f $candidateSha))
[void]$md.Add(('Platform: {0}' -f $platform))
[void]$md.Add(('Required pass/fail/skip: {0} / {1} / {2}' -f $requiredPass, $failCount, $skipCount))
[void]$md.Add(('Proof level: {0}' -f [string]$manifest.proofLevel))
[void]$md.Add(('Proof ceiling: {0}' -f [string]$manifest.proofCeiling))
[void]$md.Add(('Trigger: {0}' -f $trigger))
[void]$md.Add(('Manifest SHA-256: {0}' -f $manifestSha))
[void]$md.Add(('Generator SHA-256: {0}' -f $generatorSha))
[void]$md.Add('')
[void]$md.Add('| Gate | Runner | Status | Detail |')
[void]$md.Add('|---|---|---|---|')
foreach ($row in $results) {
    $safeDetail = ([string]$row.detail) -replace '\|', '/'
    [void]$md.Add(('| {0} | {1} | {2} | {3} |' -f $row.id, $row.runner, $row.status, $safeDetail))
}
if ($failures.Count -gt 0) {
    [void]$md.Add('')
    [void]$md.Add('## Failures')
    foreach ($failure in $failures) {
        [void]$md.Add(('- {0}' -f $failure))
    }
}
($md -join [Environment]::NewLine) | Set-Content -LiteralPath $mdPath -Encoding utf8

Write-Host ("RECEIPT_JSON={0}" -f $jsonPath)
Write-Host ("RECEIPT_MD={0}" -f $mdPath)
Write-Host ("AUTOMATED_TEST_FLOOR: {0}" -f $overall)

if ($overall -ne 'PASS') {
    exit 1
}
exit 0
