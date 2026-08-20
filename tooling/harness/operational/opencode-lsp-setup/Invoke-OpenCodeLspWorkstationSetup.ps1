[CmdletBinding()]
param(
    [ValidateSet('Inspect','Configure','Verify')][string]$Mode = 'Inspect',
    [string]$RepoPath,
    [string]$ModelId = 'opencode/nemotron-3-ultra-free',
    [string]$OutputDirectory,
    [string]$ConfigurationDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

function Stop-Setup {
    param([Parameter(Mandatory)][string]$Code, [Parameter(Mandatory)][string]$Message)
    throw ([InvalidOperationException]::new("$Code|$Message"))
}

function ConvertTo-PsLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Test-ExactLines {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Expected)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $actual = @((Get-Content -LiteralPath $Path -Encoding utf8) | ForEach-Object { [string]$_ })
    if ($actual.Count -ne $Expected.Count) { return $false }
    for ($i = 0; $i -lt $Expected.Count; $i++) {
        if ($actual[$i] -cne $Expected[$i]) { return $false }
    }
    return $true
}

$base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
$stateRoot = Join-Path $base 'AgentSwitchboard\opencode-lsp'
$outputDirectoryWasProvided = -not [string]::IsNullOrWhiteSpace($OutputDirectory)
$requestedConfigurationDirectory = $null
$preOwnedConfigureDirectory = $null
if ($outputDirectoryWasProvided) {
    $requestedConfigurationDirectory = [IO.Path]::GetFullPath($OutputDirectory)
    if ($Mode -eq 'Configure' -and (Test-Path -LiteralPath $requestedConfigurationDirectory)) {
        if (-not (Test-Path -LiteralPath $requestedConfigurationDirectory -PathType Container)) {
            $preOwnedConfigureDirectory = $requestedConfigurationDirectory
        }
        else {
            $existingEntries = @(Get-ChildItem -LiteralPath $requestedConfigurationDirectory -Force -ErrorAction Stop)
            if ($existingEntries.Count -gt 0) { $preOwnedConfigureDirectory = $requestedConfigurationDirectory }
        }
    }
}
if ($preOwnedConfigureDirectory) {
    $failureRunId = '{0}-{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')), ([guid]::NewGuid().ToString('N').Substring(0,8))
    $OutputDirectory = Join-Path $stateRoot "runs\$failureRunId"
}
elseif ($outputDirectoryWasProvided) {
    $OutputDirectory = $requestedConfigurationDirectory
}
else {
    $runId = '{0}-{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')), ([guid]::NewGuid().ToString('N').Substring(0,8))
    $OutputDirectory = Join-Path $stateRoot "runs\$runId"
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$receiptPath = Join-Path $OutputDirectory 'opencode-lsp-setup.json'
$reportPath = Join-Path $OutputDirectory 'opencode-lsp-operator-report.md'

$repoResolved = $false
$repository = 'EndeavorEverlasting/AgentSwitchboard'
$origin = $null
$branch = '<unresolved>'
$head = '<unresolved>'
$dirty = $null
$openCode = $null
$version = $null
$runtimeClass = 'unresolved'
$modelProvider = $null
$modelVisible = $false
$modelQueryStatus = 'not-run'
$configurationRoot = $null
$overlayPath = $null
$launcherScriptPath = $null
$launcherCmdPath = $null
$overlayValid = $false
$launcherScriptValid = $false
$launcherCmdValid = $false
$failureCode = $null
$failureMessage = $null
$nextOwner = 'Windows operator'
$nextDependency = 'bounded setup prerequisites remain satisfied'
$nextCommand = $null
$checkoutRecoveryRouterPath = Join-Path $PSScriptRoot 'Recover-AgentSwitchboardCheckout.ps1'

