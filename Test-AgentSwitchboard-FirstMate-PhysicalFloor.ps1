[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$ExpectedHead,

    [string]$SourceRepositoryPath,
    [string]$FirstMatePath,
    [string]$EvidenceRoot,
    [string]$WslDistribution,

    [ValidateRange(10, 300)]
    [int]$PrerequisiteTimeoutSeconds = 60,

    [switch]$ContractOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7+ (pwsh) is required for the FirstMate physical-floor wrapper.'
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$BridgePath = Join-Path $Root 'Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1'
$IntegrationContractPath = Join-Path $Root 'tooling\firstmate\harness\integration-contract.json'
$ArtifactRegistryPath = Join-Path $Root 'tooling\firstmate\harness\operational\artifact-registry.json'
$UpstreamPinPath = Join-Path $Root 'tooling\firstmate\harness\upstream-pin.json'

function Normalize-NativeText {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return '' }
    return $Text.Replace(([char]0).ToString(), '')
}

function Invoke-CapturedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [hashtable]$Environment = @{},
        [string[]]$PathEnvironmentNames = @()
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

    # Mirror Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1: reviewed path vars cross
    # into WSL only through WSLENV /p (no wslpath). Non-path env still needs WSLENV
    # listing so bash -lc can read the override.
    $wslEnvEntries = @()
    $existingWslEnv = $psi.Environment['WSLENV']
    if (-not [string]::IsNullOrWhiteSpace($existingWslEnv)) {
        $wslEnvEntries += @($existingWslEnv -split ':' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    foreach ($name in $Environment.Keys) {
        $stringName = [string]$name
        $wslEnvEntries = @($wslEnvEntries | Where-Object {
            $entryName = (([string]$_ -split '/', 2)[0])
            $entryName -ine $stringName
        })
        $psi.Environment[$stringName] = [string]$Environment[$name]
        if ($PathEnvironmentNames -contains $stringName) {
            $wslEnvEntries += "$stringName/p"
        }
        else {
            $wslEnvEntries += $stringName
        }
    }
    if ($wslEnvEntries.Count -gt 0) {
        $psi.Environment['WSLENV'] = (@($wslEnvEntries | Select-Object -Unique) -join ':')
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    if (-not $process.Start()) { throw "Unable to start $FileName." }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    $timedOut = -not $completed
    if ($timedOut) {
        try {
            $process.Kill($true)
            $process.WaitForExit()
        }
        catch {}
    }

    return [pscustomobject]@{
        ExitCode = if ($timedOut) { 124 } else { $process.ExitCode }
        TimedOut = $timedOut
        Stdout = Normalize-NativeText -Text $stdoutTask.GetAwaiter().GetResult()
        Stderr = Normalize-NativeText -Text $stderrTask.GetAwaiter().GetResult()
    }
}

foreach ($required in @($BridgePath, $IntegrationContractPath, $ArtifactRegistryPath, $UpstreamPinPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing FirstMate physical-floor contract surface: $required"
    }
}

$integration = Get-Content -LiteralPath $IntegrationContractPath -Raw | ConvertFrom-Json
$artifacts = Get-Content -LiteralPath $ArtifactRegistryPath -Raw | ConvertFrom-Json
$canonicalDistribution = [string]$integration.platform_contract.wsl_distribution
if ([string]::IsNullOrWhiteSpace($WslDistribution)) {
    $WslDistribution = $canonicalDistribution
}
elseif ($WslDistribution -ne $canonicalDistribution) {
    throw "WSL distribution mismatch. Contract=$canonicalDistribution Requested=$WslDistribution"
}
if ($integration.platform_contract.windows_host_role -ne 'bridge_only') {
    throw 'Windows host role must remain bridge_only.'
}
if (-not ($artifacts.artifacts.id -contains 'windows-wsl-prerequisite-proof')) {
    throw 'Artifact registry does not register windows-wsl-prerequisite-proof.'
}

$actualHeadRaw = & git -C $Root rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Unable to resolve exact AgentSwitchboard HEAD.' }
$actualHead = ("$actualHeadRaw").Trim()
if ($actualHead -ne $ExpectedHead.ToLowerInvariant()) {
    throw "Exact-head mismatch. Expected=$ExpectedHead Actual=$actualHead"
}

if ($ContractOnly) {
    Write-Host '[PASS] FIRSTMATE_WINDOWS_WSL_PREREQUISITE_GATE_CONTRACT'
    Write-Host "HEAD=$actualHead"
    Write-Host "WSL_DISTRIBUTION=$WslDistribution"
    Write-Host "PREREQUISITE_TIMEOUT_SECONDS=$PrerequisiteTimeoutSeconds"
    exit 0
}

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wsl) {
    # Cloud/Linux hosts cannot observe the physical Admin Box floor. Fail closed with a
    # structured status so LIVE_ATTEMPT evidence is not mistaken for an unstructured crash.
    Write-Host 'STATUS=BLOCKED_WINDOWS_WSL_REQUIRED'
    Write-Host 'FAILURE_CODE=WINDOWS_WSL_REQUIRED'
    Write-Host 'PROOF_LEVEL=LIVE_ATTEMPT_FAIL_CLOSED'
    Write-Host "HEAD=$actualHead"
    Write-Host "WSL_DISTRIBUTION=$WslDistribution"
    Write-Host '[PROOF_CEILING] Physical WSL floor requires a Windows host with wsl.exe and explicit Ubuntu; contract PASS is not live PASS.'
    exit 46
}
$pwsh = Get-Command pwsh -ErrorAction Stop

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $runId = '{0}-{1}-{2}' -f $actualHead.Substring(0, 8), (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $EvidenceRoot = Join-Path ([System.IO.Path]::GetTempPath()) "AgentSwitchboard\firstmate-windows-wsl\$runId"
}
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$EvidenceRoot = (Resolve-Path -LiteralPath $EvidenceRoot).Path

# wsl.exe present is not enough: the contracted distribution must be registered and runnable.
# Probe before apt/preflight so a missing Ubuntu yields structured exit 46, not an unstructured WSL process error.
$distroProbeTimeoutSeconds = [Math]::Max(15, [Math]::Min(30, $PrerequisiteTimeoutSeconds))
$distroProbe = Invoke-CapturedProcess `
    -FileName $wsl.Source `
    -Arguments @('--distribution', $WslDistribution, '--exec', 'true') `
    -TimeoutSeconds $distroProbeTimeoutSeconds
$distroProbePath = Join-Path $EvidenceRoot 'firstmate-wsl-distribution-probe.txt'
Set-Content -LiteralPath $distroProbePath -Value @(
    "HEAD=$actualHead"
    "WSL_DISTRIBUTION=$WslDistribution"
    "PROBE=wsl --distribution $WslDistribution --exec true"
    "EXIT_CODE=$($distroProbe.ExitCode)"
    "TIMED_OUT=$($distroProbe.TimedOut)"
    'STDOUT<<'
    $distroProbe.Stdout.TrimEnd()
    'STDOUT>>'
    'STDERR<<'
    $distroProbe.Stderr.TrimEnd()
    'STDERR>>'
)
if ($distroProbe.ExitCode -ne 0) {
    Write-Host 'STATUS=BLOCKED_WINDOWS_WSL_REQUIRED'
    Write-Host 'FAILURE_CODE=WINDOWS_WSL_REQUIRED'
    Write-Host 'PROOF_LEVEL=LIVE_ATTEMPT_FAIL_CLOSED'
    Write-Host "HEAD=$actualHead"
    Write-Host "WSL_DISTRIBUTION=$WslDistribution"
    Write-Host "DETAIL=Required WSL distribution is not registered or not runnable"
    Write-Host "DISTRIBUTION_PROBE_PATH=$distroProbePath"
    Write-Host '[PROOF_CEILING] Physical WSL floor requires Windows + wsl.exe + explicit runnable Ubuntu; contract PASS is not live PASS.'
    exit 46
}

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
# Fail fast before the long bridge/interop path when the operator-staged primary harness
# is missing from non-interactive PATH (bash -lc), matching Test-FirstMateInterop.sh.
harness=""
for candidate in claude grok pi pi-signed omp codex opencode cursor-agent; do
  if command -v "$candidate" >/dev/null 2>&1; then
    harness="$candidate"
    break
  fi
done
if [[ -z "$harness" ]]; then
  printf 'STATUS=BLOCKED_PRIMARY_HARNESS\n'
  printf 'NEXT=install one primary harness on PATH inside Ubuntu visible to: wsl -d Ubuntu --exec bash -lc "command -v <harness>" (claude|grok|pi|pi-signed|omp|codex|opencode|cursor-agent), then rerun\n'
  exit 48
fi
# Fail closed before the long bridge when FirstMate is dirty or off the audited pin.
# Pin is loaded from tooling/firstmate/harness/upstream-pin.json (same source as Test-FirstMateInterop.sh).
# When -FirstMatePath is set, ASB_FIRSTMATE_PATH is injected via WSLENV and $HOME/firstmate
# is skipped so a dirty default checkout cannot false-block a clean override.
EXPECTED_FIRSTMATE_HEAD='__ASB_EXPECTED_FIRSTMATE_HEAD__'
FIRSTMATE_CHECK_PATH="${ASB_FIRSTMATE_PATH:-}"
if [[ -n "$FIRSTMATE_CHECK_PATH" ]]; then
  if [[ ! -d "$FIRSTMATE_CHECK_PATH/.git" ]]; then
    printf 'STATUS=BLOCKED_FIRSTMATE_PIN\n'
    printf 'NEXT=pass -FirstMatePath to a clean audited kunchenguid/firstmate@%s checkout (override path missing or not a git repo: %s), then rerun\n' "$EXPECTED_FIRSTMATE_HEAD" "$FIRSTMATE_CHECK_PATH"
    exit 50
  fi
  if [[ -n "$(git -C "$FIRSTMATE_CHECK_PATH" status --porcelain 2>/dev/null || true)" ]]; then
    printf 'STATUS=BLOCKED_FIRSTMATE_DIRTY\n'
    printf 'NEXT=commit/stash/move dirty work in -FirstMatePath (%s), then rerun\n' "$FIRSTMATE_CHECK_PATH"
    exit 49
  fi
  actual_fm_head="$(git -C "$FIRSTMATE_CHECK_PATH" rev-parse HEAD 2>/dev/null || true)"
  if [[ "$actual_fm_head" != "$EXPECTED_FIRSTMATE_HEAD" ]]; then
    printf 'STATUS=BLOCKED_FIRSTMATE_PIN\n'
    printf 'NEXT=in -FirstMatePath (%s) run: git fetch --all && git checkout %s, then rerun\n' "$FIRSTMATE_CHECK_PATH" "$EXPECTED_FIRSTMATE_HEAD"
    exit 50
  fi
elif [[ -e "$HOME/firstmate" ]]; then
  if [[ ! -d "$HOME/firstmate/.git" ]]; then
    printf 'STATUS=BLOCKED_FIRSTMATE_PIN\n'
    printf 'NEXT=repair or remove $HOME/firstmate so bounded bootstrap can clone kunchenguid/firstmate@%s, or pass -FirstMatePath to a clean audited checkout, then rerun\n' "$EXPECTED_FIRSTMATE_HEAD"
    exit 50
  fi
  if [[ -n "$(git -C "$HOME/firstmate" status --porcelain 2>/dev/null || true)" ]]; then
    printf 'STATUS=BLOCKED_FIRSTMATE_DIRTY\n'
    printf 'NEXT=commit/stash/move dirty work in $HOME/firstmate, or remove that path so bounded bootstrap can run, then rerun\n'
    exit 49
  fi
  actual_fm_head="$(git -C "$HOME/firstmate" rev-parse HEAD 2>/dev/null || true)"
  if [[ "$actual_fm_head" != "$EXPECTED_FIRSTMATE_HEAD" ]]; then
    printf 'STATUS=BLOCKED_FIRSTMATE_PIN\n'
    printf 'NEXT=in $HOME/firstmate run: git fetch --all && git checkout %s, or remove that path so bounded bootstrap can run, then rerun\n' "$EXPECTED_FIRSTMATE_HEAD"
    exit 50
  fi
fi
printf 'STATUS=PASS\n'
printf 'PRIMARY_HARNESS=%s\n' "$harness"
for tool in "${required[@]}"; do
  printf 'TOOL_%s=%s\n' "${tool^^}" "$(command -v "$tool")"
done
printf 'GITHUB_AUTH=ready\n'
'@
$upstreamPin = Get-Content -LiteralPath $UpstreamPinPath -Raw | ConvertFrom-Json
$expectedFirstMateHead = [string]$upstreamPin.commit
if ($expectedFirstMateHead -notmatch '^[0-9a-f]{40}$') {
    throw "upstream-pin.json commit must be a 40-character lowercase hex SHA. Received=$expectedFirstMateHead"
}
$normalizedCommand = $preflightCommand.Replace("`r`n", "`n").Replace("`r", "`n")
$normalizedCommand = $normalizedCommand.Replace('__ASB_EXPECTED_FIRSTMATE_HEAD__', $expectedFirstMateHead)

$preflightEnvironment = @{}
$preflightPathEnvironmentNames = @()
if (-not [string]::IsNullOrWhiteSpace($FirstMatePath)) {
    $preflightEnvironment['ASB_FIRSTMATE_PATH'] = $FirstMatePath
    if ($FirstMatePath -match '^[A-Za-z]:[\\/]' -or $FirstMatePath -match '^\\\\') {
        $preflightPathEnvironmentNames += 'ASB_FIRSTMATE_PATH'
    }
}

$preflight = Invoke-CapturedProcess `
    -FileName $wsl.Source `
    -Arguments @('--distribution', $WslDistribution, '--exec', 'bash', '-lc', $normalizedCommand) `
    -TimeoutSeconds $PrerequisiteTimeoutSeconds `
    -Environment $preflightEnvironment `
    -PathEnvironmentNames $preflightPathEnvironmentNames

Set-Content -LiteralPath $PrerequisitePath -Value @(
    "HEAD=$actualHead"
    "WSL_DISTRIBUTION=$WslDistribution"
    "EXIT_CODE=$($preflight.ExitCode)"
    $preflight.Stdout.TrimEnd()
    "STDERR=$PrerequisiteStderrPath"
)
Set-Content -LiteralPath $PrerequisiteStderrPath -Value $preflight.Stderr.TrimEnd()

if ($preflight.ExitCode -ne 0) {
    Write-Host '===== FIRSTMATE WSL PREREQUISITE FLOOR ====='
    Get-Content -LiteralPath $PrerequisitePath
    $statusMatch = [regex]::Match($preflight.Stdout, '(?m)^STATUS=(.+)$')
    if ($statusMatch.Success) {
        Write-Host "STATUS=$($statusMatch.Groups[1].Value.Trim())"
    }
    $nextAction = [regex]::Match($preflight.Stdout, '(?m)^NEXT_ACTION=(.+)$')
    if ($nextAction.Success) {
        Write-Host "NEXT_ACTION=$($nextAction.Groups[1].Value.Trim())"
    }
    Write-Host "PREREQUISITE_EVIDENCE=$PrerequisitePath"
    if ($preflight.ExitCode -eq 124) {
        throw "FirstMate WSL prerequisite probe timed out after $PrerequisiteTimeoutSeconds seconds."
    }
    # Preserve structured exit codes so FM-WSL-12 continuation can distinguish
    # allowlisted package repair (44) from operator GitHub auth (45) without
    # treating every prerequisite miss as a hard permission stop.
    Write-Host "FIRSTMATE_WSL_PREREQUISITE_BLOCKED Exit=$($preflight.ExitCode)"
    exit $preflight.ExitCode
}

$bridgeArguments = @(
    '-NoLogo', '-NoProfile', '-File', $BridgePath,
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

$bridge = Invoke-CapturedProcess -FileName $pwsh.Source -Arguments $bridgeArguments -TimeoutSeconds 600
Set-Content -LiteralPath $BridgeStdoutPath -Value $bridge.Stdout.TrimEnd()
Set-Content -LiteralPath $BridgeStderrPath -Value $bridge.Stderr.TrimEnd()

if ($bridge.ExitCode -ne 0) {
    if (-not [string]::IsNullOrWhiteSpace($bridge.Stdout)) { Write-Host $bridge.Stdout.TrimEnd() }
    if (-not [string]::IsNullOrWhiteSpace($bridge.Stderr)) { Write-Host $bridge.Stderr.TrimEnd() }
    $bridgeCombined = (($bridge.Stdout, $bridge.Stderr) -join "`n")
    $operatorNext = $null
    $nextActionMatch = [regex]::Match($bridgeCombined, '(?m)^NEXT_ACTION=(.+)$')
    if ($nextActionMatch.Success) {
        $operatorNext = $nextActionMatch.Groups[1].Value.Trim()
        Write-Host "NEXT_ACTION=$operatorNext"
    }
    $nextMatch = [regex]::Match($bridgeCombined, '(?m)(?:^|\s)NEXT=(.+)$')
    if ($nextMatch.Success) {
        $operatorNext = $nextMatch.Groups[1].Value.Trim()
        Write-Host "NEXT=$operatorNext"
    }
    Write-Host "PREREQUISITE_EVIDENCE=$PrerequisitePath"
    Write-Host "BRIDGE_STDOUT=$BridgeStdoutPath"
    Write-Host "BRIDGE_STDERR=$BridgeStderrPath"
    Write-Host "FIRSTMATE_LOWER_BRIDGE_FAILED Exit=$($bridge.ExitCode)"
    exit $(if ($bridge.ExitCode -ne 0) { $bridge.ExitCode } else { 1 })
}

if (-not [string]::IsNullOrWhiteSpace($bridge.Stdout)) { Write-Host $bridge.Stdout.TrimEnd() }
Write-Host '[PASS] FIRSTMATE_WINDOWS_WSL_PHYSICAL_FLOOR'
Write-Host "HEAD=$actualHead"
Write-Host "WSL_DISTRIBUTION=$WslDistribution"
Write-Host "PREREQUISITE_EVIDENCE=$PrerequisitePath"
Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
Write-Host '[PROOF_CEILING] Physical WSL interoperability floor only; no live FirstMate crew dispatch is proven.'
