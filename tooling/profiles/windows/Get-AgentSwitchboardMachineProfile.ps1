[CmdletBinding()]
param(
    [ValidateSet('Detect', 'Apply')]
    [string]$Mode = 'Detect',

    [ValidateSet('Json', 'RepoRoot', 'ProfileId', 'None')]
    [string]$Emit = 'Json',

    [string]$RepoRoot,

    [string]$ProbeFile,

    [string]$OutputRoot = (Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\machine-profile')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedRepository = 'https://github.com/EndeavorEverlasting/AgentSwitchboard.git'

function Get-CommandAvailable {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Expand-KnownFolderValue {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    return [Environment]::ExpandEnvironmentVariables($Value)
}

function Get-LiveFacts {
    $shellFolders = $null
    try {
        $shellFolders = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop
    }
    catch {}

    $join = [ordered]@{
        azureAdJoined = $false
        domainJoined = $false
        tenantName = $null
    }
    $dsreg = Get-Command 'dsregcmd.exe' -ErrorAction SilentlyContinue
    if ($dsreg) {
        try {
            $status = (& $dsreg.Source /status 2>$null) -join "`n"
            $join.azureAdJoined = $status -match '(?m)^\s*AzureAdJoined\s*:\s*YES\s*$'
            $join.domainJoined = $status -match '(?m)^\s*DomainJoined\s*:\s*YES\s*$'
            $tenantMatch = [regex]::Match($status, '(?m)^\s*TenantName\s*:\s*(.+?)\s*$')
            if ($tenantMatch.Success) { $join.tenantName = $tenantMatch.Groups[1].Value.Trim() }
        }
        catch {}
    }

    return [ordered]@{
        username = $env:USERNAME
        userProfile = $env:USERPROFILE
        computerName = $env:COMPUTERNAME
        userDomain = $env:USERDOMAIN
        azureAdJoined = [bool]$join.azureAdJoined
        domainJoined = [bool]$join.domainJoined
        tenantName = $join.tenantName
        oneDriveCommercial = $env:OneDriveCommercial
        oneDriveConsumer = $env:OneDriveConsumer
        oneDrive = $env:OneDrive
        desktopPath = if ($shellFolders) { Expand-KnownFolderValue $shellFolders.Desktop } else { $null }
        documentsPath = if ($shellFolders) { Expand-KnownFolderValue $shellFolders.Personal } else { $null }
        existingRepositoryRoot = $null
        tools = [ordered]@{
            curl = Get-CommandAvailable 'curl.exe'
            git = Get-CommandAvailable 'git.exe'
            powershell = Get-CommandAvailable 'powershell.exe'
            pwsh = Get-CommandAvailable 'pwsh.exe'
            winget = Get-CommandAvailable 'winget.exe'
            wsl = Get-CommandAvailable 'wsl.exe'
        }
    }
}

function Get-ProbeFacts {
    param([Parameter(Mandatory)][string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    return Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Test-AgentSwitchboardCheckout {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath (Join-Path $Path '.git') -PathType Container)) { return $false }

    $git = Get-Command 'git.exe' -ErrorAction SilentlyContinue
    if (-not $git) { return $false }
    try {
        $origin = (& $git.Source -C $Path remote get-url origin 2>$null | Select-Object -First 1).Trim()
        return $origin -in @(
            $expectedRepository,
            'https://github.com/EndeavorEverlasting/AgentSwitchboard',
            'git@github.com:EndeavorEverlasting/AgentSwitchboard.git'
        )
    }
    catch { return $false }
}

function Get-CandidateClassification {
    param([Parameter(Mandatory)][string]$Source)
    switch -Regex ($Source) {
        '^(explicit-repo-root|environment-override|verified-machine-binding|canonical-user-local-root)$' {
            return [pscustomobject]@{ role = 'canonical-development-candidate'; disposition = 'CANONICAL' }
        }
        '^legacy-user-local-root$' {
            return [pscustomobject]@{ role = 'legacy-development-candidate'; disposition = 'NONCANONICAL_PRESERVE' }
        }
        '^(redirected-desktop-candidate|onedrive-candidate)$' {
            return [pscustomobject]@{ role = 'noncanonical-clone-or-backup'; disposition = 'NONCANONICAL_PRESERVE' }
        }
        '^probe-existing-checkout$' {
            return [pscustomobject]@{ role = 'probe-existing-checkout'; disposition = 'UNKNOWN' }
        }
        default {
            return [pscustomobject]@{ role = 'unclassified-candidate'; disposition = 'UNKNOWN' }
        }
    }
}

function Add-Candidate {
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$List,
        [AllowNull()][string]$Path,
        [Parameter(Mandatory)][string]$Source,
        [switch]$SimulatedExisting
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ($List | Where-Object { $_.path -ieq $expanded }) { return }
    $classification = Get-CandidateClassification -Source $Source
    [void]$List.Add([pscustomobject]@{
        path = $expanded
        source = $Source
        role = [string]$classification.role
        disposition = [string]$classification.disposition
        exists = if ($SimulatedExisting) { $true } else { Test-AgentSwitchboardCheckout $expanded }
    })
}

$facts = if ($ProbeFile) { Get-ProbeFacts $ProbeFile } else { Get-LiveFacts }
if ([string]::IsNullOrWhiteSpace([string]$facts.userProfile)) {
    throw 'Machine profile detection requires a userProfile value.'
}

$reasons = [System.Collections.Generic.List[string]]::new()
$signals = [System.Collections.Generic.List[string]]::new()
$managed = [bool]$facts.azureAdJoined -or [bool]$facts.domainJoined
$commercialOneDrive = -not [string]::IsNullOrWhiteSpace([string]$facts.oneDriveCommercial)
$consumerOneDrive = -not [string]::IsNullOrWhiteSpace([string]$facts.oneDriveConsumer)
$redirectedDesktop = -not [string]::IsNullOrWhiteSpace([string]$facts.desktopPath) -and ([string]$facts.desktopPath -match '(?i)OneDrive')
$redirectedDocuments = -not [string]::IsNullOrWhiteSpace([string]$facts.documentsPath) -and ([string]$facts.documentsPath -match '(?i)OneDrive')

if ([bool]$facts.azureAdJoined) { [void]$signals.Add('azure-ad-joined') }
if ([bool]$facts.domainJoined) { [void]$signals.Add('domain-joined') }
if ($commercialOneDrive) { [void]$signals.Add('commercial-onedrive') }
if ($consumerOneDrive) { [void]$signals.Add('consumer-onedrive') }
if ($redirectedDesktop) { [void]$signals.Add('desktop-redirected-to-onedrive') }
if ($redirectedDocuments) { [void]$signals.Add('documents-redirected-to-onedrive') }
if ([string]$facts.username -match '^[a-z]{1,8}_[a-z0-9]+$') { [void]$signals.Add('corporate-username-convention') }
if ([string]$facts.computerName -match '^[A-Z0-9-]{6,15}$') { [void]$signals.Add('managed-hostname-convention') }

$profileId = if ($managed -and $commercialOneDrive) {
    'enterprise-managed-onedrive'
}
elseif ($managed) {
    'enterprise-managed-local'
}
elseif ($commercialOneDrive) {
    'work-or-school-onedrive'
}
elseif ($consumerOneDrive) {
    'personal-onedrive'
}
else {
    'local-windows'
}

if ($managed) { [void]$reasons.Add('Windows reports enterprise join signals.') }
if ($commercialOneDrive) { [void]$reasons.Add('A commercial OneDrive root is present.') }
if ($consumerOneDrive) { [void]$reasons.Add('A consumer OneDrive root is present.') }
if ($redirectedDesktop -or $redirectedDocuments) { [void]$reasons.Add('Known folders are redirected; canonical repositories must not depend on Desktop or Documents.') }

$candidates = [System.Collections.Generic.List[object]]::new()
$simulated = $null
$environmentOverride = [string]$env:AGENT_SWITCHBOARD_REPO
if ($ProbeFile -and $facts.PSObject.Properties.Name -contains 'existingRepositoryRoot') {
    $simulated = [string]$facts.existingRepositoryRoot
}
Add-Candidate $candidates $RepoRoot 'explicit-repo-root' -SimulatedExisting:($ProbeFile -and $RepoRoot -and $RepoRoot -ieq $simulated)
Add-Candidate $candidates $environmentOverride 'environment-override'
if ($simulated) { Add-Candidate $candidates $simulated 'probe-existing-checkout' -SimulatedExisting }

$bindingPath = Join-Path $env:LOCALAPPDATA 'AgentSwitchBoard\state\repo-path.txt'
if (-not $ProbeFile -and (Test-Path -LiteralPath $bindingPath -PathType Leaf)) {
    $bound = (Get-Content -LiteralPath $bindingPath -TotalCount 1 -ErrorAction SilentlyContinue)
    Add-Candidate $candidates $bound 'verified-machine-binding'
}

$canonicalRoot = Join-Path ([string]$facts.userProfile) 'dev\AgentSwitchBoard-Live'
$legacyRoot = Join-Path ([string]$facts.userProfile) 'dev\AgentSwitchBoard'
Add-Candidate $candidates $canonicalRoot 'canonical-user-local-root'
Add-Candidate $candidates $legacyRoot 'legacy-user-local-root'
if (-not [string]::IsNullOrWhiteSpace([string]$facts.desktopPath)) {
    Add-Candidate $candidates (Join-Path ([string]$facts.desktopPath) 'dev\AgentSwitchBoard-Live') 'redirected-desktop-candidate'
    Add-Candidate $candidates (Join-Path ([string]$facts.desktopPath) 'dev\AgentSwitchBoard') 'redirected-desktop-candidate'
}
foreach ($oneDriveRoot in @($facts.oneDriveCommercial, $facts.oneDriveConsumer, $facts.oneDrive)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$oneDriveRoot)) {
        Add-Candidate $candidates (Join-Path ([string]$oneDriveRoot) 'dev\AgentSwitchBoard-Live') 'onedrive-candidate'
    }
}

# Reclassify probe/binding paths by their actual location so Desktop/OneDrive copies stay noncanonical.
foreach ($candidate in $candidates) {
    if ($candidate.path -ieq $canonicalRoot) {
        $candidate.source = if ($candidate.source -eq 'canonical-user-local-root') { $candidate.source } else { $candidate.source }
        $candidate.role = 'canonical-development-candidate'
        $candidate.disposition = 'CANONICAL'
    }
    elseif ($candidate.path -ieq $legacyRoot) {
        $candidate.role = 'legacy-development-candidate'
        $candidate.disposition = 'NONCANONICAL_PRESERVE'
    }
    elseif (
        (-not [string]::IsNullOrWhiteSpace([string]$facts.desktopPath) -and $candidate.path.StartsWith(([string]$facts.desktopPath), [System.StringComparison]::OrdinalIgnoreCase)) -or
        (-not [string]::IsNullOrWhiteSpace([string]$facts.oneDriveCommercial) -and $candidate.path.StartsWith(([string]$facts.oneDriveCommercial), [System.StringComparison]::OrdinalIgnoreCase)) -or
        (-not [string]::IsNullOrWhiteSpace([string]$facts.oneDriveConsumer) -and $candidate.path.StartsWith(([string]$facts.oneDriveConsumer), [System.StringComparison]::OrdinalIgnoreCase)) -or
        (-not [string]::IsNullOrWhiteSpace([string]$facts.oneDrive) -and $candidate.path.StartsWith(([string]$facts.oneDrive), [System.StringComparison]::OrdinalIgnoreCase)) -or
        ($candidate.path -match '(?i)\\OneDrive(\\|$)')
    ) {
        $candidate.role = 'noncanonical-clone-or-backup'
        $candidate.disposition = 'NONCANONICAL_PRESERVE'
    }
}

# Prefer binding/canonical/legacy roots. A binding under Desktop/OneDrive is CONFLICT evidence, not authority.
$bindingCandidate = $candidates | Where-Object { $_.source -eq 'verified-machine-binding' -and $_.exists } | Select-Object -First 1
if ($bindingCandidate -and $bindingCandidate.disposition -eq 'NONCANONICAL_PRESERVE') {
    [void]$reasons.Add("CONFLICT: verified machine binding points at noncanonical path '$($bindingCandidate.path)'; canonical development root remains $canonicalRoot.")
    $bindingCandidate = $null
}

$preferredExisting = $candidates |
    Where-Object {
        $_.exists -and (
            ($bindingCandidate -and $_.path -ieq $bindingCandidate.path) -or
            $_.disposition -eq 'CANONICAL' -or
            $_.path -ieq $legacyRoot
        )
    } |
    Select-Object -First 1
$noncanonicalExisting = @(
    $candidates | Where-Object {
        $_.exists -and $_.disposition -eq 'NONCANONICAL_PRESERVE'
    }
)

$recommendedRepoRoot = if ($RepoRoot) {
    [Environment]::ExpandEnvironmentVariables($RepoRoot)
}
elseif (-not [string]::IsNullOrWhiteSpace($environmentOverride)) {
    [Environment]::ExpandEnvironmentVariables($environmentOverride)
}
elseif ($preferredExisting) {
    $preferredExisting.path
}
else {
    $canonicalRoot
}

$pathRoles = [ordered]@{
    profileKey = $profileId
    developmentCheckout = $recommendedRepoRoot
    productionUsePath = $recommendedRepoRoot
    worktreeRoot = (Join-Path ([string]$env:LOCALAPPDATA) 'AgentSwitchboard\worktrees')
    canonicalEntrypoint = 'Pull-And-Run-AgentSwitchboard.cmd'
    openCodeEntrypoint = 'Bootstrap-OpenCode-SystemWide.cmd'
    pathRelation = 'same-path'
    pathRelationNotes = 'For the Windows technician profile, the development checkout is also the operator use path for repository-owned commands. Machine-wide OpenCode under Program Files is a separate installed runtime surface, not a second Git checkout.'
    stableDefaultDevelopmentCheckout = $canonicalRoot
    noncanonicalExistingCheckouts = @($noncanonicalExisting | ForEach-Object {
            [ordered]@{
                path = $_.path
                source = $_.source
                disposition = $_.disposition
            }
        })
}

if ($RepoRoot) {
    [void]$reasons.Add('An explicit repository root was selected by the operator.')
}
elseif (-not [string]::IsNullOrWhiteSpace($environmentOverride)) {
    [void]$reasons.Add('AGENT_SWITCHBOARD_REPO selected the repository root before checkout discovery.')
}
elseif ($preferredExisting) {
    [void]$reasons.Add("A verified existing checkout was selected from '$($preferredExisting.source)'.")
}
else {
    [void]$reasons.Add('No verified canonical/legacy checkout was found; the stable user-local dev root was selected.')
}
if ($noncanonicalExisting.Count -gt 0) {
    [void]$reasons.Add('One or more Desktop/OneDrive checkouts were observed and preserved as noncanonical; they do not replace %USERPROFILE%\dev\AgentSwitchBoard-Live.')
}

$confidence = if ($signals.Count -ge 3) { 'high' } elseif ($signals.Count -ge 1) { 'medium' } else { 'low' }
$profile = [ordered]@{
    schema = 'agentswitchboard.machine-profile.v1'
    detectedAt = (Get-Date).ToUniversalTime().ToString('o')
    profileId = $profileId
    confidence = $confidence
    identity = [ordered]@{
        username = [string]$facts.username
        userProfile = [string]$facts.userProfile
        computerName = [string]$facts.computerName
        userDomain = [string]$facts.userDomain
        tenantName = [string]$facts.tenantName
        azureAdJoined = [bool]$facts.azureAdJoined
        domainJoined = [bool]$facts.domainJoined
    }
    pathConventions = [ordered]@{
        desktop = [string]$facts.desktopPath
        documents = [string]$facts.documentsPath
        oneDriveCommercial = [string]$facts.oneDriveCommercial
        oneDriveConsumer = [string]$facts.oneDriveConsumer
        oneDrive = [string]$facts.oneDrive
        desktopRedirected = $redirectedDesktop
        documentsRedirected = $redirectedDocuments
    }
    tools = $facts.tools
    signals = @($signals)
    repository = [ordered]@{
        expectedOrigin = $expectedRepository
        candidates = @($candidates)
        recommendedRoot = $recommendedRepoRoot
        selectionPolicy = 'explicit > environment override > verified machine binding/canonical/legacy user-local checkout > stable user-local dev root; Desktop/OneDrive copies are NONCANONICAL_PRESERVE evidence and never silently become the development root'
    }
    pathRoles = $pathRoles
    reasons = @($reasons)
    proofCeiling = 'Local environment observation and deterministic path recommendation only. This profile does not prove package installation, authentication, provider access, launcher behavior, or live agent success.'
}

if ($Mode -eq 'Apply') {
    $null = New-Item -ItemType Directory -Path $OutputRoot -Force
    $jsonPath = Join-Path $OutputRoot 'machine-profile.json'
    $cmdPath = Join-Path $OutputRoot 'machine-profile.env.cmd'
    $ps1Path = Join-Path $OutputRoot 'machine-profile.env.ps1'
    $profile | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    @(
        '@echo off',
        ('set "AGENT_SWITCHBOARD_MACHINE_PROFILE={0}"' -f $profileId),
        ('set "AGENT_SWITCHBOARD_REPO={0}"' -f $recommendedRepoRoot),
        ('set "AGENT_SWITCHBOARD_DEV_ROOT={0}"' -f $canonicalRoot),
        ('set "AGENT_SWITCHBOARD_USE_ROOT={0}"' -f $recommendedRepoRoot),
        ('set "AGENT_SWITCHBOARD_WORKTREE_ROOT={0}"' -f $pathRoles.worktreeRoot),
        ('set "AGENT_SWITCHBOARD_MACHINE_PROFILE_JSON={0}"' -f $jsonPath)
    ) | Set-Content -LiteralPath $cmdPath -Encoding ASCII
    @(
        ('$env:AGENT_SWITCHBOARD_MACHINE_PROFILE = ''{0}''' -f $profileId.Replace("'", "''")),
        ('$env:AGENT_SWITCHBOARD_REPO = ''{0}''' -f $recommendedRepoRoot.Replace("'", "''")),
        ('$env:AGENT_SWITCHBOARD_DEV_ROOT = ''{0}''' -f $canonicalRoot.Replace("'", "''")),
        ('$env:AGENT_SWITCHBOARD_USE_ROOT = ''{0}''' -f $recommendedRepoRoot.Replace("'", "''")),
        ('$env:AGENT_SWITCHBOARD_WORKTREE_ROOT = ''{0}''' -f ([string]$pathRoles.worktreeRoot).Replace("'", "''")),
        ('$env:AGENT_SWITCHBOARD_MACHINE_PROFILE_JSON = ''{0}''' -f $jsonPath.Replace("'", "''"))
    ) | Set-Content -LiteralPath $ps1Path -Encoding UTF8
}

switch ($Emit) {
    'RepoRoot' { Write-Output $recommendedRepoRoot }
    'ProfileId' { Write-Output $profileId }
    'Json' { $profile | ConvertTo-Json -Depth 8 }
    'None' { }
}
