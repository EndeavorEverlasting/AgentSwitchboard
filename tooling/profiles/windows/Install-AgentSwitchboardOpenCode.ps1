[CmdletBinding()]
param(
    [ValidateSet('Inspect','Apply','Remove')][string]$Mode = 'Inspect',
    [ValidateRange(15, 600)][int]$NetworkTimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

$adapterId = 'opencode'
$toolingRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..') -ErrorAction Stop).Path
$lifecycleModule = Join-Path $toolingRoot 'harness\system-bootstrap-lifecycle\BootstrapLifecycle.psm1'
if (-not (Test-Path -LiteralPath $lifecycleModule -PathType Leaf)) {
    throw "AgentSwitchboard bootstrap lifecycle module is missing: $lifecycleModule"
}
Import-Module $lifecycleModule -Force -ErrorAction Stop

$installDirectory = Join-Path $env:ProgramFiles 'OpenCode'
$targetExe = Join-Path $installDirectory 'opencode.exe'
$managedDirectory = Join-Path $env:ProgramData 'opencode'
$managedJson = Join-Path $managedDirectory 'opencode.json'
$managedJsonc = Join-Path $managedDirectory 'opencode.jsonc'
$lifecycleRoot = Get-ASBLifecycleRoot -AdapterId $adapterId
$statePath = Get-ASBLifecycleStatePath -AdapterId $adapterId
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
$script:lspResolvedEffective = $null
$script:lspResolveProbeStatus = 'not-run'
$script:finalVersion = $null
$script:lifecycleState = $null
$script:lifecycleStatus = 'absent'
$script:ownership = 'none'
$script:removeReady = $false
$script:removeBlockers = @()
$script:rollbackActions = @()

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

function Normalize-OpenCodeVersion {
    param([AllowNull()][string]$Version)
    if ([string]::IsNullOrWhiteSpace($Version)) { return $null }
    return ([string]$Version).Trim().TrimStart([char[]]@('v', 'V'))
}

function ConvertTo-ComparableJson {
    param($Value)
    return ($Value | ConvertTo-Json -Depth 100 -Compress)
}

function Test-JsonValueEqual {
    param($Left, $Right)
    return (ConvertTo-ComparableJson $Left) -ceq (ConvertTo-ComparableJson $Right)
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 30,
        [string]$WorkingDirectory,
        [string[]]$ClearEnvironmentVariables = @()
    )

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.FileName = $FilePath
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $psi.WorkingDirectory = $WorkingDirectory
    }
    foreach ($argument in $ArgumentList) {
        [void]$psi.ArgumentList.Add([string]$argument)
    }
    foreach ($name in $ClearEnvironmentVariables) {
        if ([string]::IsNullOrWhiteSpace($name)) { continue }
        if ($psi.EnvironmentVariables.ContainsKey($name)) {
            [void]$psi.EnvironmentVariables.Remove($name)
        }
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

function Test-OpenCodeResolvedLspEnabled {
    param([Parameter(Mandatory)][string]$Executable)

    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        $script:lspResolveProbeStatus = 'unavailable'
        return $null
    }

    $probeDir = Join-Path ([IO.Path]::GetTempPath()) ("AgentSwitchboard-opencode-lsp-probe-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        $null = New-Item -ItemType Directory -Path $probeDir -Force
        $result = Invoke-BoundedProcess -FilePath $Executable -ArgumentList @('debug', 'config') -TimeoutSeconds 45 -WorkingDirectory $probeDir -ClearEnvironmentVariables @(
            'OPENCODE_CONFIG',
            'OPENCODE_CONFIG_CONTENT',
            'OPENCODE_CONFIG_DIR'
        )
        if ($result.TimedOut -or $result.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($result.Stdout)) {
            $script:lspResolveProbeStatus = 'failed'
            return $null
        }
        try {
            $resolved = $result.Stdout | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        }
        catch {
            $script:lspResolveProbeStatus = 'failed'
            return $null
        }
        if (-not $resolved.ContainsKey('lsp') -or $null -eq $resolved['lsp'] -or $resolved['lsp'] -eq $false) {
            $script:lspResolveProbeStatus = 'pass'
            return $false
        }
        $script:lspResolveProbeStatus = 'pass'
        return $true
    }
    finally {
        if (Test-Path -LiteralPath $probeDir) {
            Remove-Item -LiteralPath $probeDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-MachinePathValue {
    return [Environment]::GetEnvironmentVariable('Path', 'Machine')
}

function Get-MachinePathEntries {
    return @(ConvertTo-ASBPathEntries -PathValue (Get-MachinePathValue))
}

function Test-MachinePathContainsInstallDirectory {
    return Test-ASBPathContainsEntry -PathValue (Get-MachinePathValue) -Entry $installDirectory
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

function Write-ManagedConfig {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Config)
    $null = New-Item -ItemType Directory -Path $managedDirectory -Force
    $temporary = Join-Path $managedDirectory ("opencode.json.$runId.tmp")
    try {
        [IO.File]::WriteAllText($temporary, ($Config | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
        $null = Get-Content -LiteralPath $temporary -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        Move-Item -LiteralPath $temporary -Destination $managedJson -Force
    }
    finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
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

function Get-ManagedConfigBaseline {
    $config = Read-ManagedConfig
    return [ordered]@{
        fileExistedBefore = (Test-Path -LiteralPath $managedJson -PathType Leaf)
        lspBeforePresent = $config.ContainsKey('lsp')
        lspBeforeValue = if ($config.ContainsKey('lsp')) { $config['lsp'] } else { $null }
        schemaBeforePresent = $config.ContainsKey('$schema')
        schemaBeforeValue = if ($config.ContainsKey('$schema')) { $config['$schema'] } else { $null }
    }
}

function New-OpenCodeLifecycleState {
    $configBaseline = Get-ManagedConfigBaseline
    $now = [DateTime]::UtcNow.ToString('o')
    return [ordered]@{
        schema = 'agentswitchboard.system-bootstrap-state.v1'
        adapterId = $adapterId
        lifecycleVersion = 1
        installId = $runId
        status = 'applying'
        createdAt = $now
        updatedAt = $now
        removedAt = $null
        resources = [ordered]@{
            binary = [ordered]@{
                path = $targetExe
                directory = $installDirectory
                directoryExistedBefore = (Test-Path -LiteralPath $installDirectory -PathType Container)
                existedBefore = (Test-Path -LiteralPath $targetExe -PathType Leaf)
                beforeSha256 = Get-ASBFileSha256 -Path $targetExe
                backupPath = $null
                changedByAsb = $false
                afterSha256 = $null
            }
            machinePath = [ordered]@{
                entry = $installDirectory
                presentBefore = (Test-MachinePathContainsInstallDirectory)
                addedByAsb = $false
            }
            managedConfig = [ordered]@{
                jsonPath = $managedJson
                jsoncPath = $managedJsonc
                fileExistedBefore = $configBaseline['fileExistedBefore']
                lspBeforePresent = $configBaseline['lspBeforePresent']
                lspBeforeValue = $configBaseline['lspBeforeValue']
                lspChangedByAsb = $false
                schemaBeforePresent = $configBaseline['schemaBeforePresent']
                schemaBeforeValue = $configBaseline['schemaBeforeValue']
                schemaChangedByAsb = $false
            }
        }
    }
}

function Assert-LifecycleState {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)
    if ([string]$State['schema'] -ne 'agentswitchboard.system-bootstrap-state.v1') {
        Stop-NativeBootstrap 'OPENCODE_LIFECYCLE_STATE_SCHEMA_INVALID' 'OpenCode lifecycle state schema is unsupported.'
    }
    if ([string]$State['adapterId'] -ne $adapterId) {
        Stop-NativeBootstrap 'OPENCODE_LIFECYCLE_STATE_ADAPTER_INVALID' 'OpenCode lifecycle state belongs to another adapter.'
    }
    if (-not $State.Contains('resources')) {
        Stop-NativeBootstrap 'OPENCODE_LIFECYCLE_STATE_INCOMPLETE' 'OpenCode lifecycle state has no resource ownership map.'
    }
}

function Save-LifecycleState {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)
    $State['updatedAt'] = [DateTime]::UtcNow.ToString('o')
    Write-ASBLifecycleStateAtomic -StatePath $statePath -State $State
    $script:lifecycleState = $State
    $script:lifecycleStatus = [string]$State['status']
}

function Get-RemovalBlockers {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$State)
    $blockers = [System.Collections.Generic.List[string]]::new()
    $resources = $State['resources']
    $binary = $resources['binary']
    $pathState = $resources['machinePath']
    $configState = $resources['managedConfig']

    if ([bool]$binary['changedByAsb']) {
        if (-not (Test-Path -LiteralPath $targetExe -PathType Leaf)) {
            [void]$blockers.Add('binary-missing')
        }
        else {
            $currentSha = Get-ASBFileSha256 -Path $targetExe
            if ([string]::IsNullOrWhiteSpace([string]$binary['afterSha256']) -or $currentSha -ne [string]$binary['afterSha256']) {
                [void]$blockers.Add('binary-drift')
            }
        }
        if ([bool]$binary['existedBefore']) {
            $backupPath = [string]$binary['backupPath']
            if ([string]::IsNullOrWhiteSpace($backupPath) -or -not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
                [void]$blockers.Add('binary-backup-missing')
            }
            elseif ((Get-ASBFileSha256 -Path $backupPath) -ne [string]$binary['beforeSha256']) {
                [void]$blockers.Add('binary-backup-drift')
            }
        }
    }

    if ([bool]$configState['lspChangedByAsb'] -or [bool]$configState['schemaChangedByAsb']) {
        if (Test-Path -LiteralPath $managedJsonc -PathType Leaf) {
            [void]$blockers.Add('managed-jsonc-now-present')
        }
        elseif (-not (Test-Path -LiteralPath $managedJson -PathType Leaf)) {
            [void]$blockers.Add('managed-json-missing')
        }
        else {
            try {
                $current = Get-Content -LiteralPath $managedJson -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                if ([bool]$configState['lspChangedByAsb']) {
                    if (-not $current.ContainsKey('lsp') -or -not (Test-JsonValueEqual $current['lsp'] $true)) {
                        [void]$blockers.Add('managed-lsp-drift')
                    }
                }
                if ([bool]$configState['schemaChangedByAsb']) {
                    if (-not $current.ContainsKey('$schema') -or [string]$current['$schema'] -ne 'https://opencode.ai/config.json') {
                        [void]$blockers.Add('managed-schema-drift')
                    }
                }
            }
            catch {
                [void]$blockers.Add('managed-json-invalid')
            }
        }
    }

    if ([bool]$pathState['addedByAsb']) {
        # Missing is already effectively rolled back and is not a blocker. An exact present entry is safe to remove.
        $null = Test-MachinePathContainsInstallDirectory
    }

    return @($blockers)
}

function Restore-ManagedConfigFromState {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$ConfigState)
    if (-not [bool]$ConfigState['lspChangedByAsb'] -and -not [bool]$ConfigState['schemaChangedByAsb']) { return }

    $config = Get-Content -LiteralPath $managedJson -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if ([bool]$ConfigState['lspChangedByAsb']) {
        if ([bool]$ConfigState['lspBeforePresent']) { $config['lsp'] = $ConfigState['lspBeforeValue'] }
        else { [void]$config.Remove('lsp') }
    }
    if ([bool]$ConfigState['schemaChangedByAsb']) {
        if ([bool]$ConfigState['schemaBeforePresent']) { $config['$schema'] = $ConfigState['schemaBeforeValue'] }
        else { [void]$config.Remove('$schema') }
    }

    if (-not [bool]$ConfigState['fileExistedBefore'] -and $config.Count -eq 0) {
        Remove-Item -LiteralPath $managedJson -Force
        if (Test-ASBDirectoryEmpty -Path $managedDirectory) {
            Remove-Item -LiteralPath $managedDirectory -Force
        }
    }
    else {
        Write-ManagedConfig -Config $config
    }
    $script:managedConfigChanged = $true
    $script:rollbackActions += 'managed-config-restored'
}

function Invoke-OpenCodeRemove {
    $state = Read-ASBLifecycleState -StatePath $statePath
    if ($null -eq $state) {
        $present = (Test-Path -LiteralPath $targetExe -PathType Leaf) -or (Test-MachinePathContainsInstallDirectory) -or (Test-Path -LiteralPath $managedJson -PathType Leaf)
        if ($present) {
            Stop-NativeBootstrap 'OPENCODE_REMOVE_OWNERSHIP_UNPROVEN' 'OpenCode machine surfaces are present but no durable AgentSwitchboard lifecycle state proves ownership. Remove is intentionally blocked.'
        }
        $script:status = 'already-absent'
        $script:lifecycleStatus = 'absent'
        $script:ownership = 'none'
        $script:removeReady = $true
        return
    }

    Assert-LifecycleState -State $state
    $script:lifecycleState = $state
    $script:lifecycleStatus = [string]$state['status']
    $script:ownership = 'recorded'

    if ([string]$state['status'] -eq 'removed') {
        $script:status = 'already-removed'
        $script:removeReady = $true
        return
    }
    if ([string]$state['status'] -notin @('installed','applying','removing','drifted')) {
        Stop-NativeBootstrap 'OPENCODE_REMOVE_STATE_INVALID' "OpenCode lifecycle state '$($state['status'])' cannot be removed safely."
    }

    $blockers = @(Get-RemovalBlockers -State $state)
    $script:removeBlockers = $blockers
    $script:removeReady = $blockers.Count -eq 0
    if ($blockers.Count -gt 0) {
        $state['status'] = 'drifted'
        Save-LifecycleState -State $state
        Stop-NativeBootstrap 'OPENCODE_REMOVE_DRIFT_DETECTED' ("Remove blocked before rollback because owned state drifted: " + ($blockers -join ', '))
    }

    $state['status'] = 'removing'
    Save-LifecycleState -State $state
    $resources = $state['resources']
    $configState = $resources['managedConfig']
    $pathState = $resources['machinePath']
    $binary = $resources['binary']

    Restore-ManagedConfigFromState -ConfigState $configState

    if ([bool]$pathState['addedByAsb'] -and (Test-MachinePathContainsInstallDirectory)) {
        $removedPath = Remove-ASBPathEntry -PathValue (Get-MachinePathValue) -Entry $installDirectory
        [Environment]::SetEnvironmentVariable('Path', $removedPath.Value, 'Machine')
        $script:machinePathChanged = [bool]$removedPath.Changed
        $script:rollbackActions += 'machine-path-entry-removed'
    }

    if ([bool]$binary['changedByAsb']) {
        if ([bool]$binary['existedBefore']) {
            $backupPath = [string]$binary['backupPath']
            $incoming = Join-Path $installDirectory 'opencode.exe.restore'
            Copy-Item -LiteralPath $backupPath -Destination $incoming -Force
            Move-Item -LiteralPath $incoming -Destination $targetExe -Force
            if ((Get-ASBFileSha256 -Path $targetExe) -ne [string]$binary['beforeSha256']) {
                Stop-NativeBootstrap 'OPENCODE_REMOVE_BINARY_RESTORE_FAILED' 'Pre-ASB OpenCode binary did not restore to its recorded SHA-256.'
            }
            $script:rollbackActions += 'binary-restored'
        }
        else {
            Remove-Item -LiteralPath $targetExe -Force
            if (Test-Path -LiteralPath $targetExe -PathType Leaf) {
                Stop-NativeBootstrap 'OPENCODE_REMOVE_BINARY_DELETE_FAILED' 'ASB-created OpenCode binary still exists after Remove.'
            }
            $script:rollbackActions += 'binary-removed'
            if (-not [bool]$binary['directoryExistedBefore'] -and (Test-ASBDirectoryEmpty -Path $installDirectory)) {
                Remove-Item -LiteralPath $installDirectory -Force
                $script:rollbackActions += 'empty-install-directory-removed'
            }
        }
    }

    if ([bool]$pathState['addedByAsb'] -and (Test-MachinePathContainsInstallDirectory)) {
        Stop-NativeBootstrap 'OPENCODE_REMOVE_PATH_VERIFY_FAILED' 'ASB-owned OpenCode Machine PATH entry remains after Remove.'
    }
    if ([bool]$configState['lspChangedByAsb'] -or [bool]$configState['schemaChangedByAsb']) {
        if (Test-Path -LiteralPath $managedJson -PathType Leaf) {
            $restored = Get-Content -LiteralPath $managedJson -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if ([bool]$configState['lspBeforePresent']) {
                if (-not $restored.ContainsKey('lsp') -or -not (Test-JsonValueEqual $restored['lsp'] $configState['lspBeforeValue'])) {
                    Stop-NativeBootstrap 'OPENCODE_REMOVE_CONFIG_VERIFY_FAILED' 'Managed lsp property did not return to its pre-ASB value.'
                }
            }
            elseif ($restored.ContainsKey('lsp')) {
                Stop-NativeBootstrap 'OPENCODE_REMOVE_CONFIG_VERIFY_FAILED' 'ASB-added managed lsp property remains after Remove.'
            }
        }
        elseif ([bool]$configState['fileExistedBefore']) {
            Stop-NativeBootstrap 'OPENCODE_REMOVE_CONFIG_VERIFY_FAILED' 'Preexisting managed config file disappeared during Remove.'
        }
    }

    $backupPathToDelete = [string]$binary['backupPath']
    if (-not [string]::IsNullOrWhiteSpace($backupPathToDelete) -and (Test-Path -LiteralPath $backupPathToDelete -PathType Leaf)) {
        Remove-Item -LiteralPath $backupPathToDelete -Force
        $backupParent = Split-Path -Parent $backupPathToDelete
        if (Test-ASBDirectoryEmpty -Path $backupParent) { Remove-Item -LiteralPath $backupParent -Force }
        $binary['backupPath'] = $null
    }

    $state['status'] = 'removed'
    $state['removedAt'] = [DateTime]::UtcNow.ToString('o')
    Save-LifecycleState -State $state
    $script:status = 'removed'
    $script:removeReady = $true
}

function Write-Receipt {
    $receipt = [ordered]@{
        schema = 'agentswitchboard.opencode-native-system-bootstrap.v2'
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
        lspResolvedEffective = $script:lspResolvedEffective
        lspResolveProbeStatus = $script:lspResolveProbeStatus
        finalVersion = $script:finalVersion
        lifecycleStatePath = $statePath
        lifecycleStatus = $script:lifecycleStatus
        ownership = $script:ownership
        removeReady = $script:removeReady
        removeBlockers = @($script:removeBlockers)
        rollbackActions = @($script:rollbackActions)
        packageManagerAssumed = $false
        userScopedNodeOrNpmRequired = $false
        proofCeiling = 'Proves the observed OpenCode machine state plus durable AgentSwitchboard ownership/rollback state. Apply proves binary/PATH/managed-config convergence; Remove proves only ASB-recorded deltas were reversed. Active language-server behavior still requires opening a supported file in OpenCode.'
    }
    $receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM

    @(
        '# OpenCode native system bootstrap lifecycle', '',
        "- Mode: ``$Mode``",
        "- Status: ``$($script:status)``",
        "- Failure: ``$($script:failureCode)``",
        "- Lifecycle state: ``$statePath``",
        "- Lifecycle status: ``$($script:lifecycleStatus)``",
        "- Ownership: ``$($script:ownership)``",
        "- Remove ready: ``$($script:removeReady)``",
        "- Remove blockers: ``$($script:removeBlockers -join ', ')``",
        "- Rollback actions: ``$($script:rollbackActions -join ', ')``",
        "- Executable: ``$targetExe``",
        "- Existing version: ``$($script:existingVersion)``",
        "- Selected version: ``$($script:selectedVersion)``",
        "- Final version: ``$($script:finalVersion)``",
        "- Machine PATH: ``$(Test-MachinePathContainsInstallDirectory)``",
        "- Managed config: ``$managedJson``",
        "- LSP enabled (managed file): ``$(Test-LspEnabled)``",
        "- LSP resolved effective (debug config): ``$($script:lspResolvedEffective)``",
        "- LSP resolve probe: ``$($script:lspResolveProbeStatus)``", '',
        'Machine ownership is journaled under ProgramData. User credentials, sessions, project state, and unrelated configuration are not owned by this lifecycle.',
        'Remove is fail-closed: drift in an ASB-owned binary or managed config property blocks rollback before destructive mutation.'
    ) | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM

    Write-Host "OPENCODE_NATIVE_BOOTSTRAP_STATUS=$($script:status)"
    Write-Host "OPENCODE_NATIVE_BOOTSTRAP_FAILURE_CODE=$($script:failureCode)"
    Write-Host "OPENCODE_NATIVE_BOOTSTRAP_RECEIPT=$receiptPath"
    Write-Host "OPENCODE_NATIVE_BOOTSTRAP_EXECUTABLE=$targetExe"
    Write-Host "OPENCODE_NATIVE_BOOTSTRAP_VERSION=$($script:finalVersion)"
    Write-Host "OPENCODE_NATIVE_BOOTSTRAP_LSP_ENABLED=$(Test-LspEnabled)"
    Write-Host "OPENCODE_NATIVE_BOOTSTRAP_LSP_RESOLVED=$($script:lspResolvedEffective)"
    Write-Host "OPENCODE_NATIVE_BOOTSTRAP_LSP_PROBE=$($script:lspResolveProbeStatus)"
    Write-Host "OPENCODE_NATIVE_BOOTSTRAP_LIFECYCLE_STATE=$statePath"
    Write-Host "OPENCODE_NATIVE_BOOTSTRAP_REMOVE_READY=$($script:removeReady)"
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
    $script:lifecycleState = Read-ASBLifecycleState -StatePath $statePath
    if ($script:lifecycleState) {
        Assert-LifecycleState -State $script:lifecycleState
        $script:lifecycleStatus = [string]$script:lifecycleState['status']
        $script:ownership = 'recorded'
    }

    if ($Mode -eq 'Inspect') {
        $script:finalVersion = $script:existingVersion
        if (Test-Path -LiteralPath $targetExe -PathType Leaf) {
            $script:lspResolvedEffective = Test-OpenCodeResolvedLspEnabled -Executable $targetExe
        }
        if ($script:lifecycleState -and [string]$script:lifecycleState['status'] -eq 'installed') {
            $script:removeBlockers = @(Get-RemovalBlockers -State $script:lifecycleState)
            $script:removeReady = $script:removeBlockers.Count -eq 0
            if (-not $script:removeReady) { $script:lifecycleStatus = 'drifted-observed' }
        }
        elseif ($script:lifecycleState -and [string]$script:lifecycleState['status'] -eq 'removed') {
            $script:removeReady = $true
        }
        $script:status = 'inspect-complete'
        return
    }

    if (-not $script:isElevated) {
        Stop-NativeBootstrap 'ADMINISTRATOR_REQUIRED' "$Mode mode requires an elevated PowerShell session because Program Files, ProgramData, and Machine PATH are machine-wide surfaces."
    }

    if ($Mode -eq 'Remove') {
        Invoke-OpenCodeRemove
        $script:finalVersion = Get-OpenCodeVersion -Path $targetExe
        return
    }

    if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -notin @('AMD64','ARM64')) {
        Stop-NativeBootstrap 'SUPPORTED_WINDOWS_ARCHITECTURE_REQUIRED' "Unsupported Windows architecture: $env:PROCESSOR_ARCHITECTURE"
    }
    if ($env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        Stop-NativeBootstrap 'WINDOWS_X64_REQUIRED' 'This first native bootstrap contract currently supports Windows x64 only.'
    }

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
    if ([string]::IsNullOrWhiteSpace($stagedVersion) -or (Normalize-OpenCodeVersion $stagedVersion) -ne $script:selectedVersion) {
        Stop-NativeBootstrap 'OPENCODE_STAGED_VERSION_MISMATCH' "Staged executable version '$stagedVersion' does not match selected release '$($script:selectedVersion)'."
    }

    $state = $script:lifecycleState
    if ($state -and [string]$state['status'] -eq 'removed') {
        [void](Archive-ASBLifecycleState -LifecycleRoot $lifecycleRoot -State $state)
        $state = $null
    }
    if ($state -and [string]$state['status'] -eq 'removing') {
        Stop-NativeBootstrap 'OPENCODE_LIFECYCLE_REMOVE_INCOMPLETE' 'A prior Remove was interrupted. Inspect and reconcile that lifecycle before applying again.'
    }
    if ($null -eq $state) {
        $state = New-OpenCodeLifecycleState
        Save-LifecycleState -State $state
    }
    else {
        Assert-LifecycleState -State $state
        $state['status'] = 'applying'
        Save-LifecycleState -State $state
    }

    $binaryState = $state['resources']['binary']
    if ((Normalize-OpenCodeVersion $script:existingVersion) -ne $script:selectedVersion) {
        if ([bool]$binaryState['existedBefore'] -and [string]::IsNullOrWhiteSpace([string]$binaryState['backupPath'])) {
            $backupRoot = Join-Path $lifecycleRoot ("backups\" + [string]$state['installId'])
            $null = New-Item -ItemType Directory -Path $backupRoot -Force
            $backupPath = Join-Path $backupRoot 'opencode.exe.before'
            Copy-Item -LiteralPath $targetExe -Destination $backupPath -Force
            if ((Get-ASBFileSha256 -Path $backupPath) -ne [string]$binaryState['beforeSha256']) {
                Stop-NativeBootstrap 'OPENCODE_LIFECYCLE_BACKUP_VERIFY_FAILED' 'Pre-ASB OpenCode binary backup failed SHA-256 verification.'
            }
            $binaryState['backupPath'] = $backupPath
            Save-LifecycleState -State $state
        }

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
        $binaryState['changedByAsb'] = $true
        $binaryState['afterSha256'] = Get-ASBFileSha256 -Path $targetExe
        Save-LifecycleState -State $state
    }
    elseif ([bool]$binaryState['changedByAsb']) {
        $binaryState['afterSha256'] = Get-ASBFileSha256 -Path $targetExe
        Save-LifecycleState -State $state
    }

    $pathState = $state['resources']['machinePath']
    if (-not (Test-MachinePathContainsInstallDirectory)) {
        $pathMutation = Add-ASBPathEntry -PathValue (Get-MachinePathValue) -Entry $installDirectory -Position Append
        [Environment]::SetEnvironmentVariable('Path', $pathMutation.Value, 'Machine')
        $script:machinePathChanged = [bool]$pathMutation.Changed
        if ($pathMutation.Changed) {
            $pathState['addedByAsb'] = $true
            Save-LifecycleState -State $state
        }
    }

    $configState = $state['resources']['managedConfig']
    $managedChanged = $false
    if (-not $managed.ContainsKey('$schema')) {
        $managed['$schema'] = 'https://opencode.ai/config.json'
        $managedChanged = $true
        $configState['schemaChangedByAsb'] = $true
    }
    if (-not $managed.ContainsKey('lsp') -or $managed['lsp'] -ne $true) {
        $managed['lsp'] = $true
        $managedChanged = $true
        $configState['lspChangedByAsb'] = $true
    }
    if ($managedChanged) {
        if (Test-Path -LiteralPath $managedJson -PathType Leaf) {
            $backupPath = Join-Path $runRoot 'opencode.managed.before.json'
            Copy-Item -LiteralPath $managedJson -Destination $backupPath -Force
            $script:managedConfigBackup = $backupPath
        }
        Write-ManagedConfig -Config $managed
        $readback = Get-Content -LiteralPath $managedJson -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if (-not $readback.ContainsKey('lsp') -or $readback['lsp'] -ne $true) {
            Stop-NativeBootstrap 'OPENCODE_MANAGED_CONFIG_READBACK_FAILED' 'Managed configuration did not read back with lsp=true.'
        }
        $script:managedConfigChanged = $true
        Save-LifecycleState -State $state
    }

    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
    $script:finalVersion = Get-OpenCodeVersion -Path $targetExe
    if ([string]::IsNullOrWhiteSpace($script:finalVersion) -or (Normalize-OpenCodeVersion $script:finalVersion) -ne $script:selectedVersion) {
        Stop-NativeBootstrap 'OPENCODE_FINAL_VERSION_FAILED' 'Machine-wide OpenCode direct version proof failed after installation.'
    }
    if (-not (Test-MachinePathContainsInstallDirectory)) {
        Stop-NativeBootstrap 'OPENCODE_MACHINE_PATH_FAILED' 'Machine PATH does not contain the OpenCode installation directory after Apply.'
    }
    if (-not (Test-LspEnabled)) {
        Stop-NativeBootstrap 'OPENCODE_MANAGED_LSP_FAILED' 'Managed OpenCode configuration did not read back with lsp=true after Apply.'
    }

    $script:lspResolvedEffective = Test-OpenCodeResolvedLspEnabled -Executable $targetExe
    if ($script:lspResolveProbeStatus -ne 'pass') {
        Stop-NativeBootstrap 'OPENCODE_LSP_RESOLVE_PROBE_FAILED' 'OpenCode debug config could not prove that managed lsp configuration is present in the resolved runtime config.'
    }
    if ($script:lspResolvedEffective -ne $true) {
        Stop-NativeBootstrap 'OPENCODE_LSP_NOT_RESOLVED' 'OpenCode resolved configuration still reports LSP disabled after managed lsp=true was written. Restart any already-running OpenCode process and re-run Apply if a stale process retained old config.'
    }

    if ([bool]$binaryState['changedByAsb']) {
        $binaryState['afterSha256'] = Get-ASBFileSha256 -Path $targetExe
    }
    $state['status'] = 'installed'
    Save-LifecycleState -State $state
    $script:removeBlockers = @(Get-RemovalBlockers -State $state)
    $script:removeReady = $script:removeBlockers.Count -eq 0
    if (-not $script:removeReady) {
        Stop-NativeBootstrap 'OPENCODE_POST_APPLY_REMOVE_CONTRACT_FAILED' ("Apply succeeded but immediate reversible-state proof failed: " + ($script:removeBlockers -join ', '))
    }
    $script:ownership = 'recorded'
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
    if ($null -eq $script:lspResolvedEffective -and $script:lspResolveProbeStatus -eq 'not-run' -and $script:finalVersion -and (Test-Path -LiteralPath $targetExe -PathType Leaf)) {
        $script:lspResolvedEffective = Test-OpenCodeResolvedLspEnabled -Executable $targetExe
    }
    if ($null -eq $script:lifecycleState) {
        try { $script:lifecycleState = Read-ASBLifecycleState -StatePath $statePath } catch {}
    }
    if ($script:lifecycleState) {
        $script:lifecycleStatus = [string]$script:lifecycleState['status']
        $script:ownership = 'recorded'
    }
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