try {
    if ($preOwnedConfigureDirectory) { Stop-Setup 'CONFIGURATION_DIRECTORY_ALREADY_OWNED' 'Configure requires a new or empty output directory. Existing evidence was preserved and this failure receipt was written to a fresh run.' }
    if ($env:OS -ne 'Windows_NT') { Stop-Setup 'WINDOWS_REQUIRED' 'Workstation configuration is Windows-only.' }
    if ($PSVersionTable.PSVersion.Major -lt 7) { Stop-Setup 'POWERSHELL7_REQUIRED' 'Use PowerShell 7.' }

    if ([string]::IsNullOrWhiteSpace($RepoPath)) {
        $root = @(& git rev-parse --show-toplevel 2>&1)
        if ($LASTEXITCODE -ne 0 -or $root.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$root[0])) {
            Stop-Setup 'REPOSITORY_NOT_RESOLVED' 'Supply -RepoPath or run inside AgentSwitchboard.'
        }
        $RepoPath = ([string]$root[0]).Trim()
    }
    $RepoPath = (Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).Path

    function Invoke-GitLines {
        param([Parameter(Mandatory)][string[]]$Arguments)
        $lines = @(& git -C $RepoPath @Arguments 2>&1)
        if ($LASTEXITCODE -ne 0) { Stop-Setup 'GIT_COMMAND_FAILED' ('A bounded Git identity command failed: {0}' -f ($Arguments -join ' ')) }
        return $lines
    }

    $origin = ([string](Invoke-GitLines @('remote','get-url','origin'))[0]).Trim()
    $canonicalOriginPattern = '^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/|git://github\.com/)EndeavorEverlasting/AgentSwitchboard(?:\.git)?/?$'
    if ($origin -notmatch $canonicalOriginPattern) { Stop-Setup 'WRONG_REPOSITORY' 'The supplied checkout is not the exact GitHub repository EndeavorEverlasting/AgentSwitchboard.' }
    $repoResolved = $true
    $head = ([string](Invoke-GitLines @('rev-parse','HEAD'))[0]).Trim()
    $branchLines = @(Invoke-GitLines @('branch','--show-current'))
    if ($branchLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$branchLines[0])) { $branch = ([string]$branchLines[0]).Trim() } else { $branch = '<detached>' }
    $dirtyLines = @(Invoke-GitLines @('status','--porcelain=v1') | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    $dirty = $dirtyLines.Count -gt 0

    $commands = @()
    foreach ($name in @('opencode.cmd','opencode.exe','opencode')) {
        $candidate = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($candidate) { $commands += $candidate }
    }
    if ($commands.Count -eq 0) { Stop-Setup 'OPENCODE_NOT_FOUND' 'No OpenCode command is available on PATH.' }
    $openCode = [string]$commands[0].Source
    $versionLines = @(& $openCode --version 2>&1)
    if ($LASTEXITCODE -ne 0 -or $versionLines.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$versionLines[0])) { Stop-Setup 'OPENCODE_VERSION_FAILED' 'Unable to read the installed OpenCode version.' }
    $version = ([string]$versionLines[0]).Trim()
    if ($version -match '^\s*v?2(?:\.|\b)') { Stop-Setup 'OPENCODE_V2_LSP_UNAVAILABLE' 'Detected OpenCode V2; current upstream V2 documentation does not provide LSP runtime behavior.' }
    $runtimeClass = 'stable-lsp-capable'

    $modelSeparator = $ModelId.IndexOf('/')
    if ($modelSeparator -le 0 -or $modelSeparator -ge ($ModelId.Length - 1)) { Stop-Setup 'MODEL_ID_INVALID' 'ModelId must use provider/model format.' }
    $modelProvider = $ModelId.Substring(0, $modelSeparator)
    $modelLines = @(& $openCode models $modelProvider 2>&1)
    if ($LASTEXITCODE -eq 0) {
        $modelQueryStatus = 'pass'
        $modelVisible = @($modelLines | Where-Object { ([string]$_).Trim() -eq $ModelId }).Count -gt 0
    }
    else {
        $modelQueryStatus = 'failed'
    }

    if ($Mode -eq 'Configure' -and -not $modelVisible) {
        Stop-Setup 'MODEL_NOT_VISIBLE' 'The requested OpenCode model was not proven visible by the bounded provider-specific model-list query.'
    }

    if ($Mode -eq 'Verify') {
        if ([string]::IsNullOrWhiteSpace($ConfigurationDirectory)) { Stop-Setup 'VERIFY_CONFIGURATION_DIRECTORY_REQUIRED' 'Verify requires -ConfigurationDirectory naming the immutable Configure run.' }
        $configurationRoot = (Resolve-Path -LiteralPath $ConfigurationDirectory -ErrorAction Stop).Path
    }
    else {
        $configurationRoot = $OutputDirectory
    }

    $overlayPath = Join-Path $configurationRoot 'opencode-lsp.overlay.json'
    $launcherScriptPath = Join-Path $configurationRoot 'Open-AgentSwitchboard-OpenCode-Lsp.ps1'
    $launcherCmdPath = Join-Path $configurationRoot 'Open-AgentSwitchboard-OpenCode-Lsp.cmd'

    $repoLiteral = ConvertTo-PsLiteral $RepoPath
    $openCodeLiteral = ConvertTo-PsLiteral $openCode
    $overlayLiteral = ConvertTo-PsLiteral $overlayPath
    $modelLiteral = ConvertTo-PsLiteral $ModelId

    $expectedLauncherScript = @(
        '[CmdletBinding()]',
        'param()',
        'Set-StrictMode -Version Latest',
        '$ErrorActionPreference = ''Stop''',
        ('if ([string]::IsNullOrWhiteSpace($env:OPENCODE_CONFIG)) { $env:OPENCODE_CONFIG = {0} }' -f $overlayLiteral),
        '$effective = @{}',
        'if (-not [string]::IsNullOrWhiteSpace($env:OPENCODE_CONFIG_CONTENT)) {',
        '    try { $incoming = $env:OPENCODE_CONFIG_CONTENT | ConvertFrom-Json -AsHashtable }',
        '    catch { throw ''Inherited OPENCODE_CONFIG_CONTENT is not valid JSON; launch stopped without changing it.'' }',
        '    foreach ($key in $incoming.Keys) { $effective[$key] = $incoming[$key] }',
        '}',
        '$effective[''lsp''] = $true',
        '$env:OPENCODE_CONFIG_CONTENT = ($effective | ConvertTo-Json -Depth 100 -Compress)',
        ('Set-Location -LiteralPath {0}' -f $repoLiteral),
        ('& {0} --model {1} ''.''' -f $openCodeLiteral, $modelLiteral),
        '$result = $LASTEXITCODE',
        'if ($result -ne 0) { throw "OpenCode exited with code $result" }'
    )
    $expectedLauncherCmd = @(
        '@echo off',
        'setlocal EnableExtensions DisableDelayedExpansion',
        'where pwsh.exe >nul 2>nul',
        'if errorlevel 1 (echo [FAIL] PowerShell 7 is required.& endlocal & exit /b 127)',
        'pwsh.exe -NoLogo -NoProfile -File "%~dp0Open-AgentSwitchboard-OpenCode-Lsp.ps1"',
        'set "RESULT=%ERRORLEVEL%"',
        'endlocal & exit /b %RESULT%'
    )

    if ($Mode -eq 'Configure') {
        [ordered]@{'$schema'='https://opencode.ai/config.json';lsp=$true} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $overlayPath -Encoding utf8NoBOM
        $expectedLauncherScript | Set-Content -LiteralPath $launcherScriptPath -Encoding utf8NoBOM
        $expectedLauncherCmd | Set-Content -LiteralPath $launcherCmdPath -Encoding ascii
    }

    if (Test-Path -LiteralPath $overlayPath -PathType Leaf) {
        try {
            $overlay = Get-Content -LiteralPath $overlayPath -Raw | ConvertFrom-Json
            $overlayValid = ([bool]$overlay.lsp -eq $true) -and ([string]$overlay.'$schema' -eq 'https://opencode.ai/config.json')
        }
        catch { $overlayValid = $false }
    }
    $launcherScriptValid = Test-ExactLines -Path $launcherScriptPath -Expected $expectedLauncherScript
    $launcherCmdValid = Test-ExactLines -Path $launcherCmdPath -Expected $expectedLauncherCmd

    if ($Mode -in @('Configure','Verify')) {
        if (-not $overlayValid) { Stop-Setup 'OVERLAY_INVALID' 'The immutable LSP overlay is missing or does not exactly enable the OpenCode schema/lsp contract.' }
        if (-not $launcherScriptValid -or -not $launcherCmdValid) { Stop-Setup 'LAUNCHER_MISMATCH' 'The launcher does not exactly match the requested repository, executable, overlay, and model.' }
        if (-not $modelVisible) { Stop-Setup 'MODEL_NOT_VISIBLE' 'The requested model is not visible to the current OpenCode provider view.' }
    }
}
catch {
    $raw = [string]$_.Exception.Message
    if ($raw -match '^([A-Z0-9_]+)\|(.*)$') {
        $failureCode = $Matches[1]
        $failureMessage = $Matches[2]
    }
    else {
        $failureCode = 'UNEXPECTED_SETUP_FAILURE'
        $failureMessage = 'The bounded setup failed before completion; inspect the local console error and preserve this receipt.'
    }
}

