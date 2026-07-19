[CmdletBinding()]
param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot "tmux-gnhf-workstation.example.json"),
    [string]$WslExe = "wsl.exe",
    [switch]$PlanOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw "PowerShell 7 or newer is required."
}
if ($env:OS -ne "Windows_NT") {
    throw "This installer configures the WSL OpenCode instance from Windows."
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 60
    )

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    foreach ($argument in $ArgumentList) { [void]$psi.ArgumentList.Add($argument) }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill($true); $process.WaitForExit() } catch {}
        throw "Command timed out after $TimeoutSeconds seconds: $FilePath"
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
    $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
    [pscustomobject]@{
        ExitCode = $process.ExitCode
        Stdout = $stdout
        Stderr = $stderr
        Output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
}

function ConvertTo-LfText {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $Text = $Text -replace "`r`n", "`n"
    $Text -replace "`r", "`n"
}

$resolvedManifest = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$manifest = Get-Content -LiteralPath $resolvedManifest -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or -not $manifest.opencode.enabled) {
    throw "Manifest does not enable the managed OpenCode configuration: $resolvedManifest"
}

$distribution = [string]$manifest.distribution
if ($distribution -notmatch '^[A-Za-z0-9._-]+$') {
    throw "Unsafe WSL distribution name: $distribution"
}
$configPath = [string]$manifest.opencode.configPath
if ($configPath -notmatch '^~/[A-Za-z0-9._/-]+$') {
    throw "Unsafe or unsupported WSL OpenCode config path: $configPath"
}

$autoInstallDependencies = $true
$autoInstallProperty = $manifest.opencode.PSObject.Properties['autoInstallDependencies']
if ($null -ne $autoInstallProperty) {
    $autoInstallDependencies = [bool]$autoInstallProperty.Value
}

$configurator = Join-Path $PSScriptRoot "scripts\configure-opencode-free-defaults.sh"
if (-not (Test-Path -LiteralPath $configurator -PathType Leaf)) {
    throw "OpenCode configurator is missing: $configurator"
}

Write-Host "Repo-root manifest: $resolvedManifest"
Write-Host "WSL distribution:   $distribution"
Write-Host "OpenCode config:    $configPath"
Write-Host "Default model:      $($manifest.opencode.defaultModel)"
Write-Host "Small model:        $($manifest.opencode.smallModel)"
Write-Host "Mode:               $(if ($PlanOnly) { 'PLAN' } else { 'APPLY' })"

$jqProbeCommand = ConvertTo-LfText -Text @"
set -euo pipefail
command -v jq >/dev/null 2>&1
"@
$jqProbe = Invoke-BoundedProcess -FilePath $WslExe -ArgumentList @(
    "-d", $distribution, "-e", "bash", "-lc", $jqProbeCommand
) -TimeoutSeconds 30
$jqMissing = $jqProbe.ExitCode -ne 0

if ($jqMissing -and $PlanOnly) {
    Write-Host "[PLAN] Missing WSL dependency: jq"
    Write-Host "[PLAN] Install through apt as WSL root: $autoInstallDependencies"
    return [pscustomobject]@{
        status = "plan-only"
        distribution = $distribution
        manifestPath = $resolvedManifest
        configPath = $configPath
        defaultModel = [string]$manifest.opencode.defaultModel
        smallModel = [string]$manifest.opencode.smallModel
        missingDependencies = @("jq")
        wouldInstallDependencies = $autoInstallDependencies
    }
}

if ($jqMissing -and -not $autoInstallDependencies) {
    throw "Required WSL dependency is missing and automatic dependency installation is disabled: jq"
}

if ($jqMissing) {
    Write-Host "[REPAIR] Installing WSL dependency through apt: jq"
    $aptCommand = ConvertTo-LfText -Text @"
set -euo pipefail
command -v apt-get >/dev/null 2>&1
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends jq
command -v jq >/dev/null 2>&1
"@
    $aptResult = Invoke-BoundedProcess -FilePath $WslExe -ArgumentList @(
        "-d", $distribution, "-u", "root", "-e", "bash", "-lc", $aptCommand
    ) -TimeoutSeconds 300
    Write-Host $aptResult.Output
    if ($aptResult.ExitCode -ne 0) {
        throw "Unable to install jq in WSL through apt. Exit code: $($aptResult.ExitCode)."
    }
}

