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

function Convert-WindowsPathToWsl {
    param([Parameter(Mandatory)][string]$WindowsPath)

    $resolved = [IO.Path]::GetFullPath($WindowsPath)
    if ($resolved -notmatch '^(?<drive>[A-Za-z]):\(?<rest>.*)$') {
        throw "Only drive-letter Windows paths can be mapped to WSL: $resolved"
    }

    "/mnt/$($Matches.drive.ToLowerInvariant())/$($Matches.rest -replace '\\','/')"
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

$resolvedManifest = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$manifest = Get-Content -LiteralPath $resolvedManifest -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1 -or -not $manifest.opencode.enabled) {
    throw "Manifest does not enable the managed OpenCode configuration: $resolvedManifest"
}

$distribution = [string]$manifest.distribution
if ($distribution -notmatch '^[A-Za-z0-9._-]+$') {
    throw "Unsafe WSL distribution name: $distribution"
}

$configurator = Join-Path $PSScriptRoot "scripts\configure-opencode-free-defaults.sh"
if (-not (Test-Path -LiteralPath $configurator -PathType Leaf)) {
    throw "OpenCode configurator is missing: $configurator"
}

$manifestJson = $manifest | ConvertTo-Json -Depth 12 -Compress
$config64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($manifestJson))
$configuratorWsl = Convert-WindowsPathToWsl -WindowsPath $configurator
$modeArgument = if ($PlanOnly) { " --plan-only" } else { "" }
$command = "printf '%s' '$config64' | base64 -d | bash '$configuratorWsl'$modeArgument"

Write-Host "Repo-root manifest: $resolvedManifest"
Write-Host "WSL distribution:   $distribution"
Write-Host "OpenCode config:    $($manifest.opencode.configPath)"
Write-Host "Default model:      $($manifest.opencode.defaultModel)"
Write-Host "Small model:        $($manifest.opencode.smallModel)"
Write-Host "Mode:               $(if ($PlanOnly) { 'PLAN' } else { 'APPLY' })"

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
        defaultModel = [string]$manifest.opencode.defaultModel
        smallModel = [string]$manifest.opencode.smallModel
    }
}

$inspectCommand = @'
set -euo pipefail
config="$HOME/.config/opencode/opencode.json"
summary="$HOME/.local/state/agent-switchboard/tmux-gnhf/opencode-free-defaults-summary.json"
test -f "$config"
test -f "$summary"
jq -c '{model,small_model,share,whitelist:.provider.opencode.whitelist}' "$config"
'@
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
    configPath = [string]$manifest.opencode.configPath
    defaultModel = [string]$installed.model
    smallModel = [string]$installed.small_model
    freeModelIds = $actualModels
    paidDefaultAllowed = $false
}
