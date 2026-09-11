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
    if ($enterprise.pathRoles.developmentCheckout -ne 'C:\Users\corp_user27\dev\AgentSwitchBoard-Live') { throw 'Enterprise pathRoles.developmentCheckout missing or wrong.' }
    if ($enterprise.pathRoles.pathRelation -ne 'same-path') { throw 'pathRoles.pathRelation must be same-path for technician Windows profile.' }
    if ($enterprise.pathRoles.openCodeEntrypoint -ne 'Bootstrap-OpenCode-SystemWide.cmd') { throw 'pathRoles.openCodeEntrypoint drifted.' }

    $local = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $detector -Mode Apply -Emit Json -ProbeFile (Join-Path $fixtureRoot 'local-windows.fixture.json') -OutputRoot (Join-Path $tempRoot 'local') | ConvertFrom-Json
    if ($local.profileId -ne 'local-windows') { throw 'Local fixture classification failed.' }
    if ($local.repository.recommendedRoot -ne 'C:\Users\newuser\dev\AgentSwitchBoard-Live') { throw 'Local repo-root policy failed.' }
    if ($local.pathRoles.stableDefaultDevelopmentCheckout -ne 'C:\Users\newuser\dev\AgentSwitchBoard-Live') { throw 'Local stable default development checkout drifted.' }

    # OneDrive-only existing checkout must remain NONCANONICAL_PRESERVE and must not become recommendedRoot.
    $onedriveProbe = Join-Path $tempRoot 'onedrive-only.fixture.json'
    @{
        username = 'corp_user27'
        userProfile = 'C:\Users\corp_user27'
        computerName = 'CORP-LT-0427'
        userDomain = 'CORP'
        azureAdJoined = $true
        domainJoined = $false
        tenantName = 'Example Corporation'
        oneDriveCommercial = 'C:\Users\corp_user27\OneDrive - Example Corporation'
        oneDriveConsumer = $null
        oneDrive = 'C:\Users\corp_user27\OneDrive - Example Corporation'
        desktopPath = 'C:\Users\corp_user27\OneDrive - Example Corporation\Desktop'
        documentsPath = 'C:\Users\corp_user27\OneDrive - Example Corporation\Documents'
        existingRepositoryRoot = 'C:\Users\corp_user27\OneDrive - Example Corporation\OG Laptop Backup\Desktop\dev\AgentSwitchBoard'
        tools = @{ curl = $true; git = $true; powershell = $true; pwsh = $true; winget = $true; wsl = $true }
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $onedriveProbe -Encoding utf8
    $onedriveOnly = & powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File $detector -Mode Detect -Emit Json -ProbeFile $onedriveProbe | ConvertFrom-Json
    if ($onedriveOnly.repository.recommendedRoot -ne 'C:\Users\corp_user27\dev\AgentSwitchBoard-Live') { throw 'OneDrive-only checkout incorrectly became recommendedRoot.' }
    if (@($onedriveOnly.pathRoles.noncanonicalExistingCheckouts).Count -lt 1) { throw 'OneDrive checkout was not recorded under pathRoles.noncanonicalExistingCheckouts.' }

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
