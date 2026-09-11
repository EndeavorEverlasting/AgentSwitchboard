[CmdletBinding()]
param(
    [ValidateSet('Inspect','Apply')][string]$Mode = 'Inspect',
    [ValidateRange(15, 600)][int]$NetworkTimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

$installDirectory = Join-Path $env:ProgramFiles 'OpenCode'
$targetExe = Join-Path $installDirectory 'opencode.exe'
$managedDirectory = Join-Path $env:ProgramData 'opencode'
$managedJson = Join-Path $managedDirectory 'opencode.json'
$managedJsonc = Join-Path $managedDirectory 'opencode.jsonc'
$stateBase = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
$runId = '{0}-{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runRoot = Join-Path $stateBase "AgentSwitchboard\opencode-native-bootstrap\runs\$runId"
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) "AgentSwitchboard-opencode-native-$runId"
$receiptPath = Join-Path $runRoot 'opencode-native-bootstrap.json'
$reportPath = Join-Path $runRoot 'opencode-native-bootstrap.md'

$script:status = 'failed'
$script:failureCode = $null
$script:failureMessage = $null
$script:isElevated = $false
$script:architecture = $env:PROCESSOR_ARCHITECTURE
$script:existingVersion = $null
$script:selectedVersion = $null
$script:selectedAsset = $null
$script:downloadSha256 = $null
$script:binaryInstalled = $false
$script:machinePathChanged = $false
$script:managedConfigChanged = $false
$script:managedConfigBackup = $null
$script:lspEnabled = $false
$script:finalVersion = $null

function Stop-NativeBootstrap {
    param(
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Message
    )
    throw ([InvalidOperationException]::new("$Code|$Message"))
}

function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 30
    )

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.FileName = $FilePath
    foreach ($argument in $ArgumentList) {
        [void]$psi.ArgumentList.Add([string]$argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) {
        try { $process.Kill($true) } catch {}
        try { $process.WaitForExit() } catch {}
    }

    return [pscustomobject]@{
        ExitCode = if ($timedOut) { $null } else { $process.ExitCode }
        TimedOut = $timedOut
        Stdout = ([string]$stdoutTask.GetAwaiter().GetResult()).Trim()
        Stderr = ([string]$stderrTask.GetAwaiter().GetResult()).Trim()
    }
}

function Get-OpenCodeVersion {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $result = Invoke-BoundedProcess -FilePath $Path -ArgumentList @('--version') -TimeoutSeconds 30
    if ($result.TimedOut -or $result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Stdout)) { return $null }
    return [string](($result.Stdout -split "[`r`n]+" | Where-Object { $_ } | Select-Object -First 1).Trim())
}

