[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$ExpectedHead,

    [string]$FirstMatePath,

    [string]$EvidenceRoot,

    [switch]$ContractOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7+ (pwsh) is required for the Windows-to-WSL First Mate bridge.'
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ManifestPath = Join-Path $Root 'tooling\firstmate\harness\operational\manifest.json'
$ArtifactRegistryPath = Join-Path $Root 'tooling\firstmate\harness\operational\artifact-registry.json'
$ValidatorRegistryPath = Join-Path $Root 'tooling\firstmate\harness\operational\validator-registry.json'

function Assert-LastExit {
    param(
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [Parameter(Mandatory = $true)][string]$Operation
    )
    if ($ExitCode -ne 0) {
        throw "$Operation failed with exit code $ExitCode."
    }
}

function Invoke-WslProcess {
    param(
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$Command,
        [hashtable]$Environment = @{}
    )

    $wsl = Get-Command wsl.exe -ErrorAction Stop
    $resolvedWorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $wsl.Source
    $psi.WorkingDirectory = $resolvedWorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    [void]$psi.ArgumentList.Add('--exec')
    [void]$psi.ArgumentList.Add('bash')
    [void]$psi.ArgumentList.Add('-lc')
    [void]$psi.ArgumentList.Add($Command)

    if ($Environment.Count -gt 0) {
        foreach ($name in $Environment.Keys) {
            $psi.Environment[[string]$name] = [string]$Environment[$name]
        }
        $newWslEnv = ($Environment.Keys | ForEach-Object { [string]$_ }) -join ':'
        $existingWslEnv = $psi.Environment['WSLENV']
        if ([string]::IsNullOrWhiteSpace($existingWslEnv)) {
            $psi.Environment['WSLENV'] = $newWslEnv
        }
        else {
            $psi.Environment['WSLENV'] = "$existingWslEnv`:$newWslEnv"
        }
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    if (-not $process.Start()) {
        throw 'Unable to start wsl.exe.'
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdout
        Stderr = $stderr
    }
}

function Add-WslDiagnostic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][string]$Text
    )
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return
    }
    Add-Content -LiteralPath $Path -Value "===== $Stage ====="
    Add-Content -LiteralPath $Path -Value $Text.TrimEnd()
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Missing First Mate operational manifest: $ManifestPath"
}
if (-not (Test-Path -LiteralPath $ArtifactRegistryPath)) {
    throw "Missing First Mate artifact registry: $ArtifactRegistryPath"
}
if (-not (Test-Path -LiteralPath $ValidatorRegistryPath)) {
    throw "Missing First Mate validator registry: $ValidatorRegistryPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$artifacts = Get-Content -LiteralPath $ArtifactRegistryPath -Raw | ConvertFrom-Json
$validators = Get-Content -LiteralPath $ValidatorRegistryPath -Raw | ConvertFrom-Json

if ($manifest.components.windows_wsl_bridge -ne 'Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1') {
    throw 'Operational manifest does not register the Windows-to-WSL bridge.'
}
if (-not ($artifacts.artifacts.id -contains 'windows-wsl-runtime-proof')) {
    throw 'Artifact registry does not register windows-wsl-runtime-proof.'
}
if (-not ($validators.validators.id -contains 'firstmate-windows-wsl-bridge-contract')) {
    throw 'Validator registry does not register the Windows-to-WSL bridge contract.'
}

$actualHead = (& git -C $Root rev-parse HEAD).Trim()
Assert-LastExit -ExitCode $LASTEXITCODE -Operation 'Resolve exact AgentSwitchboard HEAD'
if ($actualHead -ne $ExpectedHead.ToLowerInvariant()) {
    throw "Exact-head mismatch. Expected=$ExpectedHead Actual=$actualHead"
}

if ($ContractOnly) {
    Write-Host '[PASS] FIRSTMATE_WINDOWS_WSL_BRIDGE_CONTRACT'
    Write-Host "HEAD=$actualHead"
    exit 0
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'WSL is not installed or wsl.exe is unavailable.'
}

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $EvidenceRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('AgentSwitchboard\firstmate-windows-wsl\' + $actualHead.Substring(0, 8))
}
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$EvidenceRoot = (Resolve-Path -LiteralPath $EvidenceRoot).Path

$ReportPath = Join-Path $EvidenceRoot 'firstmate-harness-report.md'
$ProbePath = Join-Path $EvidenceRoot 'firstmate-floor.txt'
$RoutePath = Join-Path $EvidenceRoot 'firstmate-route.json'
$WslDiagnosticsPath = Join-Path $EvidenceRoot 'wsl-stderr.log'

Set-Content -LiteralPath $WslDiagnosticsPath -Value @(
    "HEAD=$actualHead"
    "WINDOWS_WORKTREE=$Root"
    "NOTE=WSL stderr is isolated from machine-readable stdout so warnings cannot corrupt path/JSON parsing."
)

$visibility = Invoke-WslProcess -WorkingDirectory $Root -Command 'set -euo pipefail; printf "WSL_PWD=%s\n" "$PWD"; git rev-parse HEAD'
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'visibility' -Text $visibility.Stderr
if ($visibility.ExitCode -ne 0) {
    throw "WSL cannot execute inside the exact AgentSwitchboard worktree. See $WslDiagnosticsPath"
}
$visibilityLines = @($visibility.Stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($visibilityLines.Count -lt 2 -or $visibilityLines[-1].Trim() -ne $actualHead) {
    throw "WSL did not resolve the same AgentSwitchboard HEAD. See $WslDiagnosticsPath"
}

$contract = Invoke-WslProcess -WorkingDirectory $Root -Command 'set -euo pipefail; bash Test-AgentSwitchboard-FirstMate-Harness.sh contract'
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'contract' -Text $contract.Stderr
if ($contract.ExitCode -ne 0) {
    Set-Content -LiteralPath (Join-Path $EvidenceRoot 'contract-stdout.txt') -Value $contract.Stdout
    throw "Owning First Mate harness contract failed. Evidence: $EvidenceRoot"
}
Write-Host $contract.Stdout.TrimEnd()

$report = Invoke-WslProcess -WorkingDirectory $Root -Command 'set -euo pipefail; python3 tooling/firstmate/harness/operational/Build-FirstMateHarnessReport.py --stdout'
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'report' -Text $report.Stderr
if ($report.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($report.Stdout)) {
    throw "Canonical operator report generation failed. See $WslDiagnosticsPath"
}
Set-Content -LiteralPath $ReportPath -Value $report.Stdout.TrimEnd()

$probeCommand = 'set -euo pipefail; bash tooling/firstmate/Test-FirstMateInterop.sh'
$probeEnvironment = @{}
if (-not [string]::IsNullOrWhiteSpace($FirstMatePath)) {
    $probeEnvironment['ASB_FIRSTMATE_PATH'] = $FirstMatePath
    $probeCommand += ' --firstmate "$ASB_FIRSTMATE_PATH"'
}
$probe = Invoke-WslProcess -WorkingDirectory $Root -Command $probeCommand -Environment $probeEnvironment
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'probe' -Text $probe.Stderr
Set-Content -LiteralPath $ProbePath -Value @(
    "EXIT_CODE=$($probe.ExitCode)"
    $probe.Stdout.TrimEnd()
    "WSL_STDERR=$WslDiagnosticsPath"
)
if ($probe.ExitCode -ne 0) {
    Write-Host '===== CANONICAL HARNESS REPORT ====='
    Get-Content -LiteralPath $ReportPath
    throw "First Mate read-only floor failed. Durable evidence: $ProbePath"
}

$route = Invoke-WslProcess -WorkingDirectory $Root -Command 'set -euo pipefail; python3 tooling/firstmate/harness/operational/Select-FirstMateWorkflow.py --parallel-writers 3 --firstmate-floor pass --platform linux-wsl'
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'route' -Text $route.Stderr
if ($route.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($route.Stdout)) {
    throw "First Mate route generation failed. See $WslDiagnosticsPath"
}
Set-Content -LiteralPath $RoutePath -Value $route.Stdout.TrimEnd()
$routeObject = $route.Stdout | ConvertFrom-Json
if ($routeObject.status -ne 'ready' -or $routeObject.route -ne 'firstmate-local-only' -or $routeObject.session_backend -ne 'tmux') {
    throw "Unexpected First Mate route. Evidence: $RoutePath"
}

Write-Host '===== CANONICAL HARNESS REPORT ====='
Get-Content -LiteralPath $ReportPath
Write-Host '===== FIRST MATE ROUTE ====='
Get-Content -LiteralPath $RoutePath
Write-Host '[PASS] FIRSTMATE_WINDOWS_WSL_RUNTIME_FLOOR'
Write-Host "HEAD=$actualHead"
Write-Host "REPORT=$ReportPath"
Write-Host "FLOOR_EVIDENCE=$ProbePath"
Write-Host "ROUTE=$RoutePath"
Write-Host "WSL_DIAGNOSTICS=$WslDiagnosticsPath"
