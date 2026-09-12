[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('Enable', 'Disable', 'Status', 'Run', 'Open')]
    [string]$Action = 'Status',

    [ValidateRange(15, 1440)]
    [int]$IntervalMinutes = 60,

    [ValidateRange(1, 10)]
    [int]$RetentionCount = 2,

    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\prompt-kit-sync'),

    [string]$TaskName = 'AgentSwitchboard-PromptKitWebsiteSync'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceSyncScript = Join-Path $PSScriptRoot 'Sync-PromptKitWebsite.ps1'
$RuntimeRoot = Join-Path $StateRoot 'runtime'
$RuntimeSyncScript = Join-Path $RuntimeRoot 'Sync-PromptKitWebsite.ps1'
$ConfigPath = Join-Path $StateRoot 'config.json'
$StatePath = Join-Path $StateRoot 'state.json'
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory)][object]$Value,
        [Parameter(Mandatory)][string]$Path
    )
    $directory = Split-Path -Parent $Path
    $null = New-Item -ItemType Directory -Path $directory -Force
    $tempPath = Join-Path $directory ('.{0}.{1}.tmp' -f ([IO.Path]::GetFileName($Path)), [guid]::NewGuid().ToString('N'))
    try {
        $Value | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tempPath -Encoding UTF8
        Move-Item -LiteralPath $tempPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $tempPath) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Read-Config {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        return [pscustomobject]@{
            schema = 'agentswitchboard.prompt-kit-sync.config.v1'
            enabled = $false
            intervalMinutes = 60
            retentionCount = 2
        }
    }
    return Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-Config {
    param([bool]$Enabled, [int]$Minutes, [int]$Retention)
    $config = [ordered]@{
        schema = 'agentswitchboard.prompt-kit-sync.config.v1'
        enabled = $Enabled
        intervalMinutes = $Minutes
        retentionCount = $Retention
        updatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    }
    Write-JsonAtomic -Value $config -Path $ConfigPath
}

function Get-TaskSafe {
    if (-not (Get-Command 'Get-ScheduledTask' -ErrorAction SilentlyContinue)) {
        return $null
    }
    return Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}

function Get-StatusObject {
    $config = Read-Config
    $task = Get-TaskSafe
    $state = $null
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    return [ordered]@{
        schema = 'agentswitchboard.prompt-kit-sync.management-status.v1'
        enabled = [bool]$config.enabled
        intervalMinutes = [int]$config.intervalMinutes
        retentionCount = [int]$config.retentionCount
        scheduledTaskInstalled = $null -ne $task
        scheduledTaskName = $TaskName
        scheduledTaskState = if ($task) { [string]$task.State } else { $null }
        runtimeScript = $RuntimeSyncScript
        stateRoot = $StateRoot
        sourceSha = if ($state) { [string]$state.sourceSha } else { $null }
        websitePath = if ($state) { [string]$state.websitePath } else { $null }
    }
}

switch ($Action) {
    'Enable' {
        if (-not (Test-Path -LiteralPath $SourceSyncScript -PathType Leaf)) {
            throw "Prompt Kit sync runtime is missing from the AgentSwitchboard checkout: $SourceSyncScript"
        }
        if (-not (Test-Path -LiteralPath $PowerShellExe -PathType Leaf)) {
            throw "Windows PowerShell was not found at $PowerShellExe"
        }
        foreach ($command in @('Register-ScheduledTask', 'New-ScheduledTaskAction', 'New-ScheduledTaskTrigger', 'New-ScheduledTaskSettingsSet', 'New-ScheduledTaskPrincipal')) {
            if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
                throw "Windows ScheduledTasks command is unavailable: $command"
            }
        }

        $null = New-Item -ItemType Directory -Path $RuntimeRoot -Force
        Copy-Item -LiteralPath $SourceSyncScript -Destination $RuntimeSyncScript -Force

        $escapedStateRoot = $StateRoot.Replace('"', '\"')
        $taskArguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode Poll -StateRoot "{1}"' -f $RuntimeSyncScript, $escapedStateRoot
        $taskAction = New-ScheduledTaskAction -Execute $PowerShellExe -Argument $taskArguments
        $taskTrigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
        $taskSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $taskPrincipal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $TaskName -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings -Principal $taskPrincipal -Force | Out-Null
        # Consent becomes effective only after the scheduled task definition exists. If
        # registration fails, the config remains disabled and no poll can pass its gate.
        Write-Config -Enabled $true -Minutes $IntervalMinutes -Retention $RetentionCount
        Get-StatusObject | ConvertTo-Json -Depth 6
    }

    'Disable' {
        $existing = Read-Config
        $minutes = if ($existing.PSObject.Properties.Name -contains 'intervalMinutes') { [int]$existing.intervalMinutes } else { $IntervalMinutes }
        $retention = if ($existing.PSObject.Properties.Name -contains 'retentionCount') { [int]$existing.retentionCount } else { $RetentionCount }

        # The runtime reads this toggle before any network command. Disable it first so
        # polling stops even if Task Scheduler removal is blocked by policy.
        Write-Config -Enabled $false -Minutes $minutes -Retention $retention
        $task = Get-TaskSafe
        if ($task) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        }
        Get-StatusObject | ConvertTo-Json -Depth 6
    }

    'Run' {
        $config = Read-Config
        if (-not [bool]$config.enabled) {
            throw 'Prompt Kit polling is disabled. Enable the feature before running a poll.'
        }
        $script = if (Test-Path -LiteralPath $RuntimeSyncScript -PathType Leaf) { $RuntimeSyncScript } else { $SourceSyncScript }
        & $PowerShellExe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $script -Mode Poll -StateRoot $StateRoot
        exit $LASTEXITCODE
    }

    'Open' {
        if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) {
            throw 'No published Prompt Kit website is available yet. Enable the feature and allow a successful poll first.'
        }
        $state = Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $websitePath = [string]$state.websitePath
        if ([string]::IsNullOrWhiteSpace($websitePath) -or -not (Test-Path -LiteralPath $websitePath -PathType Leaf)) {
            throw 'Prompt Kit state does not point to a readable published website.'
        }
        Start-Process -FilePath $websitePath
        Get-StatusObject | ConvertTo-Json -Depth 6
    }

    'Status' {
        Get-StatusObject | ConvertTo-Json -Depth 6
    }
}
