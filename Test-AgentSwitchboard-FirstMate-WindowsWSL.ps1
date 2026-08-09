[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{40}$')]
    [string]$ExpectedHead,

    [string]$FirstMatePath,

    [string]$SourceRepositoryPath,

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
        [Parameter(Mandatory = $true)][string]$Command,
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
    $EvidenceRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('AgentSwitchboard\firstmate-windows-wsl\' + $actualHead.Substring(0, 8))
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
    "WSL_WORKSPACE=$wslWorkspace"
    "NOTE=Windows paths cross into WSL only through WSLENV /p translation; WSL stdout and stderr remain separate."
    "NOTE=The Linux runtime uses a WSL-owned standalone clone, never the Windows linked-worktree .git indirection."
)

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
printf 'WSL_WORKSPACE=%s\n' "$ASB_WSL_WORKSPACE"
printf 'HEAD=%s\n' "$actual"
'@

$bootstrap = Invoke-WslProcess `
    -Command $bootstrapCommand `
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
if ($bootstrap.Stdout -notmatch [regex]::Escape("HEAD=$actualHead")) {
    throw "WSL standalone clone did not resolve the expected AgentSwitchboard HEAD. See $BootstrapStdoutPath"
}

$workspaceEnvironment = @{
    ASB_WSL_WORKSPACE = $wslWorkspace
}

$visibility = Invoke-WslProcess `
    -Command 'set -euo pipefail; cd "$ASB_WSL_WORKSPACE"; printf "WSL_PWD=%s\n" "$PWD"; git rev-parse HEAD' `
    -Environment $workspaceEnvironment
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'visibility' -Text $visibility.Stderr
if ($visibility.ExitCode -ne 0) {
    throw "WSL cannot execute inside its standalone exact-head AgentSwitchboard clone. See $WslDiagnosticsPath"
}
$visibilityLines = @($visibility.Stdout -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($visibilityLines.Count -lt 2 -or $visibilityLines[-1].Trim() -ne $actualHead) {
    throw "WSL did not resolve the same AgentSwitchboard HEAD in its standalone clone. See $WslDiagnosticsPath"
}

$contract = Invoke-WslProcess `
    -Command 'set -euo pipefail; cd "$ASB_WSL_WORKSPACE"; bash Test-AgentSwitchboard-FirstMate-Harness.sh contract' `
    -Environment $workspaceEnvironment
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'contract' -Text $contract.Stderr
if ($contract.ExitCode -ne 0) {
    Set-Content -LiteralPath (Join-Path $EvidenceRoot 'contract-stdout.txt') -Value $contract.Stdout
    throw "Owning First Mate harness contract failed. Evidence: $EvidenceRoot"
}
Write-Host $contract.Stdout.TrimEnd()

$report = Invoke-WslProcess `
    -Command 'set -euo pipefail; cd "$ASB_WSL_WORKSPACE"; python3 tooling/firstmate/harness/operational/Build-FirstMateHarnessReport.py --stdout' `
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
    -Command $probeCommand `
    -Environment $probeEnvironment `
    -PathEnvironmentNames $probePathEnvironmentNames
Add-WslDiagnostic -Path $WslDiagnosticsPath -Stage 'probe' -Text $probe.Stderr
Set-Content -LiteralPath $ProbePath -Value @(
    "EXIT_CODE=$($probe.ExitCode)"
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
    -Command 'set -euo pipefail; cd "$ASB_WSL_WORKSPACE"; python3 tooling/firstmate/harness/operational/Select-FirstMateWorkflow.py --parallel-writers 3 --firstmate-floor pass --platform linux-wsl' `
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
Write-Host "REPORT=$ReportPath"
Write-Host "FLOOR_EVIDENCE=$ProbePath"
Write-Host "ROUTE=$RoutePath"
Write-Host "WSL_DIAGNOSTICS=$WslDiagnosticsPath"
Write-Host "WSL_WORKSPACE_PRESERVED=$wslWorkspace"
