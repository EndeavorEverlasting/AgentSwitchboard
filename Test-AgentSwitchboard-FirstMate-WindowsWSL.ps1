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

    [switch]$ContractOnly,
    [switch]$PreserveWslWorkspaceOnFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7+ (pwsh) is required for the Windows-to-WSL FirstMate bridge.'
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$IntegrationContractPath = Join-Path $Root 'tooling\firstmate\harness\integration-contract.json'
$ManifestPath = Join-Path $Root 'tooling\firstmate\harness\operational\manifest.json'
$ArtifactRegistryPath = Join-Path $Root 'tooling\firstmate\harness\operational\artifact-registry.json'
$ValidatorRegistryPath = Join-Path $Root 'tooling\firstmate\harness\operational\validator-registry.json'

function Normalize-WslText {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return '' }
    return $Text.Replace(([char]0).ToString(), '')
}

function ConvertTo-Lf {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    if ($null -eq $Text) { return '' }
    return $Text.Replace("`r`n", "`n").Replace("`r", "`n")
}

function Add-WslDiagnostic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Stage,
        [AllowNull()][AllowEmptyString()][string]$Text
    )
    $normalized = Normalize-WslText -Text $Text
    if ([string]::IsNullOrWhiteSpace($normalized)) { return }
    Add-Content -LiteralPath $Path -Value "===== $Stage ====="
    Add-Content -LiteralPath $Path -Value $normalized.TrimEnd()
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
    $psi.WorkingDirectory = $env:SystemRoot
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    [void]$psi.ArgumentList.Add('--distribution')
    [void]$psi.ArgumentList.Add($Distribution)
    [void]$psi.ArgumentList.Add('--exec')
    [void]$psi.ArgumentList.Add('bash')
    [void]$psi.ArgumentList.Add('-lc')
    [void]$psi.ArgumentList.Add((ConvertTo-Lf -Text $Command))

    $wslEnvEntries = @()
    $existingWslEnv = $psi.Environment['WSLENV']
    if (-not [string]::IsNullOrWhiteSpace($existingWslEnv)) {
        $wslEnvEntries += @($existingWslEnv -split ':' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    foreach ($name in $Environment.Keys) {
        $stringName = [string]$name
        # Replace any inherited mode for variables this bridge owns. Keeping both
        # ASB_SOURCE_REPO and ASB_SOURCE_REPO/p makes WSL translation ambiguous.
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
    # Keep exit 46 structured — do not throw (throw collapses to unstructured exit 1).
    try {
        if (-not $process.Start()) {
            Write-Host 'STATUS=BLOCKED_WINDOWS_WSL_REQUIRED'
            Write-Host 'FAILURE_CODE=WINDOWS_WSL_REQUIRED'
            Write-Host 'NEXT=run on Windows Admin Box with runnable wsl.exe and Ubuntu; unable to start wsl.exe process'
            Write-Host '[PROOF_CEILING] Physical WSL floor requires Windows + wsl.exe; contract PASS is not live PASS.'
            exit 46
        }
    }
    catch {
        Write-Host 'STATUS=BLOCKED_WINDOWS_WSL_REQUIRED'
        Write-Host 'FAILURE_CODE=WINDOWS_WSL_REQUIRED'
        Write-Host 'NEXT=run on Windows Admin Box with runnable wsl.exe and Ubuntu; wsl.exe Start threw'
        Write-Host ("HARNESS_START_ERROR={0}" -f $_.Exception.Message)
        Write-Host '[PROOF_CEILING] Physical WSL floor requires Windows + wsl.exe; contract PASS is not live PASS.'
        exit 46
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
            # Timeout remains authoritative; process cleanup failure is diagnostic only.
        }
    }

    $stdout = Normalize-WslText -Text $stdoutTask.GetAwaiter().GetResult()
    $stderr = Normalize-WslText -Text $stderrTask.GetAwaiter().GetResult()
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

function Complete-WslWorkspace {
    param(
        [Parameter(Mandatory = $true)][string]$Distribution,
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)][string]$DiagnosticsPath,
        [Parameter(Mandatory = $true)][bool]$PrimaryFailure,
        [switch]$PreserveOnFailure
    )

    if ($Workspace -notmatch '^/tmp/agentswitchboard-firstmate-[0-9a-fA-F-]+$') {
        $message = "Refusing cleanup of unexpected WSL workspace path: $Workspace"
        if ($PrimaryFailure) {
            Write-Warning $message
            return
        }
        # Keep structured — do not throw (throw collapses to unstructured exit 1).
        Write-Host 'STATUS=BLOCKED_WSL_CLEANUP'
        Write-Host "WSL_WORKSPACE=$Workspace"
        Write-Host 'NEXT=inspect evidence; only /tmp/agentswitchboard-firstmate-* workspaces are cleaned by this bridge, then rerun'
        Write-Host $message
        exit 1
    }

    if ($PrimaryFailure -and $PreserveOnFailure) {
        Write-Host "WSL_WORKSPACE_PRESERVED=$Workspace"
        return
    }

    $cleanupCommand = @'
set -euo pipefail
: "${ASB_WSL_WORKSPACE:?ASB_WSL_WORKSPACE is required}"
case "$ASB_WSL_WORKSPACE" in
  /tmp/agentswitchboard-firstmate-*) ;;
  *) printf '[FAIL] Refusing unexpected cleanup target: %s\n' "$ASB_WSL_WORKSPACE" >&2; exit 74 ;;
