[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$detector = Join-Path $repoRoot 'tooling\profiles\windows\Get-AgentSwitchboardMachineProfile.ps1'
$fixtureRoot = Join-Path $repoRoot 'tooling\profiles\windows\harness\machine-profile\fixtures'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('agentswitchboard-machine-profile-' + [guid]::NewGuid().ToString('N'))
$originalOverride = $env:AGENT_SWITCHBOARD_REPO
try {
    Remove-Item Env:AGENT_SWITCHBOARD_REPO -ErrorAction SilentlyContinue
    $enterprise = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $detector -Mode Apply -Emit Json -ProbeFile (Join-Path $fixtureRoot 'enterprise-onedrive.fixture.json') -OutputRoot (Join-Path $tempRoot 'enterprise') | ConvertFrom-Json
    if ($enterprise.profileId -ne 'enterprise-managed-onedrive') { throw 'Enterprise fixture classification failed.' }
    if ($enterprise.repository.recommendedRoot -ne 'C:\Users\corp_user27\dev\AgentSwitchBoard-Live') { throw 'Enterprise repo-root policy failed.' }
    if (-not $enterprise.pathConventions.desktopRedirected) { throw 'Enterprise redirected Desktop was not detected.' }

    $local = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $detector -Mode Apply -Emit Json -ProbeFile (Join-Path $fixtureRoot 'local-windows.fixture.json') -OutputRoot (Join-Path $tempRoot 'local') | ConvertFrom-Json
    if ($local.profileId -ne 'local-windows') { throw 'Local fixture classification failed.' }
    if ($local.repository.recommendedRoot -ne 'C:\Users\newuser\dev\AgentSwitchBoard-Live') { throw 'Local repo-root policy failed.' }

    $env:AGENT_SWITCHBOARD_REPO = 'C:\Selected\Dev\AgentSwitchBoard-Live'
    $override = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $detector -Mode Detect -Emit Json -ProbeFile (Join-Path $fixtureRoot 'local-windows.fixture.json') | ConvertFrom-Json
    if ($override.repository.recommendedRoot -ne $env:AGENT_SWITCHBOARD_REPO) { throw 'Environment-selected new checkout root was not honored.' }
    if (-not ($override.reasons -contains 'AGENT_SWITCHBOARD_REPO selected the repository root before checkout discovery.')) { throw 'Environment override reason was not recorded.' }

    foreach ($name in @('machine-profile.json', 'machine-profile.env.cmd', 'machine-profile.env.ps1')) {
        if (-not (Test-Path -LiteralPath (Join-Path $tempRoot "enterprise\$name") -PathType Leaf)) { throw "Missing artifact: $name" }
    }
    Write-Host '[PASS] Machine-profile bootstrap harness passed.'
}
finally {
    if ($null -eq $originalOverride) {
        Remove-Item Env:AGENT_SWITCHBOARD_REPO -ErrorAction SilentlyContinue
    }
    else {
        $env:AGENT_SWITCHBOARD_REPO = $originalOverride
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