if ($failureCode) {
    $status = 'failed'
    $nextOwner = switch ($failureCode) {
        'OPENCODE_NOT_FOUND' { 'OpenCode installation/runtime owner' }
        'OPENCODE_V2_LSP_UNAVAILABLE' { 'OpenCode upstream/runtime owner' }
        'MODEL_NOT_VISIBLE' { 'OpenCode provider/model connection owner' }
        'WRONG_REPOSITORY' { 'repository operator' }
        default { 'OpenCode LSP harness operator' }
    }
    $nextDependency = 'repair the named failure boundary without changing existing OpenCode config or weakening harness gates'
    $nextCommand = if ($failureCode -eq 'WRONG_REPOSITORY') {
        '& ' + (ConvertTo-PsLiteral $checkoutRecoveryRouterPath) + ' -PreferredPath ' + (ConvertTo-PsLiteral $RepoPath)
    }
    elseif ($repoResolved) {
        "pwsh -NoLogo -NoProfile -File `"$PSCommandPath`" -Mode Inspect -RepoPath `"$RepoPath`""
    }
    else {
        'git rev-parse --show-toplevel'
    }
}
else {
    $status = if ($Mode -eq 'Inspect') { 'inspected' } elseif ($Mode -eq 'Configure') { 'configured' } else { 'verified' }
    $nextDependency = if ($Mode -eq 'Inspect') { 'status=inspected and the requested model is visible before Configure' } else { 'configuration artifacts remain exact and public/non-confidential content only is used with free trial models' }
    $nextCommand = if ($Mode -eq 'Inspect') {
        "pwsh -NoLogo -NoProfile -File `"$PSCommandPath`" -Mode Configure -RepoPath `"$RepoPath`" -ModelId `"$ModelId`""
    }
    else {
        "& `"$launcherCmdPath`""
    }
}

$result = [ordered]@{
    schema = 'agentswitchboard.opencode-lsp-workstation-setup-receipt.v2'
    status = $status
    mode = $Mode
    failureCode = $failureCode
    failureMessage = $failureMessage
    repository = $repository
    repoPath = if ($repoResolved) { $RepoPath } else { $null }
    branch = $branch
    head = $head
    dirty = $dirty
    opencodeCommand = $openCode
    opencodeVersion = $version
    runtimeClass = $runtimeClass
    requestedConfigurationDirectory = $requestedConfigurationDirectory
    configurationDirectory = $configurationRoot
    overlayPath = $overlayPath
    overlayValid = $overlayValid
    launcherScriptPath = $launcherScriptPath
    launcherScriptValid = $launcherScriptValid
    launcherPath = $launcherCmdPath
    launcherValid = $launcherCmdValid
    modelId = $ModelId
    modelProvider = $modelProvider
    modelVisible = $modelVisible
    modelQueryStatus = $modelQueryStatus
    inheritedInlineConfigContentsPersisted = $false
    privacyBoundary = 'Free trial models are launch-only and must not receive confidential, customer, credential, private-machine, or private-source data.'
    proofCeiling = 'Configuration proof only. Active LSP runtime requires opening a supported file and observing server/diagnostic behavior.'
    nextOwner = $nextOwner
    nextDependency = $nextDependency
    nextCommand = $nextCommand
}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM

$working = @()
if ($repoResolved) { $working += "Repository identity resolved at HEAD $head." }
if ($openCode) { $working += "OpenCode command/version resolved: $openCode ($version)." }
if ($overlayValid) { $working += "Immutable LSP overlay validated: $overlayPath" }
if ($launcherScriptValid -and $launcherCmdValid) { $working += "Immutable launcher pair validated for the requested repo/model: $launcherCmdPath" }
$broken = if ($failureCode) { @("$failureCode - $failureMessage") } else { @('none detected by this bounded setup pass') }
$unproven = @('Active LSP server/diagnostic behavior is not proven by configuration alone.')
if (-not $modelVisible) { $unproven += 'Requested model visibility is not proven.' }

$report = @(
    '# OpenCode LSP Workstation Report','',
    "- Repository: ``$repository``",
    "- Branch: ``$branch``",
    "- HEAD: ``$head``",
    "- OpenCode version: ``$version``",
    "- Status: ``$status``",
    "- Failure code: ``$failureCode``",
    "- Model: ``$ModelId``",
    "- Model provider: ``$modelProvider``",
    "- Model visible: ``$modelVisible``",'',
    '## Working'
)
$report += @($working | ForEach-Object { '- ' + $_ })
$report += @('', '## Broken')
$report += @($broken | ForEach-Object { '- ' + $_ })
$report += @('', '## Missing / unproven')
$report += @($unproven | ForEach-Object { '- ' + $_ })
$report += @('', '## Privacy boundary', '- Free trial endpoints must not receive confidential, customer, credential, private-machine, or private-source data.', '- Inherited OPENCODE_CONFIG_CONTENT is merged in memory at launch and is never copied into setup artifacts.', '', '## Proof ceiling', [string]$result.proofCeiling, '', '## Next action', "- Owner: ``$nextOwner``", "- Dependency: ``$nextDependency``", '```powershell', $nextCommand, '```', "Expected evidence: ``$receiptPath``")
$report | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM

Write-Host "OPENCODE_LSP_SETUP_STATUS=$status"
Write-Host "FAILURE_CODE=$failureCode"
Write-Host "FAILURE_MESSAGE=$failureMessage"
Write-Host "REPO_HEAD=$head"
Write-Host "OPENCODE_VERSION=$version"
Write-Host "MODEL_PROVIDER=$modelProvider"
Write-Host "MODEL_VISIBLE=$modelVisible"
Write-Host "CONFIGURATION_DIRECTORY=$configurationRoot"
Write-Host "OVERLAY=$overlayPath"
Write-Host "LAUNCHER=$launcherCmdPath"
Write-Host "RECEIPT=$receiptPath"
Write-Host "REPORT=$reportPath"
Write-Host "NEXT_COMMAND=$nextCommand"
if ($failureCode) { exit 1 }
exit 0
