[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$ExpectedHead,

    [string]$SourceRepositoryPath,

    [string]$FirstMatePath,

    [string]$EvidenceRoot,

    [Parameter(Mandatory = $true)]
    [string]$WslDistribution,

    [switch]$ContractOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7+ (pwsh) is required for the First Mate physical-floor wrapper.'
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$BridgePath = Join-Path $Root 'Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1'
$ArtifactRegistryPath = Join-Path $Root 'tooling\firstmate\harness\operational\artifact-registry.json'

function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FileName
    $psi.WorkingDirectory = $env:SystemRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in $Arguments) {
        [void]$psi.ArgumentList.Add([string]$argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    if (-not $process.Start()) {
        throw "Unable to start $FileName."
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()

    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdoutTask.GetAwaiter().GetResult().Replace(([char]0).ToString(), '')
        Stderr = $stderrTask.GetAwaiter().GetResult().Replace(([char]0).ToString(), '')
    }
}

if (-not (Test-Path -LiteralPath $BridgePath)) {
    throw "Missing lower Windows-to-WSL bridge: $BridgePath"
}
if (-not (Test-Path -LiteralPath $ArtifactRegistryPath)) {
    throw "Missing First Mate artifact registry: $ArtifactRegistryPath"
}
$artifacts = Get-Content -LiteralPath $ArtifactRegistryPath -Raw | ConvertFrom-Json
if (-not ($artifacts.artifacts.id -contains 'windows-wsl-prerequisite-proof')) {
    throw 'Artifact registry does not register windows-wsl-prerequisite-proof.'
}

$actualHead = (& git -C $Root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to resolve the exact AgentSwitchboard HEAD.'
}
if ($actualHead -ne $ExpectedHead.ToLowerInvariant()) {
    throw "Exact-head mismatch. Expected=$ExpectedHead Actual=$actualHead"
}

if ($ContractOnly) {
    Write-Host '[PASS] FIRSTMATE_WINDOWS_WSL_PREREQUISITE_GATE_CONTRACT'
    Write-Host "HEAD=$actualHead"
    exit 0
}

$wsl = Get-Command wsl.exe -ErrorAction Stop
$pwsh = Get-Command pwsh -ErrorAction Stop

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $runId = "$($actualHead.Substring(0, 8))-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $EvidenceRoot = Join-Path ([System.IO.Path]::GetTempPath()) "AgentSwitchboard\firstmate-windows-wsl\$runId"
}
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$EvidenceRoot = (Resolve-Path -LiteralPath $EvidenceRoot).Path

$PrerequisitePath = Join-Path $EvidenceRoot 'firstmate-wsl-prerequisites.txt'
$PrerequisiteStderrPath = Join-Path $EvidenceRoot 'firstmate-wsl-prerequisites-stderr.log'
$BridgeStdoutPath = Join-Path $EvidenceRoot 'bridge-stdout.txt'
$BridgeStderrPath = Join-Path $EvidenceRoot 'bridge-stderr.txt'

$preflightCommand = @'
set -euo pipefail
required=(git gh tmux python3)
missing=()
for tool in "${required[@]}"; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing+=("$tool")
  fi
done
if ((${#missing[@]} > 0)); then
  printf 'STATUS=BLOCKED_MISSING_TOOLS\n'
  printf 'MISSING_TOOLS=%s\n' "${missing[*]}"
  printf 'NEXT_ACTION=sudo apt-get update && sudo apt-get install -y %s\n' "${missing[*]}"
  exit 44
fi
if ! gh auth status --hostname github.com >/dev/null 2>&1; then
  printf 'STATUS=BLOCKED_GITHUB_AUTH\n'
  printf 'NEXT_ACTION=gh auth login --hostname github.com --git-protocol https --web\n'
  exit 45
fi
printf 'STATUS=PASS\n'
for tool in "${required[@]}"; do
  printf 'TOOL_%s=%s\n' "${tool^^}" "$(command -v "$tool")"
done
printf 'GITHUB_AUTH=ready\n'
'@

$preflight = Invoke-CapturedProcess `
    -FileName $wsl.Source `
    -Arguments @('--distribution', $WslDistribution, '--exec', 'bash', '-lc', $preflightCommand.Replace("`r`n", "`n").Replace("`r", "`n"))

Set-Content -LiteralPath $PrerequisitePath -Value @(
    "HEAD=$actualHead"
    "WSL_DISTRIBUTION=$WslDistribution"
    $preflight.Stdout.TrimEnd()
    "STDERR=$PrerequisiteStderrPath"
)
Set-Content -LiteralPath $PrerequisiteStderrPath -Value $preflight.Stderr.TrimEnd()

if ($preflight.ExitCode -ne 0) {
    Write-Host '===== FIRST MATE WSL PREREQUISITE FLOOR ====='
    Get-Content -LiteralPath $PrerequisitePath
    $nextAction = [regex]::Match($preflight.Stdout, '(?m)^NEXT_ACTION=(.+)$')
    if ($nextAction.Success) {
        Write-Host "NEXT_ACTION=$($nextAction.Groups[1].Value.Trim())"
    }
    Write-Host "PREREQUISITE_EVIDENCE=$PrerequisitePath"
    throw "First Mate WSL prerequisite floor blocked before clone/test execution. Exit=$($preflight.ExitCode)"
}

$bridgeArguments = @(
    '-NoLogo',
    '-NoProfile',
    '-File', $BridgePath,
    '-ExpectedHead', $actualHead,
    '-EvidenceRoot', $EvidenceRoot,
    '-WslDistribution', $WslDistribution
)
if (-not [string]::IsNullOrWhiteSpace($SourceRepositoryPath)) {
    $bridgeArguments += @('-SourceRepositoryPath', $SourceRepositoryPath)
}
if (-not [string]::IsNullOrWhiteSpace($FirstMatePath)) {
    $bridgeArguments += @('-FirstMatePath', $FirstMatePath)
}

$bridge = Invoke-CapturedProcess -FileName $pwsh.Source -Arguments $bridgeArguments
Set-Content -LiteralPath $BridgeStdoutPath -Value $bridge.Stdout.TrimEnd()
Set-Content -LiteralPath $BridgeStderrPath -Value $bridge.Stderr.TrimEnd()

if ($bridge.ExitCode -ne 0) {
    if (-not [string]::IsNullOrWhiteSpace($bridge.Stdout)) {
        Write-Host $bridge.Stdout.TrimEnd()
    }
    Write-Host "PREREQUISITE_EVIDENCE=$PrerequisitePath"
    Write-Host "BRIDGE_STDOUT=$BridgeStdoutPath"
    Write-Host "BRIDGE_STDERR=$BridgeStderrPath"
    throw "First Mate lower bridge failed. Exit=$($bridge.ExitCode)"
}

if (-not [string]::IsNullOrWhiteSpace($bridge.Stdout)) {
    Write-Host $bridge.Stdout.TrimEnd()
}
Write-Host '[PASS] FIRSTMATE_WINDOWS_WSL_PHYSICAL_FLOOR'
Write-Host "HEAD=$actualHead"
Write-Host "WSL_DISTRIBUTION=$WslDistribution"
Write-Host "PREREQUISITE_EVIDENCE=$PrerequisitePath"
Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
