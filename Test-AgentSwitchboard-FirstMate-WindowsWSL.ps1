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

    [switch]$ContractOnly
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

function Assert-LastExit {
    param(
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [Parameter(Mandatory = $true)][string]$Operation
    )
    if ($ExitCode -ne 0) {
        throw "$Operation failed with exit code $ExitCode."
    }
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
    if (-not $process.Start()) { throw 'Unable to start wsl.exe.' }

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

foreach ($required in @($IntegrationContractPath, $ManifestPath, $ArtifactRegistryPath, $ValidatorRegistryPath)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing FirstMate bridge contract surface: $required"
    }
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
if ($integration.platform_contract.windows_host_role -ne 'bridge_only') {
    throw 'Integration contract must keep Windows host role bridge_only.'
}
if ($manifest.components.windows_wsl_bridge -ne 'Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1') {
    throw 'Operational manifest does not register the Windows-to-WSL bridge.'
}
if (-not ($artifacts.artifacts.id -contains 'windows-wsl-runtime-proof')) {
    throw 'Artifact registry does not register windows-wsl-runtime-proof.'
}
if (-not ($validators.validators.id -contains 'firstmate-windows-wsl-bridge-contract')) {
    throw 'Validator registry does not register firstmate-windows-wsl-bridge-contract.'
}

$actualHead = (& git -C $Root rev-parse HEAD).Trim()
Assert-LastExit -ExitCode $LASTEXITCODE -Operation 'Resolve exact AgentSwitchboard HEAD'
if ($actualHead -ne $ExpectedHead.ToLowerInvariant()) {
    throw "Exact-head mismatch. Expected=$ExpectedHead Actual=$actualHead"
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
    throw 'WSL is unavailable. This bridge does not install or repair WSL.'
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
    'NOTE=Windows paths cross into WSL only through WSLENV /p; wslpath is not used.'
    'NOTE=stdout and stderr remain separate; empty native streams are valid.'
    'NOTE=The Linux runtime uses a WSL-owned standalone clone, never the Windows linked-worktree .git indirection.'
)

$preflight = Invoke-WslProcess `
    -Distribution $WslDistribution `
    -Command 'set -euo pipefail; printf "WSL_DISTRO_NAME=%s\n" "${WSL_DISTRO_NAME:-}"; command -v bash; command -v git; printf "BASH_READY=1\n"' `
    -TimeoutSeconds $WslTimeoutSeconds
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'ubuntu-preflight' -Text $preflight.Stderr
if ($preflight.ExitCode -ne 0) {
    throw "Canonical WSL distribution '$WslDistribution' cannot execute the bridge preflight. See $WslDiagnosticsPath"
}
if ($preflight.Stdout -notmatch [regex]::Escape("WSL_DISTRO_NAME=$WslDistribution") -or $preflight.Stdout -notmatch 'BASH_READY=1') {
    throw "WSL preflight did not prove explicit '$WslDistribution' and Bash readiness. See $WslDiagnosticsPath"
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
    throw "WSL standalone clone did not prove explicit Ubuntu and exact AgentSwitchboard HEAD. See $BootstrapStdoutPath"
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
    throw "Owning FirstMate harness contract failed inside the WSL-owned clone. Evidence: $EvidenceRoot"
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
    "WSL_STDERR=$WslDiagnosticsPath"
)
if ($probe.ExitCode -ne 0) {
    Write-Host "WSL_WORKSPACE_PRESERVED=$wslWorkspace"
    throw "FirstMate read-only interoperability floor failed. Evidence: $ProbePath"
}

Write-Host $contract.Stdout.TrimEnd()
Write-Host $probe.Stdout.TrimEnd()
Write-Host '[PASS] FIRSTMATE_WINDOWS_WSL_RUNTIME_FLOOR'
Write-Host "HEAD=$actualHead"
Write-Host "WSL_DISTRIBUTION=$WslDistribution"
Write-Host "FLOOR_EVIDENCE=$ProbePath"
Write-Host "WSL_DIAGNOSTICS=$WslDiagnosticsPath"
Write-Host "WSL_WORKSPACE_PRESERVED=$wslWorkspace"
Write-Host '[PROOF_CEILING] Physical WSL interoperability floor only; no FirstMate crew task was dispatched or supervised.'
