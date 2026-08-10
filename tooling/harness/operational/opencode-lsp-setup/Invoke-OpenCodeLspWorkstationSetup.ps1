[CmdletBinding()]
param(
    [ValidateSet('Inspect','Configure','Verify')][string]$Mode = 'Inspect',
    [string]$RepoPath,
    [string]$ModelId = 'opencode/nemotron-3-ultra-free',
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

function Invoke-GitLines {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $lines = @(& git -C $RepoPath @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $($lines -join ' ')" }
    return $lines
}

if ($env:OS -ne 'Windows_NT') { throw 'WINDOWS_REQUIRED: workstation configuration is Windows-only.' }
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'POWERSHELL7_REQUIRED: use PowerShell 7.' }
if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    $root = @(& git rev-parse --show-toplevel 2>&1)
    if ($LASTEXITCODE -ne 0 -or $root.Count -eq 0) { throw 'REPOSITORY_NOT_RESOLVED: supply -RepoPath or run inside AgentSwitchboard.' }
    $RepoPath = ([string]$root[0]).Trim()
}
$RepoPath = (Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).Path
$origin = ([string](Invoke-GitLines @('remote','get-url','origin'))[0]).Trim()
if ($origin -notmatch 'EndeavorEverlasting[/:]AgentSwitchboard(?:\.git)?$') { throw "WRONG_REPOSITORY: $origin" }
$head = ([string](Invoke-GitLines @('rev-parse','HEAD'))[0]).Trim()
$branchLines = @(Invoke-GitLines @('branch','--show-current'))
$branch = if ($branchLines.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace([string]$branchLines[0])) { ([string]$branchLines[0]).Trim() } else { '<detached>' }
$dirty = @(Invoke-GitLines @('status','--porcelain=v1') | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })

$commands = @()
foreach ($name in @('opencode.cmd','opencode.exe','opencode')) {
    $candidate = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($candidate) { $commands += $candidate }
}
if ($commands.Count -eq 0) { throw 'OPENCODE_NOT_FOUND: no opencode command is available on PATH.' }
$openCode = [string]$commands[0].Source
$versionLines = @(& $openCode --version 2>&1)
if ($LASTEXITCODE -ne 0 -or $versionLines.Count -eq 0) { throw 'OPENCODE_VERSION_FAILED: unable to read OpenCode version.' }
$version = ([string]$versionLines[0]).Trim()
if ($version -match '^\s*2(?:\.|\b)') { throw "OPENCODE_V2_LSP_UNAVAILABLE: detected $version; current V2 documentation does not provide LSP runtime behavior." }

$base = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
$stateRoot = Join-Path $base 'AgentSwitchboard\opencode-lsp'
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $runId = '{0}-{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')), ([guid]::NewGuid().ToString('N').Substring(0,8))
    $OutputDirectory = Join-Path $stateRoot "runs\$runId"
}
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$overlayPath = Join-Path $stateRoot 'opencode-lsp.overlay.json'
$launcherPath = Join-Path $stateRoot 'Open-AgentSwitchboard-OpenCode-Lsp.cmd'
$receiptPath = Join-Path $OutputDirectory 'opencode-lsp-setup.json'
$reportPath = Join-Path $OutputDirectory 'opencode-lsp-operator-report.md'

$modelVisible = $false
$modelQueryStatus = 'not-run'
$modelLines = @()
try {
    $modelLines = @(& $openCode models opencode 2>&1)
    if ($LASTEXITCODE -eq 0) {
        $modelQueryStatus = 'pass'
        $modelVisible = @($modelLines | Where-Object { ([string]$_).Trim() -eq $ModelId }).Count -gt 0
    } else { $modelQueryStatus = "exit-$LASTEXITCODE" }
} catch { $modelQueryStatus = 'error' }

if ($Mode -eq 'Configure') {
    $null = New-Item -ItemType Directory -Path $stateRoot -Force
    [ordered]@{'$schema'='https://opencode.ai/config.json';lsp=$true} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $overlayPath -Encoding utf8NoBOM
    $launcher = @(
        '@echo off',
        'setlocal EnableExtensions DisableDelayedExpansion',
        ('set "OPENCODE_CONFIG={0}"' -f $overlayPath),
        ('cd /d "{0}"' -f $RepoPath),
        ('"{0}" -m "{1}" .' -f $openCode, $ModelId),
        'set "RESULT=%ERRORLEVEL%"',
        'endlocal & exit /b %RESULT%'
    )
    $launcher | Set-Content -LiteralPath $launcherPath -Encoding ascii
}

