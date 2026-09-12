[CmdletBinding()]
param([string]$RootPath = (Split-Path -Parent $PSScriptRoot))

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$preflightPath = Join-Path $RootPath 'tooling/pi/Test-PiWorkstationPrereqs.ps1'
$verificationPath = Join-Path $RootPath 'tooling/pi/harness/upstream-verification.json'
$pwshPath = (Get-Process -Id $PID).Path
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Check {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Message
    )
    if ($Condition) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("${Name}: $Message") }
}

function Read-JsonReport {
    param([Parameter(Mandatory)][string]$Directory)
    $path = Join-Path $Directory 'pi-workstation-prereqs.json'
    Check -Condition (Test-Path -LiteralPath $path -PathType Leaf) -Name "report/$Directory" -Message 'JSON report was not created'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("AgentSwitchboard-PiPrereqContracts-" + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $tempRoot -Force
try {
    $missingRoot = Join-Path $tempRoot 'missing-verification'
    $missingOutput = Join-Path $tempRoot 'missing-output'
    $null = New-Item -ItemType Directory -Path $missingRoot -Force
    & $pwshPath -NoLogo -NoProfile -File $preflightPath -RootPath $missingRoot -OutputDirectory $missingOutput *> $null
    $missingExit = $LASTEXITCODE
    Check -Condition ($missingExit -eq 1) -Name 'missing/exit' -Message "expected exit 1, got $missingExit"
    $missing = Read-JsonReport -Directory $missingOutput
    if ($null -ne $missing) {
        Check -Condition ($missing.schema -eq 'agentswitchboard.pi-workstation-prereqs.v1') -Name 'missing/schema' -Message 'structured schema missing'
        Check -Condition ($missing.status -eq 'blocked-prerequisite') -Name 'missing/status' -Message 'missing verification did not block the preflight'
        Check -Condition ($missing.error.code -eq 'UPSTREAM_VERIFICATION_MISSING') -Name 'missing/error-code' -Message 'missing verification error code is incorrect'
        Check -Condition (-not [string]::IsNullOrWhiteSpace([string]$missing.recoveryAction)) -Name 'missing/recovery' -Message 'recovery action is missing'
        Check -Condition ([string]$missing.recoveryAction -match 'upstream-verification\.json') -Name 'missing/recovery-target' -Message 'recovery action does not identify the verification record'
    }

    $normalOutput = Join-Path $tempRoot 'normal-output'
    & $pwshPath -NoLogo -NoProfile -File $preflightPath -RootPath $RootPath -OutputDirectory $normalOutput -NoNetwork -AllowUnready *> $null
    $normalExit = $LASTEXITCODE
    Check -Condition ($normalExit -eq 0) -Name 'normal/report-only-exit' -Message "report-only preflight returned $normalExit"
    $normal = Read-JsonReport -Directory $normalOutput
    if ($null -ne $normal) {
        foreach ($name in @('node', 'npm', 'git', 'bash', 'pi')) {
            $evidence = $normal.observed.$name
            $paths = @($evidence.paths)
            Check -Condition ($paths.Count -le 8) -Name "paths/$name/bounded" -Message "reported $($paths.Count) paths; limit is 8"
            Check -Condition ([int]$evidence.pathCount -ge $paths.Count) -Name "paths/$name/count" -Message 'pathCount is smaller than visible path count'
            Check -Condition ([int]$evidence.pathsOmitted -eq ([int]$evidence.pathCount - $paths.Count)) -Name "paths/$name/omitted" -Message 'omitted count does not match total minus visible paths'
            $expectedState = if ([int]$evidence.pathCount -eq 0) { 'empty' } else { 'present' }
            Check -Condition ($evidence.pathState -eq $expectedState) -Name "paths/$name/state" -Message "expected $expectedState, got $($evidence.pathState)"
        }
    }

    if ($IsWindows) {
        $bashCandidate = @(
            'C:\Program Files\Git\bin\bash.exe'
            @(Get-Command bash.exe, bash -All -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.Source })
        ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
        Check -Condition (-not [string]::IsNullOrWhiteSpace([string]$bashCandidate)) -Name 'configured-shell/candidate' -Message 'no Bash executable is available to exercise project shellPath precedence'
        if ($bashCandidate) {
            $configuredRoot = Join-Path $tempRoot 'configured-shell'
            $configuredHarness = Join-Path $configuredRoot 'tooling/pi/harness'
            $configuredPi = Join-Path $configuredRoot '.pi'
            $configuredOutput = Join-Path $tempRoot 'configured-output'
            $null = New-Item -ItemType Directory -Path $configuredHarness -Force
            $null = New-Item -ItemType Directory -Path $configuredPi -Force
            Copy-Item -LiteralPath $verificationPath -Destination (Join-Path $configuredHarness 'upstream-verification.json')
            [ordered]@{ shellPath = [string]$bashCandidate } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $configuredPi 'settings.json') -Encoding utf8

            & $pwshPath -NoLogo -NoProfile -File $preflightPath -RootPath $configuredRoot -OutputDirectory $configuredOutput -NoNetwork -AllowUnready *> $null
            $configuredExit = $LASTEXITCODE
            Check -Condition ($configuredExit -eq 0) -Name 'configured-shell/exit' -Message "configured-shell report returned $configuredExit"
            $configured = Read-JsonReport -Directory $configuredOutput
            if ($null -ne $configured) {
                $expectedBash = (Resolve-Path -LiteralPath $bashCandidate).Path
                $observedBash = @($configured.observed.bash.paths) | Select-Object -First 1
                Check -Condition ($observedBash -eq $expectedBash) -Name 'configured-shell/precedence' -Message "expected configured shell first: $expectedBash; observed: $observedBash"
                Check -Condition ($configured.observed.bash.ready -eq $true) -Name 'configured-shell/ready' -Message 'configured Bash path did not satisfy the Bash prerequisite'
            }
        }
    }

    Write-Host 'PI WORKSTATION PREREQUISITE CONTRACTS' -ForegroundColor Cyan
    $passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
    $failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
    Write-Host ''
    Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
    if ($failures.Count -gt 0) { exit 1 }
    exit 0
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
