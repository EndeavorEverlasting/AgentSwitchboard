[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$ExpectedHead,

    [string]$FirstMatePath,

    [string]$SourceRepositoryPath,

    [string]$EvidenceRoot,

    [string]$WslDistribution,

    [ValidateRange(10, 600)]
    [int]$WslTimeoutSeconds = 120,

    [switch]$RepairWslIfNeeded,

    [switch]$ContractOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7+ (pwsh) is required for the Windows-to-WSL First Mate bridge.'
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$IntegrationContractPath = Join-Path $Root 'tooling\firstmate\harness\integration-contract.json'
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
        [Parameter(Mandatory = $true)][string]$Distribution,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [hashtable]$Environment = @{},
        [string[]]$PathEnvironmentNames = @()
    )

    $wsl = Get-Command wsl.exe -ErrorAction Stop

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $wsl.Source
    # Never inherit a linked-worktree CWD into WSL. The Linux command explicitly
    # enters the WSL-owned standalone clone created by this bridge.
    $psi.WorkingDirectory = $env:SystemRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    [void]$psi.ArgumentList.Add('-d')
    [void]$psi.ArgumentList.Add($Distribution)
    [void]$psi.ArgumentList.Add('--exec')
    [void]$psi.ArgumentList.Add('bash')
    [void]$psi.ArgumentList.Add('-lc')
    [void]$psi.ArgumentList.Add($Command)

    $wslEnvEntries = @()
    $existingWslEnv = $psi.Environment['WSLENV']
    if (-not [string]::IsNullOrWhiteSpace($existingWslEnv)) {
        $wslEnvEntries += @($existingWslEnv -split ':' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    foreach ($name in $Environment.Keys) {
        $stringName = [string]$name
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
    if (-not $process.Start()) {
        throw 'Unable to start wsl.exe.'
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    $timedOut = -not $completed
    if ($timedOut) {
        try {
            $process.Kill($true)
            $process.WaitForExit()
        }
        catch {
            # Timeout remains authoritative; cleanup failure is diagnostic only.
        }
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    if ($timedOut) {
        $stderr = ($stderr.TrimEnd() + "`nTIMEOUT: wsl.exe exceeded $TimeoutSeconds seconds.").Trim()
    }

    return [pscustomobject]@{
        ExitCode = if ($timedOut) { 124 } else { $process.ExitCode }
        Stdout = $stdout
        Stderr = $stderr
        TimedOut = $timedOut
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

if (-not (Test-Path -LiteralPath $IntegrationContractPath)) {
    throw "Missing First Mate integration contract: $IntegrationContractPath"
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

$integration = Get-Content -LiteralPath $IntegrationContractPath -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$artifacts = Get-Content -LiteralPath $ArtifactRegistryPath -Raw | ConvertFrom-Json
$validators = Get-Content -LiteralPath $ValidatorRegistryPath -Raw | ConvertFrom-Json

$canonicalWslDistribution = [string]$integration.platform_contract.wsl_distribution
if ([string]::IsNullOrWhiteSpace($canonicalWslDistribution)) {
    throw 'Integration contract does not declare platform_contract.wsl_distribution.'
}
if ([string]::IsNullOrWhiteSpace($WslDistribution)) {
    $WslDistribution = $canonicalWslDistribution
}
elseif ($WslDistribution -ne $canonicalWslDistribution) {
    throw "WSL distribution mismatch. Contract=$canonicalWslDistribution Requested=$WslDistribution"
}

if ($manifest.components.windows_wsl_bridge -ne 'Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1') {
    throw 'Operational manifest does not register the Windows-to-WSL bridge.'
}
if (-not ($artifacts.artifacts.id -contains 'windows-wsl-runtime-proof')) {
    throw 'Artifact registry does not register windows-wsl-runtime-proof.'
}
if (-not ($artifacts.artifacts.id -contains 'windows-wsl-diagnostics')) {
    throw 'Artifact registry does not register windows-wsl-diagnostics.'
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
    Write-Host "WSL_DISTRIBUTION=$WslDistribution"
    Write-Host "WSL_TIMEOUT_SECONDS=$WslTimeoutSeconds"
    exit 0
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'WSL is not installed or wsl.exe is unavailable.'
}

if ([string]::IsNullOrWhiteSpace($SourceRepositoryPath)) {
    $commonGitDir = (& git -C $Root rev-parse --path-format=absolute --git-common-dir).Trim()
    Assert-LastExit -ExitCode $LASTEXITCODE -Operation 'Resolve AgentSwitchboard common Git directory'
    $SourceRepositoryPath = Split-Path -Parent $commonGitDir
}
$SourceRepositoryPath = (Resolve-Path -LiteralPath $SourceRepositoryPath).Path
$sourceIsWorktree = (& git -C $SourceRepositoryPath rev-parse --is-inside-work-tree).Trim()
Assert-LastExit -ExitCode $LASTEXITCODE -Operation 'Verify AgentSwitchboard source repository'
if ($sourceIsWorktree -ne 'true') {
    throw "Source repository is not a Git working tree: $SourceRepositoryPath"
}
& git -C $SourceRepositoryPath cat-file -e "$actualHead^{commit}"
Assert-LastExit -ExitCode $LASTEXITCODE -Operation 'Verify exact AgentSwitchboard commit in source repository'

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $evidenceRunId = '{0}-{1}-{2}' -f $actualHead.Substring(0, 8), (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $EvidenceRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('AgentSwitchboard\firstmate-windows-wsl\' + $evidenceRunId)
}
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$EvidenceRoot = (Resolve-Path -LiteralPath $EvidenceRoot).Path

$ReportPath = Join-Path $EvidenceRoot 'firstmate-harness-report.md'
$ProbePath = Join-Path $EvidenceRoot 'firstmate-floor.txt'
$RoutePath = Join-Path $EvidenceRoot 'firstmate-route.json'
$WslDiagnosticsPath = Join-Path $EvidenceRoot 'wsl-stderr.log'
$BootstrapStdoutPath = Join-Path $EvidenceRoot 'wsl-bootstrap-stdout.txt'

$runId = "$($actualHead.Substring(0, 8))-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$wslWorkspace = "/tmp/agentswitchboard-firstmate-$runId"

Set-Content -LiteralPath $WslDiagnosticsPath -Value @(
    "HEAD=$actualHead"
    "WINDOWS_LAUNCHER_WORKTREE=$Root"
    "WINDOWS_SOURCE_REPOSITORY=$SourceRepositoryPath"
    "WSL_DISTRIBUTION=$WslDistribution"
    "WSL_TIMEOUT_SECONDS=$WslTimeoutSeconds"
    "WSL_WORKSPACE=$wslWorkspace"
    "NOTE=Windows paths cross into WSL only through WSLENV /p translation; WSL stdout and stderr remain separate."
    "NOTE=The Linux runtime uses a WSL-owned standalone clone, never the Windows linked-worktree .git indirection."
)

$preflight = Invoke-WslProcess `
    -Distribution $WslDistribution `
    -Command 'set -euo pipefail; printf "WSL_DISTRO_NAME=%s\n" "${WSL_DISTRO_NAME:-}"; command -v bash; printf "BASH_READY=1\n"' `
    -TimeoutSeconds $WslTimeoutSeconds
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'ubuntu-preflight-initial' -Text $preflight.Stderr

if ($preflight.ExitCode -ne 0 -and $RepairWslIfNeeded) {
    $repairCmd = Join-Path $Root 'Repair-Technician-WSL-Ubuntu.cmd'
    if (-not (Test-Path -LiteralPath $repairCmd -PathType Leaf)) {
        throw "Canonical WSL repair entrypoint is missing: $repairCmd"
    }

    Write-Host "Canonical WSL distribution '$WslDistribution' cannot execute Bash. Invoking the repository-owned WSL/Ubuntu repair..." -ForegroundColor Yellow
    $previousNoPause = $env:AGENT_SWITCHBOARD_NO_PAUSE
    $nativePreferenceExists = Test-Path Variable:PSNativeCommandUseErrorActionPreference
    if ($nativePreferenceExists) {
        $previousNativePreference = $PSNativeCommandUseErrorActionPreference
    }
    try {
        $env:AGENT_SWITCHBOARD_NO_PAUSE = '1'
        if ($nativePreferenceExists) {
            $PSNativeCommandUseErrorActionPreference = $false
        }
        & $repairCmd
        $repairExit = $LASTEXITCODE
    }
    finally {
        if ($nativePreferenceExists) {
            $PSNativeCommandUseErrorActionPreference = $previousNativePreference
        }
        if ($null -eq $previousNoPause) {
            Remove-Item Env:AGENT_SWITCHBOARD_NO_PAUSE -ErrorAction SilentlyContinue
        }
        else {
            $env:AGENT_SWITCHBOARD_NO_PAUSE = $previousNoPause
        }
    }

    Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'ubuntu-repair' -Text "ENTRYPOINT=$repairCmd`nEXIT_CODE=$repairExit"
    if ($repairExit -eq 3010) {
        throw "Repository-owned WSL repair reached a required Windows reboot boundary. Evidence: $WslDiagnosticsPath"
    }
    if ($repairExit -ne 0) {
        throw "Repository-owned WSL repair failed with exit code $repairExit. Evidence: $WslDiagnosticsPath"
    }

    $preflight = Invoke-WslProcess `
        -Distribution $WslDistribution `
        -Command 'set -euo pipefail; printf "WSL_DISTRO_NAME=%s\n" "${WSL_DISTRO_NAME:-}"; command -v bash; printf "BASH_READY=1\n"' `
        -TimeoutSeconds $WslTimeoutSeconds
    Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'ubuntu-preflight-after-repair' -Text $preflight.Stderr
}

if ($preflight.ExitCode -ne 0) {
    $repairHint = if ($RepairWslIfNeeded) {
        'The repository-owned repair already ran and did not establish a usable Ubuntu Bash runtime.'
    }
    else {
        'Re-run with -RepairWslIfNeeded to invoke the repository-owned WSL/Ubuntu repair.'
    }
    throw "Canonical WSL distribution '$WslDistribution' cannot execute Bash. $repairHint See $WslDiagnosticsPath"
}
if ($preflight.Stdout -notmatch [regex]::Escape("WSL_DISTRO_NAME=$WslDistribution") -or $preflight.Stdout -notmatch 'BASH_READY=1') {
    throw "WSL preflight did not prove canonical distribution '$WslDistribution' and Bash readiness. See $WslDiagnosticsPath"
}

$bootstrapCommand = @'
set -euo pipefail
: "${ASB_SOURCE_REPO:?ASB_SOURCE_REPO is required}"
: "${ASB_EXPECTED_HEAD:?ASB_EXPECTED_HEAD is required}"
: "${ASB_WSL_WORKSPACE:?ASB_WSL_WORKSPACE is required}"
if [[ -e "$ASB_WSL_WORKSPACE" ]]; then
  printf '[FAIL] WSL workspace already exists: %s\n' "$ASB_WSL_WORKSPACE" >&2
  exit 73
fi
git -C "$ASB_SOURCE_REPO" rev-parse --is-inside-work-tree >/dev/null
git -C "$ASB_SOURCE_REPO" cat-file -e "${ASB_EXPECTED_HEAD}^{commit}"
git clone --quiet --no-hardlinks --no-checkout "$ASB_SOURCE_REPO" "$ASB_WSL_WORKSPACE"
git -C "$ASB_WSL_WORKSPACE" checkout --quiet --detach "$ASB_EXPECTED_HEAD"
actual="$(git -C "$ASB_WSL_WORKSPACE" rev-parse HEAD)"
printf 'WSL_DISTRO_NAME=%s\n' "${WSL_DISTRO_NAME:-}"
printf 'WSL_WORKSPACE=%s\n' "$ASB_WSL_WORKSPACE"
printf 'HEAD=%s\n' "$actual"
'@

$bootstrap = Invoke-WslProcess `
    -Distribution $WslDistribution `
    -Command $bootstrapCommand `
    -TimeoutSeconds $WslTimeoutSeconds `
    -Environment @{
        ASB_SOURCE_REPO = $SourceRepositoryPath
        ASB_EXPECTED_HEAD = $actualHead
        ASB_WSL_WORKSPACE = $wslWorkspace
    } `
    -PathEnvironmentNames @('ASB_SOURCE_REPO')
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'bootstrap' -Text $bootstrap.Stderr
Set-Content -LiteralPath $BootstrapStdoutPath -Value $bootstrap.Stdout.TrimEnd()
if ($bootstrap.ExitCode -ne 0) {
    throw "WSL could not create the standalone exact-head AgentSwitchboard clone. See $WslDiagnosticsPath and $BootstrapStdoutPath"
}
if ($bootstrap.Stdout -notmatch [regex]::Escape("WSL_DISTRO_NAME=$WslDistribution") -or $bootstrap.Stdout -notmatch [regex]::Escape("HEAD=$actualHead")) {
    throw "WSL standalone clone did not prove the canonical distribution and expected AgentSwitchboard HEAD. See $BootstrapStdoutPath"
}

$workspaceEnvironment = @{
    ASB_WSL_WORKSPACE = $wslWorkspace
}

$visibility = Invoke-WslProcess `
    -Distribution $WslDistribution `
    -Command 'set -euo pipefail; cd "$ASB_WSL_WORKSPACE"; printf "WSL_DISTRO_NAME=%s\n" "${WSL_DISTRO_NAME:-}"; printf "WSL_PWD=%s\n" "$PWD"; git rev-parse HEAD' `
    -TimeoutSeconds $WslTimeoutSeconds `
    -Environment $workspaceEnvironment
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'visibility' -Text $visibility.Stderr
if ($visibility.ExitCode -ne 0) {
    throw "WSL cannot execute inside its standalone exact-head AgentSwitchboard clone. See $WslDiagnosticsPath"
}
$visibilityLines = @($visibility.Stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($visibilityLines.Count -lt 3 -or $visibilityLines[0].Trim() -ne "WSL_DISTRO_NAME=$WslDistribution" -or $visibilityLines[-1].Trim() -ne $actualHead) {
    throw "WSL did not resolve the canonical distribution and same AgentSwitchboard HEAD in its standalone clone. See $WslDiagnosticsPath"
}

$contract = Invoke-WslProcess `
    -Distribution $WslDistribution `
    -Command 'set -euo pipefail; cd "$ASB_WSL_WORKSPACE"; bash Test-AgentSwitchboard-FirstMate-Harness.sh contract' `
    -TimeoutSeconds $WslTimeoutSeconds `
    -Environment $workspaceEnvironment
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'contract' -Text $contract.Stderr
if ($contract.ExitCode -ne 0) {
    Set-Content -LiteralPath (Join-Path $EvidenceRoot 'contract-stdout.txt') -Value $contract.Stdout
    throw "Owning First Mate harness contract failed. Evidence: $EvidenceRoot"
}
Write-Host $contract.Stdout.TrimEnd()

$report = Invoke-WslProcess `
    -Distribution $WslDistribution `
    -Command 'set -euo pipefail; cd "$ASB_WSL_WORKSPACE"; python3 tooling/firstmate/harness/operational/Build-FirstMateHarnessReport.py --stdout' `
    -TimeoutSeconds $WslTimeoutSeconds `
    -Environment $workspaceEnvironment
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'report' -Text $report.Stderr
if ($report.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($report.Stdout)) {
    throw "Canonical operator report generation failed. See $WslDiagnosticsPath"
}
Set-Content -LiteralPath $ReportPath -Value $report.Stdout.TrimEnd()

$probeCommand = 'set -euo pipefail; cd "$ASB_WSL_WORKSPACE"; bash tooling/firstmate/Test-FirstMateInterop.sh'
$probeEnvironment = @{
    ASB_WSL_WORKSPACE = $wslWorkspace
}
$probePathEnvironmentNames = @()
if (-not [string]::IsNullOrWhiteSpace($FirstMatePath)) {
    $probeEnvironment['ASB_FIRSTMATE_PATH'] = $FirstMatePath
    if ($FirstMatePath -match '^[A-Za-z]:[\\/]' -or $FirstMatePath -match '^\\\\') {
        $probePathEnvironmentNames += 'ASB_FIRSTMATE_PATH'
    }
    $probeCommand += ' --firstmate "$ASB_FIRSTMATE_PATH"'
}
$probe = Invoke-WslProcess `
    -Distribution $WslDistribution `
    -Command $probeCommand `
    -TimeoutSeconds $WslTimeoutSeconds `
    -Environment $probeEnvironment `
    -PathEnvironmentNames $probePathEnvironmentNames
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'probe' -Text $probe.Stderr
Set-Content -LiteralPath $ProbePath -Value @(
    "EXIT_CODE=$($probe.ExitCode)"
    "WSL_DISTRIBUTION=$WslDistribution"
    "WSL_WORKSPACE=$wslWorkspace"
    $probe.Stdout.TrimEnd()
    "WSL_STDERR=$WslDiagnosticsPath"
)
if ($probe.ExitCode -ne 0) {
    Write-Host '===== CANONICAL HARNESS REPORT ====='
    Get-Content -LiteralPath $ReportPath
    Write-Host "WSL_WORKSPACE_PRESERVED=$wslWorkspace"
    throw "First Mate read-only floor failed. Durable evidence: $ProbePath"
}

$route = Invoke-WslProcess `
    -Distribution $WslDistribution `
    -Command 'set -euo pipefail; cd "$ASB_WSL_WORKSPACE"; python3 tooling/firstmate/harness/operational/Select-FirstMateWorkflow.py --parallel-writers 3 --firstmate-floor pass --platform linux-wsl' `
    -TimeoutSeconds $WslTimeoutSeconds `
    -Environment $workspaceEnvironment
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'route' -Text $route.Stderr
if ($route.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($route.Stdout)) {
    throw "First Mate route generation failed. See $WslDiagnosticsPath"
}
Set-Content -LiteralPath $RoutePath -Value $route.Stdout.TrimEnd()
$routeObject = $route.Stdout | ConvertFrom-Json
if (
    $routeObject.status -ne 'ready' -or
    $routeObject.route -ne 'firstmate-local-only' -or
    $routeObject.session_backend -ne 'tmux' -or
    $routeObject.yolo_enabled -ne $false
) {
    throw "Unexpected First Mate route. Evidence: $RoutePath"
}

Write-Host '===== CANONICAL HARNESS REPORT ====='
Get-Content -LiteralPath $ReportPath
Write-Host '===== FIRST MATE ROUTE ====='
Get-Content -LiteralPath $RoutePath
Write-Host '[PASS] FIRSTMATE_WINDOWS_WSL_RUNTIME_FLOOR'
Write-Host "HEAD=$actualHead"
Write-Host "WSL_DISTRIBUTION=$WslDistribution"
Write-Host "REPORT=$ReportPath"
Write-Host "FLOOR_EVIDENCE=$ProbePath"
Write-Host "ROUTE=$RoutePath"
Write-Host "WSL_DIAGNOSTICS=$WslDiagnosticsPath"
Write-Host "WSL_WORKSPACE_PRESERVED=$wslWorkspace"
