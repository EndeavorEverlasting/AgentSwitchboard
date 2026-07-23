[CmdletBinding()]
param(
    [string]$StageId = 'P01',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host 'Running P01-Network reachability checks...' -ForegroundColor Yellow

function Get-CurlFailureClassification {
    param([int]$ExitCode, [string]$Text)

    switch ($ExitCode) {
        5 { return 'proxy' }
        6 { return 'dns' }
        7 { return 'connection' }
        22 { return 'http' }
        28 { return 'timeout' }
        35 { return 'tls' }
        56 { return 'connection' }
        60 { return 'tls' }
    }
    if ($Text -match '(?i)proxy') { return 'proxy' }
    if ($Text -match '(?i)(certificate|ssl|tls)') { return 'tls' }
    if ($Text -match '(?i)(resolve host|name resolution|dns)') { return 'dns' }
    if ($Text -match '(?i)(401|403|authentication|unauthorized|forbidden)') { return 'authentication' }
    return 'unknown-network-failure'
}

function Invoke-CurlProbe {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Url
    )

    $output = (& curl.exe -fsSL --max-time 20 -o NUL $Url 2>&1 | Out-String).Trim()
    $exitCode = $LASTEXITCODE
    $classification = if ($exitCode -eq 0) { 'reachable' } else { Get-CurlFailureClassification -ExitCode $exitCode -Text $output }
    return [pscustomobject]@{
        name = $Name
        transport = 'https'
        target = $Url
        reachable = ($exitCode -eq 0)
        exitCode = $exitCode
        classification = $classification
        detail = $output
    }
}

$results = [System.Collections.Generic.List[object]]::new()
$allPassed = $true

# Prove Git access to the actual repository, not merely github.com.
$gitOutput = (& git.exe ls-remote https://github.com/EndeavorEverlasting/AgentSwitchboard.git HEAD 2>&1 | Out-String).Trim()
$gitExit = $LASTEXITCODE
[void]$results.Add([pscustomobject]@{
    name = 'AgentSwitchboard repository'
    transport = 'git-https'
    target = 'https://github.com/EndeavorEverlasting/AgentSwitchboard.git'
    reachable = ($gitExit -eq 0)
    exitCode = $gitExit
    classification = if ($gitExit -eq 0) { 'reachable' } elseif ($gitOutput -match '(?i)(certificate|ssl|tls)') { 'tls' } elseif ($gitOutput -match '(?i)(resolve|could not resolve)') { 'dns' } elseif ($gitOutput -match '(?i)(authentication|403|401)') { 'authentication' } else { 'source-unavailable' }
    detail = $gitOutput
})
if ($gitExit -ne 0) { $allPassed = $false }

$branch = (& git.exe -C $RepoRoot symbolic-ref --quiet --short HEAD 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) {
    throw 'P01 requires an attached repository branch so the exact bootstrap source can be probed.'
}

$httpProbes = @(
    @{ Name = 'Technician parent bootstrap'; Url = "https://raw.githubusercontent.com/EndeavorEverlasting/AgentSwitchboard/$branch/Pull-Repo-And-Setup-AgentSwitchboard.cmd" },
    @{ Name = 'AGY installer'; Url = 'https://antigravity.google/cli/install.sh' },
    @{ Name = 'OpenCode installer'; Url = 'https://opencode.ai/install' }
)

foreach ($probe in $httpProbes) {
    $result = Invoke-CurlProbe -Name $probe.Name -Url $probe.Url
    [void]$results.Add($result)
    if (-not $result.reachable) { $allPassed = $false }
}

# WinGet is network-required only when WezTerm is not already resolvable.
$wezTerm = Get-Command wezterm.exe -ErrorAction SilentlyContinue
if (-not $wezTerm) {
    foreach ($candidate in @(
        (Join-Path $env:ProgramFiles 'WezTerm\wezterm.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\WezTerm\wezterm.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\wezterm.exe')
    )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $wezTerm = Get-Item -LiteralPath $candidate
            break
        }
    }
}

if (-not $wezTerm) {
    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        [void]$results.Add([pscustomobject]@{
            name = 'WinGet WezTerm source'
            transport = 'winget'
            target = 'wez.wezterm'
            reachable = $false
            exitCode = 127
            classification = 'source-unavailable'
            detail = 'WezTerm is missing and winget.exe is unavailable.'
        })
        $allPassed = $false
    } else {
        $wingetOutput = (& $winget.Source show --id wez.wezterm --exact --source winget --accept-source-agreements 2>&1 | Out-String).Trim()
        $wingetExit = $LASTEXITCODE
        [void]$results.Add([pscustomobject]@{
            name = 'WinGet WezTerm source'
            transport = 'winget'
            target = 'wez.wezterm'
            reachable = ($wingetExit -eq 0)
            exitCode = $wingetExit
            classification = if ($wingetExit -eq 0) { 'reachable' } elseif ($wingetOutput -match '(?i)(certificate|ssl|tls)') { 'tls' } elseif ($wingetOutput -match '(?i)(proxy)') { 'proxy' } else { 'source-unavailable' }
            detail = $wingetOutput
        })
        if ($wingetExit -ne 0) { $allPassed = $false }
    }
} else {
    [void]$results.Add([pscustomobject]@{
        name = 'WinGet WezTerm source'
        transport = 'winget'
        target = 'wez.wezterm'
        reachable = $true
        exitCode = 0
        classification = 'not-required-existing-wezterm'
        detail = "WezTerm already resolved at $($wezTerm.FullName)."
    })
}

$networkFile = Join-Path $StageDir 'network-summary.json'
$results | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $networkFile -Encoding utf8NoBOM

foreach ($result in $results) {
    $color = if ($result.reachable) { 'Green' } else { 'Red' }
    Write-Host ("{0}: {1} [{2}]" -f $result.name, $(if ($result.reachable) { 'PASS' } else { 'FAIL' }), $result.classification) -ForegroundColor $color
}

if (-not $allPassed) {
    $failures = @($results | Where-Object { -not $_.reachable } | ForEach-Object { "$($_.name)=$($_.classification)" })
    throw "Required technician network sources failed: $($failures -join '; '). Evidence: $networkFile"
}

Write-Host 'P01-Network reachability passed.' -ForegroundColor Green
return 0