esac
rm -rf -- "$ASB_WSL_WORKSPACE"
printf 'CLEANED=%s\n' "$ASB_WSL_WORKSPACE"
'@
    $cleanup = Invoke-WslProcess `
        -Distribution $Distribution `
        -Command $cleanupCommand `
        -TimeoutSeconds $TimeoutSeconds `
        -Environment @{ ASB_WSL_WORKSPACE = $Workspace }
    Add-WslDiagnostic -Path $DiagnosticsPath -Stage 'workspace-cleanup' -Text $cleanup.Stderr
    if ($cleanup.ExitCode -ne 0) {
        $message = "Unable to clean script-owned WSL workspace '$Workspace'. See $DiagnosticsPath"
        if ($PrimaryFailure) {
            Write-Warning $message
            return
        }
        # Keep structured — do not throw (throw collapses to unstructured exit 1).
        Write-Host 'STATUS=BLOCKED_WSL_CLEANUP'
        Write-Host "WSL_WORKSPACE=$Workspace"
        Write-Host "WSL_DIAGNOSTICS=$DiagnosticsPath"
        Write-Host 'NEXT=inspect WSL diagnostics, remove the script-owned /tmp/agentswitchboard-firstmate-* workspace if safe, then rerun'
        Write-Host $message
        exit 1
    }
    Write-Host "WSL_WORKSPACE_CLEANED=$Workspace"
}

foreach ($required in @($IntegrationContractPath, $ManifestPath, $ArtifactRegistryPath, $ValidatorRegistryPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        # Keep structured — do not throw (throw collapses to unstructured exit 1).
        Write-Host 'STATUS=BLOCKED_HARNESS_CONTRACT'
        Write-Host "MISSING_SURFACE=$required"
        Write-Host "NEXT=restore FirstMate bridge contract surface ($required), then rerun Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1"
        exit 52
    }
}

$integration = Get-Content -LiteralPath $IntegrationContractPath -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$artifacts = Get-Content -LiteralPath $ArtifactRegistryPath -Raw | ConvertFrom-Json
$validators = Get-Content -LiteralPath $ValidatorRegistryPath -Raw | ConvertFrom-Json