function Get-MachinePathEntries {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    return @($machinePath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Test-MachinePathContainsInstallDirectory {
    foreach ($entry in @(Get-MachinePathEntries)) {
        if ($entry.TrimEnd('\') -ieq $installDirectory.TrimEnd('\')) { return $true }
    }
    return $false
}

function Read-ManagedConfig {
    if (Test-Path -LiteralPath $managedJsonc -PathType Leaf) {
        Stop-NativeBootstrap 'OPENCODE_MANAGED_JSONC_PRESENT' "Managed OpenCode JSONC already exists at $managedJsonc. AgentSwitchboard will not create competing managed configuration."
    }
    if (-not (Test-Path -LiteralPath $managedJson -PathType Leaf)) {
        return [ordered]@{}
    }
    try {
        return (Get-Content -LiteralPath $managedJson -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop)
    }
    catch {
        Stop-NativeBootstrap 'OPENCODE_MANAGED_CONFIG_INVALID' "Existing managed OpenCode configuration is not valid JSON: $managedJson"
    }
}

function Test-LspEnabled {
    if (-not (Test-Path -LiteralPath $managedJson -PathType Leaf)) { return $false }
    try {
        $config = Get-Content -LiteralPath $managedJson -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        return $config.ContainsKey('lsp') -and ($config['lsp'] -eq $true)
    }
    catch { return $false }
}

function Write-Receipt {
    $receipt = [ordered]@{
        schema = 'agentswitchboard.opencode-native-system-bootstrap.v1'
        runId = $runId
        mode = $Mode
        status = $script:status
        failureCode = $script:failureCode
        failureMessage = $script:failureMessage
        windows = ($env:OS -eq 'Windows_NT')
        powershellVersion = [string]$PSVersionTable.PSVersion
        elevated = $script:isElevated
        architecture = $script:architecture
        installDirectory = $installDirectory
        executable = $targetExe
        existingVersion = $script:existingVersion
        selectedVersion = $script:selectedVersion
        selectedAsset = $script:selectedAsset
        downloadSha256 = $script:downloadSha256
        binaryInstalled = $script:binaryInstalled
        machinePathContainsInstallDirectory = (Test-MachinePathContainsInstallDirectory)
        machinePathChanged = $script:machinePathChanged
        managedConfig = $managedJson
        managedConfigChanged = $script:managedConfigChanged
        managedConfigBackup = $script:managedConfigBackup
        lspEnabled = (Test-LspEnabled)
        finalVersion = $script:finalVersion
        packageManagerAssumed = $false
        userScopedNodeOrNpmRequired = $false
        proofCeiling = 'Proves native Windows binary placement, machine PATH state, managed lsp=true configuration, and direct version execution. Active language-server behavior still requires opening a supported file in OpenCode and observing runtime LSP evidence.'
    }
    $receipt | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM

    @(
        '# OpenCode native system bootstrap',
        '',
        "- Status: ``$($script:status)``",
        "- Failure: ``$($script:failureCode)``",
        "- Executable: ``$targetExe``",
        "- Existing version: ``$($script:existingVersion)``",
        "- Selected version: ``$($script:selectedVersion)``",
        "- Final version: ``$($script:finalVersion)``",
        "- Machine PATH: ``$(Test-MachinePathContainsInstallDirectory)``",
        "- Managed config: ``$managedJson``",
        "- LSP enabled: ``$(Test-LspEnabled)``",
        '',
        'This bootstrap does not use Chocolatey, Scoop, npm, or another assumed package manager. Apply mode first verifies Windows, PowerShell, architecture, elevation, existing managed-config safety, official release identity, asset identity, and SHA-256 before mutation.',
        '',
        'Configuration proof is not active-LSP proof. Open a supported source file and observe OpenCode LSP runtime behavior for that higher proof level.'
    ) | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM

    Write-Host "OPENCODE_NATIVE_BOOTSTRAP_STATUS=$($script:status)"
    Write-Host "OPENCODE_NATIVE_BOOTSTRAP_FAILURE_CODE=$($script:failureCode)"
    Write-Host "OPENCODE_NATIVE_BOOTSTRAP_RECEIPT=$receiptPath"
    Write-Host "OPENCODE_NATIVE_BOOTSTRAP_EXECUTABLE=$targetExe"
    Write-Host "OPENCODE_NATIVE_BOOTSTRAP_VERSION=$($script:finalVersion)"
    Write-Host "OPENCODE_NATIVE_BOOTSTRAP_LSP_ENABLED=$(Test-LspEnabled)"
}

try {
    $null = New-Item -ItemType Directory -Path $runRoot -Force

    if ($env:OS -ne 'Windows_NT') {
        Stop-NativeBootstrap 'WINDOWS_REQUIRED' 'The native system-wide OpenCode bootstrap is Windows-only.'
    }
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Stop-NativeBootstrap 'POWERSHELL7_REQUIRED' 'PowerShell 7 is required.'
    }
    if ([string]::IsNullOrWhiteSpace($env:ProgramFiles) -or [string]::IsNullOrWhiteSpace($env:ProgramData)) {
        Stop-NativeBootstrap 'WINDOWS_SYSTEM_PATHS_REQUIRED' 'ProgramFiles and ProgramData must be available.'
    }

    $script:isElevated = Test-IsElevated
    $script:existingVersion = Get-OpenCodeVersion -Path $targetExe
    $script:lspEnabled = Test-LspEnabled

    # Inspect is deliberately local and non-mutating. It does not assume or probe a package manager.
    if ($Mode -eq 'Inspect') {
        $script:finalVersion = $script:existingVersion
        $script:status = 'inspect-complete'
        return
    }

    if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -notin @('AMD64','ARM64')) {
        Stop-NativeBootstrap 'SUPPORTED_WINDOWS_ARCHITECTURE_REQUIRED' "Unsupported Windows architecture: $env:PROCESSOR_ARCHITECTURE"
    }
    if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        Stop-NativeBootstrap 'WINDOWS_X64_REQUIRED' 'This first native bootstrap contract currently supports Windows x64 only.'
    }
    if (-not $script:isElevated) {
        Stop-NativeBootstrap 'ADMINISTRATOR_REQUIRED' 'Apply mode requires an elevated PowerShell session because Program Files, ProgramData, and Machine PATH are machine-wide surfaces.'
    }

    # Ascertain managed-config safety before any binary or PATH mutation.
    $managed = Read-ManagedConfig

    $headers = @{
        'User-Agent' = 'AgentSwitchboard-OpenCode-Bootstrap'
        'Accept' = 'application/vnd.github+json'
    }
    try {
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/anomalyco/opencode/releases/latest' -Headers $headers -TimeoutSec $NetworkTimeoutSeconds -ErrorAction Stop
    }
    catch {
        Stop-NativeBootstrap 'OPENCODE_RELEASE_DISCOVERY_FAILED' 'Unable to resolve the latest official anomalyco/opencode release within the bounded network window.'
    }

    $tag = [string]$release.tag_name
    if ($tag -notmatch '^v?(?<version>\d+\.\d+\.\d+)$') {
        Stop-NativeBootstrap 'OPENCODE_RELEASE_TAG_INVALID' "Latest official release tag is not a semantic version: $tag"
    }
    $script:selectedVersion = $Matches['version']

    $assets = @($release.assets | Where-Object { [string]$_.name -eq 'opencode-windows-x64.zip' })
    if ($assets.Count -ne 1) {
        Stop-NativeBootstrap 'OPENCODE_WINDOWS_X64_ASSET_AMBIGUOUS' "Expected exactly one opencode-windows-x64.zip asset; found $($assets.Count)."
    }
    $asset = $assets[0]
    $script:selectedAsset = [string]$asset.name
    $assetUrl = [string]$asset.browser_download_url
    $assetDigest = [string]$asset.digest
    if ([string]::IsNullOrWhiteSpace($assetUrl)) {
        Stop-NativeBootstrap 'OPENCODE_ASSET_URL_MISSING' 'The selected official release asset has no download URL.'
    }
    if ($assetDigest -notmatch '^sha256:(?<sha>[0-9a-fA-F]{64})$') {
        Stop-NativeBootstrap 'OPENCODE_ASSET_SHA256_MISSING' 'The selected official release asset did not expose an authoritative SHA-256 digest. No installation was performed.'
    }
    $expectedSha256 = $Matches['sha'].ToLowerInvariant()

    $null = New-Item -ItemType Directory -Path $stageRoot -Force
    $archivePath = Join-Path $stageRoot 'opencode-windows-x64.zip'
    $extractRoot = Join-Path $stageRoot 'extract'
    try {
        Invoke-WebRequest -Uri $assetUrl -OutFile $archivePath -Headers $headers -TimeoutSec $NetworkTimeoutSeconds -ErrorAction Stop
    }
    catch {
        Stop-NativeBootstrap 'OPENCODE_ASSET_DOWNLOAD_FAILED' 'The official Windows x64 OpenCode archive could not be downloaded within the bounded network window.'
    }

    $actualSha256 = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $script:downloadSha256 = $actualSha256
    if ($actualSha256 -ne $expectedSha256) {
        Stop-NativeBootstrap 'OPENCODE_ASSET_SHA256_MISMATCH' 'Downloaded OpenCode archive SHA-256 did not match the official release digest.'
    }

    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force
    $executables = @(Get-ChildItem -LiteralPath $extractRoot -Filter 'opencode.exe' -File -Recurse)
    if ($executables.Count -ne 1) {
        Stop-NativeBootstrap 'OPENCODE_ARCHIVE_LAYOUT_UNEXPECTED' "Expected exactly one opencode.exe in the official archive; found $($executables.Count)."
    }
    $stagedExe = $executables[0].FullName
    $stagedVersion = Get-OpenCodeVersion -Path $stagedExe
    if ([string]::IsNullOrWhiteSpace($stagedVersion) -or $stagedVersion.TrimStart('v') -ne $script:selectedVersion) {
        Stop-NativeBootstrap 'OPENCODE_STAGED_VERSION_MISMATCH' "Staged executable version '$stagedVersion' does not match selected release '$($script:selectedVersion)'."
    }

    if ($script:existingVersion -ne $script:selectedVersion) {
        $null = New-Item -ItemType Directory -Path $installDirectory -Force
        $incoming = Join-Path $installDirectory 'opencode.exe.new'
        Copy-Item -LiteralPath $stagedExe -Destination $incoming -Force
        try {
            Move-Item -LiteralPath $incoming -Destination $targetExe -Force
        }
        catch {
            Remove-Item -LiteralPath $incoming -Force -ErrorAction SilentlyContinue
            Stop-NativeBootstrap 'OPENCODE_BINARY_REPLACE_FAILED' 'Unable to replace the machine-wide OpenCode binary. Close any process locking the target and retry.'
        }
        $script:binaryInstalled = $true
    }

    if (-not (Test-MachinePathContainsInstallDirectory)) {
        $entries = @(Get-MachinePathEntries)
        [Environment]::SetEnvironmentVariable('Path', (($entries + $installDirectory) -join ';'), 'Machine')
        $script:machinePathChanged = $true
    }

    $managedChanged = $false
    if (-not $managed.ContainsKey('$schema')) {
        $managed['$schema'] = 'https://opencode.ai/config.json'
        $managedChanged = $true
    }
    if (-not $managed.ContainsKey('lsp') -or $managed['lsp'] -ne $true) {
        $managed['lsp'] = $true
        $managedChanged = $true
    }
    if ($managedChanged) {
        $null = New-Item -ItemType Directory -Path $managedDirectory -Force
        if (Test-Path -LiteralPath $managedJson -PathType Leaf) {
            $backupPath = Join-Path $runRoot 'opencode.managed.before.json'
            Copy-Item -LiteralPath $managedJson -Destination $backupPath -Force
            $script:managedConfigBackup = $backupPath
        }
        $tempConfig = Join-Path $managedDirectory "opencode.json.$runId.tmp"
        $managedJsonText = $managed | ConvertTo-Json -Depth 100
        [IO.File]::WriteAllText($tempConfig, $managedJsonText, [Text.UTF8Encoding]::new($false))
        try {
            $readback = Get-Content -LiteralPath $tempConfig -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if (-not $readback.ContainsKey('lsp') -or $readback['lsp'] -ne $true) {
                Stop-NativeBootstrap 'OPENCODE_MANAGED_CONFIG_READBACK_FAILED' 'Staged managed configuration did not read back with lsp=true.'
            }
            Move-Item -LiteralPath $tempConfig -Destination $managedJson -Force
        }
        finally {
            Remove-Item -LiteralPath $tempConfig -Force -ErrorAction SilentlyContinue
        }
        $script:managedConfigChanged = $true
    }

    # Refresh this process from authoritative machine + user PATH only after mutation.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    $script:finalVersion = Get-OpenCodeVersion -Path $targetExe
    if ([string]::IsNullOrWhiteSpace($script:finalVersion) -or $script:finalVersion.TrimStart('v') -ne $script:selectedVersion) {
        Stop-NativeBootstrap 'OPENCODE_FINAL_VERSION_FAILED' 'Machine-wide OpenCode direct version proof failed after installation.'
    }
    if (-not (Test-MachinePathContainsInstallDirectory)) {
        Stop-NativeBootstrap 'OPENCODE_MACHINE_PATH_FAILED' 'Machine PATH does not contain the OpenCode installation directory after Apply.'
    }
    if (-not (Test-LspEnabled)) {
        Stop-NativeBootstrap 'OPENCODE_MANAGED_LSP_FAILED' 'Managed OpenCode configuration did not read back with lsp=true after Apply.'
    }

    $script:status = 'success'
}
catch {
    $raw = [string]$_.Exception.Message
    if ($raw -match '^([A-Z0-9_]+)\|(.*)$') {
        $script:failureCode = $Matches[1]
        $script:failureMessage = $Matches[2]
    }
    else {
        $script:failureCode = 'OPENCODE_NATIVE_BOOTSTRAP_UNEXPECTED_FAILURE'
        $script:failureMessage = $raw
    }
    $script:status = 'failed'
}
finally {
    if (-not (Test-Path -LiteralPath $runRoot -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $runRoot -Force
    }
    $script:lspEnabled = Test-LspEnabled
    if (-not $script:finalVersion) { $script:finalVersion = Get-OpenCodeVersion -Path $targetExe }
    Write-Receipt
    if (Test-Path -LiteralPath $stageRoot) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($script:status -eq 'failed') {
    Write-Error "$($script:failureCode): $($script:failureMessage)"
    exit 1
}
exit 0
