[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('desktop-workstation', 'personal-windows-laptop')]
    [string]$EnvironmentRoleId,

    [ValidateSet('Inspect', 'Apply')]
    [string]$Mode = 'Inspect',

    [ValidateSet('code-now', 'engineering-full')]
    [string]$Profile = 'engineering-full',

    [string]$RepoRoot,

    [string]$OutputRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Personal workstation provisioning is supported only on Windows.' }

if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$contractPath = Join-Path $RepoRoot 'tooling/profiles/windows/harness/machine-profile/personal-workstation-bootstrap.v1.json'
$rolesPath = Join-Path $RepoRoot 'tooling/profiles/windows/harness/machine-profile/environment-role.registry.json'
$contract = Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8 | ConvertFrom-Json
$roleRegistry = Get-Content -LiteralPath $rolesPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ($contract.schema -ne 'agentswitchboard.personal-workstation-bootstrap.v1' -or
    $EnvironmentRoleId -notin @($contract.roles) -or
    $EnvironmentRoleId -notin @($roleRegistry.roles | ForEach-Object { $_.roleId })) {
    throw 'Refusing to provision a non-personal Windows role or unrecognized bootstrap contract.'
}

if (-not $OutputRoot) {
    $OutputRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard/personal-workstation-bootstrap/runs'
}
$runId = '{0}-{1}' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'), [Guid]::NewGuid().ToString('N').Substring(0, 8)
$runDir = Join-Path $OutputRoot $runId
$null = New-Item -ItemType Directory -Path $runDir -Force
$reportPath = Join-Path $runDir 'provision-summary.json'
$steps = [System.Collections.Generic.List[object]]::new()
$receipt = [ordered]@{
    schema = 'agentswitchboard.personal-workstation-provision-result.v1'
    runId = $runId
    roleId = $EnvironmentRoleId
    profile = $Profile
    mode = $Mode
    state = 'running'
    startedAtUtc = [DateTime]::UtcNow.ToString('o')
    completedAtUtc = $null
    steps = $steps
    nextAction = $null
    sourceCheckout = $RepoRoot
    proofCeiling = 'Installer exit and local version observations only; login, provider access, first repository task, optional SDKs, and crew-runtime certification remain separate gates.'
    tracked = $false
}
function Add-Stage {
    param([string]$Name, [string]$Status, [string]$Detail)
    [void]$steps.Add([pscustomobject]@{ name=$Name; status=$Status; detail=$Detail; utc=[DateTime]::UtcNow.ToString('o') })
    Write-Host ('[{0}] {1}: {2}' -f $Status.ToUpperInvariant(), $Name, $Detail)
}
function Refresh-ProcessPath {
    $extra = @((Join-Path $env:APPDATA 'npm'), (Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Links'))
    $parts = @($env:Path, [Environment]::GetEnvironmentVariable('Path','Machine'),
        [Environment]::GetEnvironmentVariable('Path','User')) + $extra
    $env:Path = (($parts | Where-Object { $_ } | ForEach-Object { $_ -split ';' } |
        Where-Object { $_ } | Select-Object -Unique) -join ';')
}
function Find-Exe {
    param([string]$Name)
    Refresh-ProcessPath
    return Get-Command -Name $Name -ErrorAction SilentlyContinue | Select-Object -First 1
}
function Get-ObservedVersion {
    param([string]$Command, [string[]]$Arguments)
    $resolved = Find-Exe $Command
    if (-not $resolved) { return $null }
    try {
        $out = @(& $resolved.Source @Arguments 2>$null)
        if ($LASTEXITCODE -ne 0 -or $out.Count -eq 0) { return $null }
        return ($out | Select-Object -First 1).ToString().Trim()
    } catch { return $null }
}
function Assert-Checkout {
    $origin = @(& git.exe -C $RepoRoot remote get-url origin 2>$null)
    if ($LASTEXITCODE -ne 0 -or $origin.Count -eq 0 -or
        $origin[0].Trim() -notin @('https://github.com/EndeavorEverlasting/AgentSwitchboard.git',
                                  'https://github.com/EndeavorEverlasting/AgentSwitchboard',
                                  'git@github.com:EndeavorEverlasting/AgentSwitchboard.git')) {
        throw 'Bootstrap requires a verified AgentSwitchboard checkout. No attempt to replace or overwrite it was made.'
    }
    Add-Stage 'checkout-origin' 'observed' 'Canonical Git origin matched; checkout not modified.'
}
function Ensure-Foundation {
    $winget = Find-Exe 'winget.exe'
    foreach ($component in @($contract.stages | Where-Object id -eq 'windows-foundation' | Select-Object -ExpandProperty components)) {
        $commandName = [string]$component.command
        if ($commandName -eq 'pwsh') { $commandName = 'pwsh.exe' }
        elseif ($commandName -eq 'git') { $commandName = 'git.exe' }
        elseif ($commandName -eq 'node') { $commandName = 'node.exe' }
        elseif ($commandName -eq 'gh') { $commandName = 'gh.exe' }
        $version = Get-ObservedVersion $commandName @('--version')
        $needsRepair = -not $version
        if ($component.id -eq 'node-lts' -and $version) {
            if ($version -notmatch '^v?(\d+)\.') { $needsRepair = $true }
            elseif ([int]$Matches[1] -lt [int]$component.minimumMajor) { $needsRepair = $true }
        }
        if (-not $needsRepair) {
            Add-Stage ([string]$component.id) 'observed' "Command version: $version"
            continue
        }
        if (-not $winget) { throw "WinGet is unavailable; cannot install $($component.wingetId)." }
        $packageId = [string]$component.wingetId
        if ($packageId -notin @('Microsoft.PowerShell','Git.Git','OpenJS.NodeJS.LTS','GitHub.cli')) {
            throw "Package not on approved foundation allowlist: $packageId"
        }
        Add-Stage ([string]$component.id) 'installing' "Approved WinGet package: $packageId"
        & $winget.Source install --id $packageId --exact --source winget --accept-source-agreements --accept-package-agreements
        if ($LASTEXITCODE -ne 0) {
            throw "WinGet failed for $packageId (exit $LASTEXITCODE). No subsequent stages executed."
        }
        $after = Get-ObservedVersion $commandName @('--version')
        if (-not $after) {
            throw "Installed $packageId but command is not yet on PATH. Close/reopen PowerShell and rerun this same command."
        }
        if ($component.id -eq 'node-lts') {
            if ($after -notmatch '^v?(\d+)\.' -or [int]$Matches[1] -lt [int]$component.minimumMajor) {
                throw "Node.js still does not meet the minimum required major version: $after"
            }
        }
        Add-Stage ([string]$component.id) 'observed' "Post-install command version: $after"
    }
}
function Ensure-NativeAgents {
    $nodeVersion = Get-ObservedVersion 'node.exe' @('--version')
    if (-not $nodeVersion -or $nodeVersion -notmatch '^v?(\d+)\.' -or [int]$Matches[1] -lt 22) {
        throw "Node >= 22 required for native Codex/Auggie stage; observed: $nodeVersion"
    }
    $npm = Find-Exe 'npm.cmd'
    if (-not $npm) { throw 'npm.cmd not available after Node installation. Open a fresh shell, then resume.' }
    foreach ($component in @($contract.stages | Where-Object id -eq 'native-agents' | Select-Object -ExpandProperty components)) {
        if ($component.id -notin @('codex','auggie')) { continue }
        $cli = "$($component.command).cmd"
        $version = Get-ObservedVersion $cli @('--version')
        if ($version) {
            Add-Stage ([string]$component.id) 'observed' "Command version: $version"
            continue
        }
        $package = [string]$component.npmPackage
        if ($package -notin @('@openai/codex','@augmentcode/auggie')) { throw "Disallowed npm package: $package" }
        Add-Stage ([string]$component.id) 'installing' "Approved npm package: $package"
        & $npm.Source install -g $package
        if ($LASTEXITCODE -ne 0) { throw "npm global install failed for $package (exit $LASTEXITCODE)." }
        $after = Get-ObservedVersion $cli @('--version')
        if (-not $after) { throw "$package installed but CLI not resolved. Open a fresh shell and resume." }
        Add-Stage ([string]$component.id) 'observed' "Post-install command version: $after"
    }
    Add-Stage 'native-provider-auth' 'operator-required' 'Sign in to Codex and Auggie interactively; no credential collection or login automation.'
}
function Ensure-CanonicalFleet {
    $pwsh = Find-Exe 'pwsh.exe'
    if (-not $pwsh) { throw 'PowerShell 7 is required for canonical fleet repair. Resume in a fresh shell.' }
    $repair = Join-Path $RepoRoot 'Repair-Technician-WSL-Ubuntu.cmd'
    $ready = Join-Path $RepoRoot 'Technician-AgentSwitchboard-Ready.cmd'
    if (-not (Test-Path -LiteralPath $repair -PathType Leaf) -or
        -not (Test-Path -LiteralPath $ready -PathType Leaf)) {
        throw 'Tracked WSL repair or technician-ready entrypoint is missing.'
    }
    $wsl = Find-Exe 'wsl.exe'
    $ubuntuInstalled = $false
    if ($wsl) {
        $existing = @(& $wsl.Source --list --quiet 2>$null)
        if ($LASTEXITCODE -eq 0 -and (($existing -join ' ') -replace ([char]0), '') -match '(?i)Ubuntu') { $ubuntuInstalled = $true }
    }
    if (-not $ubuntuInstalled) {
        Add-Stage 'wsl-ubuntu' 'installing' 'Delegating to tracked Repair-Technician-WSL-Ubuntu.cmd'
        $savedNoPause = $env:AGENT_SWITCHBOARD_NO_PAUSE
        $env:AGENT_SWITCHBOARD_NO_PAUSE = '1'
        try {
            & $repair
            $result = $LASTEXITCODE
        } finally {
            $env:AGENT_SWITCHBOARD_NO_PAUSE = $savedNoPause
        }
        if ($result -eq 3010) { throw 'WSL repair requires a reboot. Restart Windows, finish any Ubuntu first-user setup, and rerun the same bootstrap command.' }
        if ($result -ne 0) { throw "Repository WSL repair failed with exit $result; inspect its own local receipt." }
        Add-Stage 'wsl-ubuntu' 'observed' 'Repository repair exited zero; Ubuntu initialization will be checked by technician-ready.'
    } else { Add-Stage 'wsl-ubuntu' 'observed' 'Ubuntu distro enumerated; technician-ready will validate initialization.' }

    Add-Stage 'agentswitchboard-fleet' 'running' 'Delegating to canonical technician-ready setup'
    $saved = $env:AGENT_SWITCHBOARD_NO_PAUSE
    $env:AGENT_SWITCHBOARD_NO_PAUSE = '1'
    try {
        & $ready setup $RepoRoot
        $result = $LASTEXITCODE
    } finally {
        $env:AGENT_SWITCHBOARD_NO_PAUSE = $saved
    }
    if ($result -ne 0) { throw "Technician-ready setup failed ($result). Inspect its own receipt; rerun after correcting that prerequisite." }
    $statePath = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard/GnhfFleet/state.json'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw 'Fleet setup exited zero but canonical state.json is absent.' }
    Add-Stage 'agentswitchboard-fleet' 'observed' 'Canonical technician setup returned zero and fleet state exists. Provider auth and crew proof remain separate.'
}
try {
    $inspector = Join-Path $RepoRoot 'tooling/profiles/windows/Get-PersonalWorkstationBootstrapStatus.ps1'
    if ($Mode -eq 'Inspect') {
        & $inspector -EnvironmentRoleId $EnvironmentRoleId -OutputRoot $runDir
        # A PowerShell function/script need not set LASTEXITCODE. Exceptions propagate directly.
        Add-Stage 'preflight' 'observed' 'Read-only PATH discovery produced a machine-local report.'
        $receipt.state = 'inspected-only'
        $receipt.nextAction = "Run this script with -Mode Apply -Profile $Profile if you authorize tool installation."
    } else {
        if (-not (Find-Exe 'git.exe')) { throw 'Git is missing. Install Git.Git with WinGet, reopen PowerShell, and rerun the verified checkout script.' }
        Assert-Checkout
        Ensure-Foundation
        Ensure-NativeAgents
        if ($Profile -eq 'engineering-full') {
            Ensure-CanonicalFleet
            Add-Stage 'project-sdks' 'operator-required' 'Select project-required Python/uv, Android, containers and editor dependencies; do not install all heavyweight SDKs blindly.'
            Add-Stage 'security-drivers' 'operator-required' 'Verify activation, admin status, Windows Updates, chipset/GPU drivers and backups separately.'
        }
        Add-Stage 'first-repository-task' 'operator-required' 'Authenticate selected agents and perform one bounded read-only repository orientation.'
        $receipt.state = 'installed-awaiting-operator-gates'
        $receipt.nextAction = 'Complete provider logins, repo smoke, and any project-specific SDK/Windows health checks. Do not label this full readiness yet.'
    }
} catch {
    Add-Stage 'provisioning' 'blocked' $_.Exception.Message
    $receipt.state = 'blocked'
    $receipt.nextAction = $_.Exception.Message
} finally {
    $receipt.completedAtUtc = [DateTime]::UtcNow.ToString('o')
    $receipt | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Host "State: $($receipt.state)"
    Write-Host "Receipt: $reportPath"
    Write-Host "Next: $($receipt.nextAction)"
}
if ($receipt.state -eq 'blocked') { exit 1 }
exit 0
