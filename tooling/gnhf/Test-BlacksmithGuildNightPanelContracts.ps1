[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-True {
    param([bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-PowerShellParses {
    param([Parameter(Mandatory = $true)][string]$Path)
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors) | Out-Null
    if (@($errors).Count -gt 0) {
        throw "$Path does not parse: $(@($errors | ForEach-Object Message) -join '; ')"
    }
}

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'The BlacksmithGuild night-panel contract test requires PowerShell 7.'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$installerPath = Join-Path $PSScriptRoot 'Install-BlacksmithGuildNightPanel.ps1'
$launcherPath = Join-Path $PSScriptRoot 'Start-BlacksmithGuildNightShift.ps1'
$controlPath = Join-Path $PSScriptRoot 'Start-AgentSwitchboard.ps1'
$templatePath = Join-Path $PSScriptRoot 'templates\wezterm-blacksmithguild-night.lua'
$cmdPath = Join-Path $repoRoot 'Install-BlacksmithGuildNightPanel.cmd'

foreach ($path in @($installerPath, $launcherPath, $controlPath, $templatePath, $cmdPath)) {
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Required night-panel file is missing: $path"
}
foreach ($path in @($installerPath, $launcherPath, $controlPath, $PSCommandPath)) {
    Assert-PowerShellParses -Path $path
}

$launcherText = Get-Content -LiteralPath $launcherPath -Raw
$templateText = Get-Content -LiteralPath $templatePath -Raw
$installerText = Get-Content -LiteralPath $installerPath -Raw
$cmdText = Get-Content -LiteralPath $cmdPath -Raw
$controlText = Get-Content -LiteralPath $controlPath -Raw

foreach ($required in @(
    "ValidateSet('Auto', 'Compile', 'Repair', 'Closeout')",
    "[string]`$Agent = 'deepseek'",
    "deepseek/deepseek-v4-pro",
    'gnhf-night-shift.contract.json',
    "queue.items | Where-Object { [string]`$_.state -eq 'ready' }",
    'WezTerm -> native Windows PowerShell 7 -> AgentSwitchboard -> GNHF',
    "PromptPath = `$promptPath",
    "MaxIterations = [int]`$stageRecord.maxIterations",
    "MaxTokens = [int]`$stageRecord.maxTokens"
)) {
    Assert-True ($launcherText.Contains($required)) "Night launcher is missing required contract text: $required"
}
Assert-True ($launcherText -notmatch '(?i)PushBranch|--push|wsl\.exe|tmux') 'Night launcher must not push automatically or route through WSL/tmux.'
Assert-True ($controlText -match 'ValidateSet\("opencode",\s*"deepseek"') 'AgentSwitchboard control launcher must expose the truthful DeepSeek route.'
Assert-True ($controlText.Contains('AGENT_SWITCHBOARD_MODEL_READY')) 'DeepSeek route must require the bounded spawnability marker.'

foreach ($required in @(
    "label = 'BlacksmithGuild — GNHF Night Shift'",
    "'pwsh.exe'",
    "'Start-BlacksmithGuildNightShift.ps1'",
    "'Auto'",
    "'deepseek'",
    'config.launch_menu'
)) {
    Assert-True ($templateText.Contains($required)) "WezTerm template is missing required contract text: $required"
}
Assert-True ($templateText -notmatch '(?i)wsl\.exe|tmux|--push') 'WezTerm panel must start native Windows PowerShell and must not automate push.'

foreach ($required in @(
    'Read-TextFilePreservingEncoding',
    'Write-TextFilePreservingEncoding',
    'BEGIN AgentSwitchboard BlacksmithGuild GNHF Night Panel',
    "'.wezterm.lua.{0}.bak'",
    "Copy-Item -LiteralPath `$sourceControlLauncher",
    "ValidateSet\\\(\\\"opencode\\\",\\s\\\*\\\"deepseek\\\""
)) {
    Assert-True ($installerText.Contains($required)) "Installer is missing required preservation or readiness text: $required"
}
Assert-True ($cmdText.Contains('Install-BlacksmithGuildNightPanel.ps1')) 'Root CMD must invoke the strict installer.'
Assert-True ($cmdText.Contains('-Apply')) 'Root CMD must explicitly select apply mode.'
Assert-True ($cmdText.Contains('pause')) 'Root CMD must keep the technician-visible window open.'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('agentswitchboard-tbg-panel-' + [Guid]::NewGuid().ToString('N'))
try {
    $fakeHome = Join-Path $tempRoot 'home'
    $installRoot = Join-Path $tempRoot 'fleet'
    $configPath = Join-Path $fakeHome '.wezterm.lua'
    New-Item -ItemType Directory -Path $fakeHome -Force | Out-Null

    $initialText = "local wezterm = require 'wezterm'`r`nlocal config = wezterm.config_builder()`r`nconfig.color_scheme = 'rose-pine'`r`nreturn config`r`n"
    $preamble = [byte[]]@(0xEF, 0xBB, 0xBF)
    $body = [Text.UTF8Encoding]::new($false).GetBytes($initialText)
    $bytes = [byte[]]::new($preamble.Length + $body.Length)
    [Array]::Copy($preamble, 0, $bytes, 0, $preamble.Length)
    [Array]::Copy($body, 0, $bytes, $preamble.Length, $body.Length)
    [IO.File]::WriteAllBytes($configPath, $bytes)

    & $installerPath -RepoPath (Join-Path $tempRoot 'BlacksmithGuild') -WezTermConfigPath $configPath -InstallRoot $installRoot -Apply

    $firstBytes = [IO.File]::ReadAllBytes($configPath)
    Assert-True ($firstBytes.Length -ge 3 -and $firstBytes[0] -eq 0xEF -and $firstBytes[1] -eq 0xBB -and $firstBytes[2] -eq 0xBF) 'Installer did not preserve the UTF-8 BOM.'
    $firstText = [Text.UTF8Encoding]::new($true).GetString($firstBytes, 3, $firstBytes.Length - 3)
    Assert-True ($firstText.Contains("config.color_scheme = 'rose-pine'")) 'Installer rewrote unrelated WezTerm configuration.'
    Assert-True ([regex]::Matches($firstText, 'BEGIN AgentSwitchboard BlacksmithGuild GNHF Night Panel').Count -eq 1) 'Installer must insert exactly one managed block.'
    Assert-True ($firstText -notmatch '(?<!\r)\n') 'Installer did not preserve CRLF line endings.'

    $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $installRoot 'panel-install\backups') -File -ErrorAction Stop)
    Assert-True ($backupFiles.Count -eq 1) 'Installer must create one backup before the first config mutation.'
    Assert-True (Test-Path -LiteralPath (Join-Path $installRoot 'Start-AgentSwitchboard.ps1') -PathType Leaf) 'Installed DeepSeek-aware control launcher is missing.'
    Assert-True (Test-Path -LiteralPath (Join-Path $installRoot 'Start-BlacksmithGuildNightShift.ps1') -PathType Leaf) 'Installed BlacksmithGuild night launcher is missing.'
    Assert-True (Test-Path -LiteralPath (Join-Path $fakeHome '.wezterm-blacksmithguild-night.lua') -PathType Leaf) 'Installed WezTerm include is missing.'

    & $installerPath -RepoPath (Join-Path $tempRoot 'BlacksmithGuild') -WezTermConfigPath $configPath -InstallRoot $installRoot -Apply
    $secondBytes = [IO.File]::ReadAllBytes($configPath)
    $secondText = [Text.UTF8Encoding]::new($true).GetString($secondBytes, 3, $secondBytes.Length - 3)
    Assert-True ([regex]::Matches($secondText, 'BEGIN AgentSwitchboard BlacksmithGuild GNHF Night Panel').Count -eq 1) 'Repeated installation duplicated the managed block.'
    $backupFilesAfterRepeat = @(Get-ChildItem -LiteralPath (Join-Path $installRoot 'panel-install\backups') -File -ErrorAction Stop)
    Assert-True ($backupFilesAfterRepeat.Count -eq 1) 'Repeated installation should not create a second backup when the managed block already exists.'
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host 'PASS: BlacksmithGuild WezTerm night panel preserves config, selects the repo-owned stage, and routes DeepSeek through native Windows AgentSwitchboard.' -ForegroundColor Green
