Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Machine PATH values are Windows contract data even when validators execute on Linux.
# Normalize both slash characters explicitly rather than inheriting the validator host's separator semantics.
$script:PathTrimCharacters = [char[]]@([char]92, [char]47)

function Assert-ASBAdapterId {
    param([Parameter(Mandatory)][string]$AdapterId)
    if ($AdapterId -notmatch '^[a-z0-9][a-z0-9._-]{0,63}$') {
        throw "Invalid AgentSwitchboard bootstrap adapter id: $AdapterId"
    }
}

function Assert-ASBInstallId {
    param([Parameter(Mandatory)][string]$InstallId)
    if ($InstallId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -or $InstallId.Contains('..')) {
        throw 'Invalid AgentSwitchboard lifecycle install id. History identifiers may contain only letters, numbers, dot, underscore, and dash, may not contain dot-dot segments, and may not contain path separators.'
    }
}

function Get-ASBLifecycleRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AdapterId,
        [string]$ProgramDataRoot = $env:ProgramData
    )
    Assert-ASBAdapterId -AdapterId $AdapterId
    if ([string]::IsNullOrWhiteSpace($ProgramDataRoot)) {
        throw 'ProgramData root is required for machine bootstrap lifecycle state.'
    }
    return Join-Path $ProgramDataRoot "AgentSwitchboard\bootstrap-lifecycle\$AdapterId"
}

function Get-ASBLifecycleStatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AdapterId,
        [string]$ProgramDataRoot = $env:ProgramData
    )
    return Join-Path (Get-ASBLifecycleRoot -AdapterId $AdapterId -ProgramDataRoot $ProgramDataRoot) 'state.json'
}

function Read-ASBLifecycleState {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StatePath)
    if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf)) { return $null }
    try {
        return Get-Content -LiteralPath $StatePath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    }
    catch {
        throw "AgentSwitchboard lifecycle state is unreadable or invalid JSON: $StatePath :: $($_.Exception.Message)"
    }
}

function Write-ASBLifecycleStateAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StatePath,
        [Parameter(Mandatory)][System.Collections.IDictionary]$State
    )
    $directory = Split-Path -Parent $StatePath
    $null = New-Item -ItemType Directory -Path $directory -Force
    $temporary = Join-Path $directory ("state.{0}.tmp" -f [guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText(
            $temporary,
            ($State | ConvertTo-Json -Depth 100),
            [Text.UTF8Encoding]::new($false)
        )
        $null = Get-Content -LiteralPath $temporary -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        Move-Item -LiteralPath $temporary -Destination $StatePath -Force
    }
    finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Archive-ASBLifecycleState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$LifecycleRoot,
        [Parameter(Mandatory)][System.Collections.IDictionary]$State
    )
    $installId = [string]$State['installId']
    Assert-ASBInstallId -InstallId $installId
    $historyRoot = Join-Path $LifecycleRoot 'history'
    $null = New-Item -ItemType Directory -Path $historyRoot -Force
    $historyPath = Join-Path $historyRoot ("$installId.json")
    if (-not (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
        [IO.File]::WriteAllText(
            $historyPath,
            ($State | ConvertTo-Json -Depth 100),
            [Text.UTF8Encoding]::new($false)
        )
    }
    return $historyPath
}

function Get-ASBFileSha256 {
    [CmdletBinding()]
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function ConvertTo-ASBPathEntries {
    [CmdletBinding()]
    param([AllowNull()][string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return @() }
    return @($PathValue -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Test-ASBPathEntryEqual {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Left,
        [AllowNull()][string]$Right
    )
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
    $leftNormalized = $Left.Trim().TrimEnd($script:PathTrimCharacters)
    $rightNormalized = $Right.Trim().TrimEnd($script:PathTrimCharacters)
    return $leftNormalized -ieq $rightNormalized
}

function Test-ASBPathContainsEntry {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$PathValue,
        [Parameter(Mandatory)][string]$Entry
    )
    foreach ($candidate in @(ConvertTo-ASBPathEntries -PathValue $PathValue)) {
        if (Test-ASBPathEntryEqual -Left $candidate -Right $Entry) { return $true }
    }
    return $false
}

function Add-ASBPathEntry {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$PathValue,
        [Parameter(Mandatory)][string]$Entry,
        [ValidateSet('Append','Prepend')][string]$Position = 'Append'
    )
    $entries = @(ConvertTo-ASBPathEntries -PathValue $PathValue)
    if (Test-ASBPathContainsEntry -PathValue $PathValue -Entry $Entry) {
        return [pscustomobject]@{ Value = ($entries -join ';'); Changed = $false; Preexisting = $true }
    }
    $next = if ($Position -eq 'Prepend') { @($Entry) + $entries } else { $entries + @($Entry) }
    return [pscustomobject]@{ Value = ($next -join ';'); Changed = $true; Preexisting = $false }
}

function Remove-ASBPathEntry {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$PathValue,
        [Parameter(Mandatory)][string]$Entry
    )
    $entries = @(ConvertTo-ASBPathEntries -PathValue $PathValue)
    $next = @($entries | Where-Object { -not (Test-ASBPathEntryEqual -Left $_ -Right $Entry) })
    return [pscustomobject]@{
        Value = ($next -join ';')
        Changed = ($next.Count -ne $entries.Count)
        WasPresent = ($next.Count -ne $entries.Count)
    }
}

function Test-ASBDirectoryEmpty {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $true }
    return $null -eq (Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop | Select-Object -First 1)
}

Export-ModuleMember -Function @(
    'Get-ASBLifecycleRoot',
    'Get-ASBLifecycleStatePath',
    'Read-ASBLifecycleState',
    'Write-ASBLifecycleStateAtomic',
    'Archive-ASBLifecycleState',
    'Get-ASBFileSha256',
    'ConvertTo-ASBPathEntries',
    'Test-ASBPathEntryEqual',
    'Test-ASBPathContainsEntry',
    'Add-ASBPathEntry',
    'Remove-ASBPathEntry',
    'Test-ASBDirectoryEmpty'
)