$overlayValid = $false
if (Test-Path -LiteralPath $overlayPath -PathType Leaf) {
    try {
        $overlay = Get-Content -LiteralPath $overlayPath -Raw | ConvertFrom-Json
        $overlayValid = ([bool]$overlay.lsp -eq $true) -and ([string]$overlay.'$schema' -eq 'https://opencode.ai/config.json')
    } catch { $overlayValid = $false }
}
$launcherExists = Test-Path -LiteralPath $launcherPath -PathType Leaf
if ($Mode -eq 'Verify' -and (-not $overlayValid -or -not $launcherExists)) { throw 'CONFIGURATION_INCOMPLETE: run Configure first.' }

$status = if ($Mode -eq 'Inspect') { 'inspected' } elseif ($overlayValid -and $launcherExists) { 'configured' } else { 'incomplete' }
$result = [ordered]@{
    schema='agentswitchboard.opencode-lsp-workstation-setup-receipt.v1'; status=$status; mode=$Mode
    repository='EndeavorEverlasting/AgentSwitchboard'; repoPath=$RepoPath; origin=$origin; branch=$branch; head=$head; dirty=($dirty.Count -gt 0)
    opencodeCommand=$openCode; opencodeVersion=$version; runtimeClass='stable-lsp-capable'
    overlayPath=$overlayPath; overlayValid=$overlayValid; launcherPath=$launcherPath; launcherExists=$launcherExists
    modelId=$ModelId; modelVisible=$modelVisible; modelQueryStatus=$modelQueryStatus
    privacyBoundary='Free trial models are launch-only and must not receive confidential, customer, credential, private-machine, or private-source data.'
    proofCeiling='Configuration proof only. Active LSP runtime requires opening a supported file and observing server/diagnostic behavior.'
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM
$working = @("OpenCode resolved: $openCode ($version)", "Repository identity: $origin @ $head")
if ($overlayValid) { $working += "Owned LSP overlay valid: $overlayPath" }
if ($launcherExists) { $working += "Owned launcher present: $launcherPath" }
$missing = @('Active LSP server/diagnostic behavior is not proven by configuration alone.')
if (-not $modelVisible) { $missing += "Requested model was not proven visible by 'opencode models opencode'; connect/refresh OpenCode if launch fails." }
$report = @('# OpenCode LSP Workstation Report','',"- Repository: ``EndeavorEverlasting/AgentSwitchboard``","- Branch: ``$branch``","- HEAD: ``$head``","- OpenCode: ``$openCode``","- Version: ``$version``","- Status: ``$status``","- Model: ``$ModelId``","- Model visible: ``$modelVisible``",'','## Working')
$report += @($working | ForEach-Object { '- ' + $_ })
$report += @('','## Broken','- none detected by this bounded setup pass','','## Missing / unproven')
$report += @($missing | ForEach-Object { '- ' + $_ })
$report += @('','## Privacy boundary','- Free trial endpoints must not receive confidential, customer, credential, private-machine, or private-source data.','','## Next action')
$next = if ($Mode -eq 'Inspect') { "pwsh -NoLogo -NoProfile -File `"$PSCommandPath`" -Mode Configure -RepoPath `"$RepoPath`"" } else { "& `"$launcherPath`"" }
$report += @('- Owner: Windows operator',"- Dependency: status=$status; exact HEAD remains $head",'```powershell',$next,'```',"Expected evidence: $receiptPath")
$report | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM

Write-Host "OPENCODE_LSP_SETUP_STATUS=$status"
Write-Host "REPO_HEAD=$head"
Write-Host "OPENCODE_VERSION=$version"
Write-Host "MODEL_VISIBLE=$modelVisible"
Write-Host "OVERLAY=$overlayPath"
Write-Host "LAUNCHER=$launcherPath"
Write-Host "RECEIPT=$receiptPath"
Write-Host "REPORT=$reportPath"
if ($status -eq 'incomplete') { exit 1 }
exit 0
