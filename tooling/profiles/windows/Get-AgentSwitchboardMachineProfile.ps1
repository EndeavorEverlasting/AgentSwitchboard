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
    if (-not $git) { return $true }
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
    [void]$List.Add([pscustomobject]@{
        path = $expanded
        source = $Source
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
if ($ProbeFile -and $facts.PSObject.Properties.Name -contains 'existingRepositoryRoot') {
    $simulated = [string]$facts.existingRepositoryRoot
}
Add-Candidate $candidates $RepoRoot 'explicit-repo-root' -SimulatedExisting:($ProbeFile -and $RepoRoot -and $RepoRoot -ieq $simulated)
Add-Candidate $candidates $env:AGENT_SWITCHBOARD_REPO 'environment-override'
if ($simulated) { Add-Candidate $candidates $simulated 'probe-existing-checkout' -SimulatedExisting }

$bindingPath = Join-Path $env:LOCALAPPDATA 'AgentSwitchBoard\state\repo-path.txt'
if (-not $ProbeFile -and (Test-Path -LiteralPath $bindingPath -PathType Leaf)) {
    $bound = (Get-Content -LiteralPath $bindingPath -TotalCount 1 -ErrorAction SilentlyContinue)
    Add-Candidate $candidates $bound 'verified-machine-binding'
}

$canonicalRoot = Join-Path ([string]$facts.userProfile) 'dev\AgentSwitchBoard-Live'
Add-Candidate $candidates $canonicalRoot 'canonical-user-local-root'
Add-Candidate $candidates (Join-Path ([string]$facts.userProfile) 'dev\AgentSwitchBoard') 'legacy-user-local-root'
if (-not [string]::IsNullOrWhiteSpace([string]$facts.desktopPath)) {
    Add-Candidate $candidates (Join-Path ([string]$facts.desktopPath) 'dev\AgentSwitchBoard-Live') 'redirected-desktop-candidate'
    Add-Candidate $candidates (Join-Path ([string]$facts.desktopPath) 'dev\AgentSwitchBoard') 'redirected-desktop-candidate'
}
foreach ($oneDriveRoot in @($facts.oneDriveCommercial, $facts.oneDriveConsumer, $facts.oneDrive)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$oneDriveRoot)) {
        Add-Candidate $candidates (Join-Path ([string]$oneDriveRoot) 'dev\AgentSwitchBoard-Live') 'onedrive-candidate'
    }
}

$existing = $candidates | Where-Object { $_.exists } | Select-Object -First 1
$recommendedRepoRoot = if ($RepoRoot) {
    [Environment]::ExpandEnvironmentVariables($RepoRoot)
}
elseif ($existing) {
    $existing.path
}
else {
    $canonicalRoot
}

if ($existing) {
    [void]$reasons.Add("A verified existing checkout was selected from '$($existing.source)'.")
}
else {
    [void]$reasons.Add('No verified checkout was found; the stable user-local dev root was selected.')
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
        selectionPolicy = 'explicit > verified existing checkout > stable user-local dev root; OneDrive paths are evidence, not the new-checkout default'
    }
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
        ('set "AGENT_SWITCHBOARD_MACHINE_PROFILE_JSON={0}"' -f $jsonPath)
    ) | Set-Content -LiteralPath $cmdPath -Encoding ASCII
    @(
        ('$env:AGENT_SWITCHBOARD_MACHINE_PROFILE = ''{0}''' -f $profileId.Replace("'", "''")),
        ('$env:AGENT_SWITCHBOARD_REPO = ''{0}''' -f $recommendedRepoRoot.Replace("'", "''")),
        ('$env:AGENT_SWITCHBOARD_MACHINE_PROFILE_JSON = ''{0}''' -f $jsonPath.Replace("'", "''"))
    ) | Set-Content -LiteralPath $ps1Path -Encoding UTF8
}

switch ($Emit) {
    'RepoRoot' { Write-Output $recommendedRepoRoot }
    'ProfileId' { Write-Output $profileId }
    'Json' { $profile | ConvertTo-Json -Depth 8 }
    'None' { }
}