$canonicalWslDistribution = [string]$integration.platform_contract.wsl_distribution
if ([string]::IsNullOrWhiteSpace($canonicalWslDistribution)) {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_HARNESS_CONTRACT'
    Write-Host 'NEXT=repair tooling/firstmate/harness/integration-contract.json so platform_contract.wsl_distribution is set'
    exit 52
}
if ([string]::IsNullOrWhiteSpace($WslDistribution)) {
    $WslDistribution = $canonicalWslDistribution
}
elseif ($WslDistribution -ne $canonicalWslDistribution) {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_WSL_DISTRIBUTION'
    Write-Host "CONTRACT_WSL_DISTRIBUTION=$canonicalWslDistribution"
    Write-Host "REQUESTED_WSL_DISTRIBUTION=$WslDistribution"
    Write-Host 'NEXT=rerun with -WslDistribution matching integration-contract platform_contract.wsl_distribution'
    exit 1
}
if ($integration.platform_contract.windows_host_role -ne 'bridge_only') {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_HARNESS_CONTRACT'
    Write-Host "WINDOWS_HOST_ROLE=$($integration.platform_contract.windows_host_role)"
    Write-Host 'NEXT=repair tooling/firstmate/harness/integration-contract.json so platform_contract.windows_host_role=bridge_only'
    exit 52
}
if ($manifest.components.windows_wsl_bridge -ne 'Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1') {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_HARNESS_CONTRACT'
    Write-Host 'NEXT=register Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1 as components.windows_wsl_bridge in the operational manifest'
    exit 52
}
if (-not ($artifacts.artifacts.id -contains 'windows-wsl-runtime-proof')) {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_HARNESS_CONTRACT'
    Write-Host 'NEXT=register windows-wsl-runtime-proof in the artifact registry, then rerun Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1'
    exit 52
}
if (-not ($validators.validators.id -contains 'firstmate-windows-wsl-bridge-contract')) {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_HARNESS_CONTRACT'
    Write-Host 'NEXT=register firstmate-windows-wsl-bridge-contract in the validator registry, then rerun Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1'
    exit 52
}

$actualHead = (& git -C $Root rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_GIT_HEAD'
    Write-Host 'NEXT=repair the AgentSwitchboard checkout so git rev-parse HEAD succeeds, then rerun Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1'
    Write-Host 'Unable to resolve exact AgentSwitchboard HEAD.'
    exit 1
}
if ($actualHead -ne $ExpectedHead.ToLowerInvariant()) {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_HEAD_MISMATCH'
    Write-Host "EXPECTED_HEAD=$ExpectedHead"
    Write-Host "ACTUAL_HEAD=$actualHead"
    Write-Host 'NEXT=ff-only refresh main, re-resolve HEAD, and rerun with the recorded SHA'
    exit 1
}

if ($ContractOnly) {
    if ((ConvertTo-Lf -Text "a`r`nb`rc") -match "`r") {
        throw 'CRLF normalization contract failed.'
    }
    if ((Normalize-WslText -Text '') -ne '') {
        throw 'Empty native stream normalization contract failed.'
    }
    Write-Host '[PASS] FIRSTMATE_WINDOWS_WSL_BRIDGE_CONTRACT'
    Write-Host "HEAD=$actualHead"
    Write-Host "WSL_DISTRIBUTION=$WslDistribution"
    Write-Host "WSL_TIMEOUT_SECONDS=$WslTimeoutSeconds"
    exit 0
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    # Keep exit 46 structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_WINDOWS_WSL_REQUIRED'
    Write-Host 'FAILURE_CODE=WINDOWS_WSL_REQUIRED'
    Write-Host 'NEXT=run on Windows Admin Box with wsl.exe and Ubuntu; this bridge does not install or repair WSL'
    Write-Host '[PROOF_CEILING] Physical WSL floor requires Windows + wsl.exe; contract PASS is not live PASS.'
    exit 46
}