$manifestJson = $manifest | ConvertTo-Json -Depth 12 -Compress
$config64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($manifestJson))

# Never execute a Windows-mounted shell script directly. Git may check it out
# with CRLF even when the repository blob is LF, which makes Bash parse
# `set -euo pipefail` as an invalid option. Normalize and stage the script in
# WSL before execution so local core.autocrlf settings cannot break setup.
$configuratorText = ConvertTo-LfText -Text (Get-Content -LiteralPath $configurator -Raw)
$configurator64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($configuratorText))
$modeArgument = if ($PlanOnly) { " --plan-only" } else { "" }
$command = @"
set -euo pipefail
script=`$(mktemp)
trap 'rm -f "`$script"' EXIT
printf '%s' '$configurator64' | base64 -d > "`$script"
chmod 0700 "`$script"
printf '%s' '$config64' | base64 -d | bash "`$script"$modeArgument
"@
$command = ConvertTo-LfText -Text $command

$result = Invoke-BoundedProcess -FilePath $WslExe -ArgumentList @(
    "-d", $distribution, "-e", "bash", "-lc", $command
) -TimeoutSeconds 90
Write-Host $result.Output
if ($result.ExitCode -ne 0) {
    throw "OpenCode free-default configuration failed with exit code $($result.ExitCode)."
}

if ($PlanOnly) {
    return [pscustomobject]@{
        status = "plan-only"
        distribution = $distribution
        manifestPath = $resolvedManifest
        configPath = $configPath
        defaultModel = [string]$manifest.opencode.defaultModel
        smallModel = [string]$manifest.opencode.smallModel
        missingDependencies = @()
        wouldInstallDependencies = $false
    }
}

$configSuffix = $configPath.Substring(2)
$configSuffix64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($configSuffix))
$inspectCommand = @"
set -euo pipefail
config="`$HOME/`$(printf '%s' '$configSuffix64' | base64 -d)"
summary="`$HOME/.local/state/agent-switchboard/tmux-gnhf/opencode-free-defaults-summary.json"
test -f "`$config"
test -f "`$summary"
jq -c '{model,small_model,share,whitelist:.provider.opencode.whitelist}' "`$config"
"@
$inspectCommand = ConvertTo-LfText -Text $inspectCommand
$inspection = Invoke-BoundedProcess -FilePath $WslExe -ArgumentList @(
    "-d", $distribution, "-e", "bash", "-lc", $inspectCommand
) -TimeoutSeconds 30
if ($inspection.ExitCode -ne 0 -or -not $inspection.Stdout) {
    throw "Installed OpenCode configuration could not be verified. $($inspection.Output)"
}
$installed = $inspection.Stdout | ConvertFrom-Json
$expectedModels = @($manifest.opencode.freeModelIds | ForEach-Object { [string]$_ })
$actualModels = @($installed.whitelist | ForEach-Object { [string]$_ })
if (
    $installed.model -ne [string]$manifest.opencode.defaultModel -or
    $installed.small_model -ne [string]$manifest.opencode.smallModel -or
    $installed.share -ne "disabled" -or
    (@(Compare-Object -ReferenceObject $expectedModels -DifferenceObject $actualModels).Count -ne 0)
) {
    throw "Installed OpenCode configuration does not match the manifest."
}

[pscustomobject]@{
    status = "installed-and-verified"
    distribution = $distribution
    configPath = $configPath
    defaultModel = [string]$installed.model
    smallModel = [string]$installed.small_model
    freeModelIds = $actualModels
    paidDefaultAllowed = $false
    dependenciesInstalled = @($jqMissing ? "jq" : @())
}