if ([string]::IsNullOrWhiteSpace($SourceRepositoryPath)) {
    $commonGitDir = (& git -C $Root rev-parse --path-format=absolute --git-common-dir).Trim()
    if ($LASTEXITCODE -ne 0) {
        # Keep structured — do not throw (throw collapses to unstructured exit 1).
        Write-Host 'STATUS=BLOCKED_GIT_HEAD'
        Write-Host 'NEXT=repair the AgentSwitchboard checkout so git rev-parse --git-common-dir succeeds, then rerun'
        Write-Host 'Unable to resolve AgentSwitchboard common Git directory.'
        exit 1
    }
    $SourceRepositoryPath = Split-Path -Parent $commonGitDir
}
$SourceRepositoryPath = (Resolve-Path -LiteralPath $SourceRepositoryPath).Path
$sourceIsWorktree = (& git -C $SourceRepositoryPath rev-parse --is-inside-work-tree).Trim()
if ($LASTEXITCODE -ne 0) {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_GIT_HEAD'
    Write-Host "SOURCE_REPOSITORY_PATH=$SourceRepositoryPath"
    Write-Host 'NEXT=pass -SourceRepositoryPath to a Git working tree that contains the exact AgentSwitchboard HEAD, then rerun'
    Write-Host 'Unable to verify AgentSwitchboard source repository work tree.'
    exit 1
}
if ($sourceIsWorktree -ne 'true') {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_GIT_HEAD'
    Write-Host "SOURCE_REPOSITORY_PATH=$SourceRepositoryPath"
    Write-Host 'NEXT=pass -SourceRepositoryPath to a Git working tree that contains the exact AgentSwitchboard HEAD, then rerun'
    exit 1
}
& git -C $SourceRepositoryPath cat-file -e "$actualHead^{commit}"
if ($LASTEXITCODE -ne 0) {
    # Keep structured — do not throw (throw collapses to unstructured exit 1).
    Write-Host 'STATUS=BLOCKED_GIT_HEAD'
    Write-Host "SOURCE_REPOSITORY_PATH=$SourceRepositoryPath"
    Write-Host "EXPECTED_HEAD=$actualHead"
    Write-Host 'NEXT=pass -SourceRepositoryPath to a Git working tree that contains the exact AgentSwitchboard HEAD, then rerun'
    Write-Host 'Unable to verify exact AgentSwitchboard commit in source repository.'
    exit 1
}

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $runId = '{0}-{1}-{2}' -f $actualHead.Substring(0, 8), (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $EvidenceRoot = Join-Path ([System.IO.Path]::GetTempPath()) "AgentSwitchboard\firstmate-windows-wsl\$runId"
}
New-Item -ItemType Directory -Force -Path $EvidenceRoot | Out-Null
$EvidenceRoot = (Resolve-Path -LiteralPath $EvidenceRoot).Path

$ProbePath = Join-Path $EvidenceRoot 'firstmate-floor.txt'
$WslDiagnosticsPath = Join-Path $EvidenceRoot 'wsl-stderr.log'
$BootstrapStdoutPath = Join-Path $EvidenceRoot 'wsl-bootstrap-stdout.txt'
$workspaceId = "$($actualHead.Substring(0, 8))-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$wslWorkspace = "/tmp/agentswitchboard-firstmate-$workspaceId"

Set-Content -LiteralPath $WslDiagnosticsPath -Value @(
    "HEAD=$actualHead"
    "WSL_DISTRIBUTION=$WslDistribution"
    "WSL_TIMEOUT_SECONDS=$WslTimeoutSeconds"
    "WSL_WORKSPACE=$wslWorkspace"
    'NOTE=Windows paths cross into WSL only through WSLENV /p; wslpath is not executed.'
    'NOTE=stdout and stderr remain separate; empty native streams are valid.'
    'NOTE=The Linux runtime uses a WSL-owned standalone clone, never the Windows linked-worktree .git indirection.'
    'NOTE=The script-owned WSL clone is cleaned after each run unless failure preservation is explicitly requested.'
)

$preflight = Invoke-WslProcess `
    -Distribution $WslDistribution `
    -Command 'set -euo pipefail; printf "WSL_DISTRO_NAME=%s\n" "${WSL_DISTRO_NAME:-}"; command -v bash; command -v git; printf "BASH_READY=1\n"' `
    -TimeoutSeconds $WslTimeoutSeconds
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'ubuntu-preflight' -Text $preflight.Stderr
if ($preflight.TimedOut -or $preflight.ExitCode -eq 124) {
    # Keep exit 124 structured — do not remap hangs to WINDOWS_WSL_REQUIRED/46.
    Write-Host 'STATUS=BLOCKED_PREREQUISITE_TIMEOUT'
    Write-Host "NEXT=increase WslTimeoutSeconds or repair hung Ubuntu WSL preflight, then rerun; probe timed out after $WslTimeoutSeconds seconds"
    Write-Host "WSL_DIAGNOSTICS=$WslDiagnosticsPath"
    exit 124
}
if ($preflight.ExitCode -ne 0) {
    Write-Host 'STATUS=BLOCKED_WINDOWS_WSL_REQUIRED'
    Write-Host 'FAILURE_CODE=WINDOWS_WSL_REQUIRED'
    Write-Host "NEXT=repair Ubuntu WSL so distribution '$WslDistribution' can run bash/git; see $WslDiagnosticsPath; then rerun Invoke-Asq017AdminBoxLiveFloor.ps1"
    Write-Host "WSL_DIAGNOSTICS=$WslDiagnosticsPath"
    exit 46
}
if ($preflight.Stdout -notmatch [regex]::Escape("WSL_DISTRO_NAME=$WslDistribution") -or $preflight.Stdout -notmatch 'BASH_READY=1') {
    Write-Host 'STATUS=BLOCKED_WINDOWS_WSL_REQUIRED'
    Write-Host "NEXT=repair Ubuntu WSL so distribution '$WslDistribution' proves Bash readiness; see $WslDiagnosticsPath; then rerun Invoke-Asq017AdminBoxLiveFloor.ps1"
    Write-Host "WSL_DIAGNOSTICS=$WslDiagnosticsPath"
    exit 46
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
    Complete-WslWorkspace -Distribution $WslDistribution -Workspace $wslWorkspace -TimeoutSeconds $WslTimeoutSeconds -DiagnosticsPath $WslDiagnosticsPath -PrimaryFailure $true -PreserveOnFailure:$PreserveWslWorkspaceOnFailure
    Write-Host 'STATUS=BLOCKED_WSL_BOOTSTRAP'
    Write-Host "NEXT=inspect $WslDiagnosticsPath and $BootstrapStdoutPath; repair WSL clone/source-repo access for exact-head bootstrap, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1"
    Write-Host "WSL_DIAGNOSTICS=$WslDiagnosticsPath"
    Write-Host "BOOTSTRAP_STDOUT=$BootstrapStdoutPath"
    exit 51
}
if ($bootstrap.Stdout -notmatch [regex]::Escape("WSL_DISTRO_NAME=$WslDistribution") -or $bootstrap.Stdout -notmatch [regex]::Escape("HEAD=$actualHead")) {
    Complete-WslWorkspace -Distribution $WslDistribution -Workspace $wslWorkspace -TimeoutSeconds $WslTimeoutSeconds -DiagnosticsPath $WslDiagnosticsPath -PrimaryFailure $true -PreserveOnFailure:$PreserveWslWorkspaceOnFailure
    Write-Host 'STATUS=BLOCKED_WSL_BOOTSTRAP'
    Write-Host "NEXT=inspect $BootstrapStdoutPath; ensure WSL clone proves explicit Ubuntu and exact AgentSwitchboard HEAD, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1"
    Write-Host "BOOTSTRAP_STDOUT=$BootstrapStdoutPath"
    exit 51
}

$workspaceEnvironment = @{ ASB_WSL_WORKSPACE = $wslWorkspace }
$contract = Invoke-WslProcess `
    -Distribution $WslDistribution `
    -Command 'set -euo pipefail; cd "$ASB_WSL_WORKSPACE"; bash Test-AgentSwitchboard-FirstMate-Harness.sh contract' `
    -TimeoutSeconds $WslTimeoutSeconds `
    -Environment $workspaceEnvironment
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'contract' -Text $contract.Stderr
if ($contract.ExitCode -ne 0) {
    Set-Content -LiteralPath (Join-Path $EvidenceRoot 'contract-stdout.txt') -Value $contract.Stdout.TrimEnd()
    Complete-WslWorkspace -Distribution $WslDistribution -Workspace $wslWorkspace -TimeoutSeconds $WslTimeoutSeconds -DiagnosticsPath $WslDiagnosticsPath -PrimaryFailure $true -PreserveOnFailure:$PreserveWslWorkspaceOnFailure
    Write-Host 'STATUS=BLOCKED_HARNESS_CONTRACT'
    Write-Host "NEXT=inspect evidence at $EvidenceRoot; repair FirstMate harness contract failure inside Ubuntu, then rerun Invoke-Asq017AdminBoxLiveFloor.ps1"
    Write-Host "EVIDENCE_ROOT=$EvidenceRoot"
    exit 52
}

$probeCommand = 'set -euo pipefail; cd "$ASB_WSL_WORKSPACE"; bash tooling/firstmate/Test-FirstMateInterop.sh'
$probeEnvironment = @{ ASB_WSL_WORKSPACE = $wslWorkspace }
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
    "HEAD=$actualHead"
    "WSL_DISTRIBUTION=$WslDistribution"
    "WSL_WORKSPACE=$wslWorkspace"
    $probe.Stdout.TrimEnd()
    'STDERR<<'
    $probe.Stderr.TrimEnd()
    'STDERR>>'
    "WSL_STDERR=$WslDiagnosticsPath"
)
if ($probe.ExitCode -ne 0) {
    if (-not [string]::IsNullOrWhiteSpace($probe.Stdout)) { Write-Host $probe.Stdout.TrimEnd() }
    if (-not [string]::IsNullOrWhiteSpace($probe.Stderr)) { Write-Host $probe.Stderr.TrimEnd() }
    $probeBlob = @($probe.Stdout, $probe.Stderr) -join "`n"
    $statusMatch = [regex]::Match($probeBlob, '(?m)^STATUS=(.+)$')
    if ($statusMatch.Success) {
        Write-Host ("STATUS=" + $statusMatch.Groups[1].Value.Trim())
    }
    $nextMatch = [regex]::Match($probeBlob, '(?m)^NEXT=(.+)$')
    if (-not $nextMatch.Success) {
        $nextMatch = [regex]::Match($probeBlob, '(?m)(?:^|\s)NEXT=(.+)$')
    }
    if ($nextMatch.Success) {
        Write-Host ("NEXT=" + $nextMatch.Groups[1].Value.Trim())
    }
    Write-Host "FIRSTMATE_INTEROP_PROBE_FAILED Exit=$($probe.ExitCode) Evidence=$ProbePath"
    Complete-WslWorkspace -Distribution $WslDistribution -Workspace $wslWorkspace -TimeoutSeconds $WslTimeoutSeconds -DiagnosticsPath $WslDiagnosticsPath -PrimaryFailure $true -PreserveOnFailure:$PreserveWslWorkspaceOnFailure
    # Preserve structured interop exits (49/50/...) for ASQ-017 / oneshot callers; do not throw.
    exit $(if ($probe.ExitCode -ne 0) { $probe.ExitCode } else { 1 })
}

Complete-WslWorkspace -Distribution $WslDistribution -Workspace $wslWorkspace -TimeoutSeconds $WslTimeoutSeconds -DiagnosticsPath $WslDiagnosticsPath -PrimaryFailure $false
Write-Host $contract.Stdout.TrimEnd()
Write-Host $probe.Stdout.TrimEnd()
Write-Host '[PASS] FIRSTMATE_WINDOWS_WSL_RUNTIME_FLOOR'
Write-Host "HEAD=$actualHead"
Write-Host "WSL_DISTRIBUTION=$WslDistribution"
Write-Host "FLOOR_EVIDENCE=$ProbePath"
Write-Host "WSL_DIAGNOSTICS=$WslDiagnosticsPath"
Write-Host '[PROOF_CEILING] Physical WSL interoperability floor only; no FirstMate crew task was dispatched or supervised.'
