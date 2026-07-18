[CmdletBinding()]
param(
    [ValidateSet('List', 'Search', 'Show', 'Render')]
    [string]$Mode = 'List',
    [ValidatePattern('^P\d{2}$')]
    [string]$PromptId,
    [string]$Query,
    [ValidateSet('regular_ai_prompt', 'gnhf_launch_artifact')]
    [string]$ExecutionSurface,
    [string[]]$Variable = @(),
    [switch]$AllowUnresolved,
    [switch]$AsJson,
    [string]$OutputPath,
    [string]$RegistryPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.ai\prompt-kits\v38\prompt-registry.v1.json.gz.b64')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256Text {
    param([Parameter(Mandatory)][string]$Text)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-Sha256File {
    param([Parameter(Mandatory)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RegistryJson {
    param([Parameter(Mandatory)][string]$Path)
    if (-not $Path.EndsWith('.gz.b64', [StringComparison]::OrdinalIgnoreCase)) {
        return Get-Content -LiteralPath $Path -Raw
    }
    $encoded = (Get-Content -LiteralPath $Path -Raw).Trim()
    try {
        $compressed = [Convert]::FromBase64String($encoded)
    }
    catch {
        throw "Prompt registry bundle is not valid base64: $($_.Exception.Message)"
    }
    $input = [IO.MemoryStream]::new($compressed, $false)
    $gzip = [IO.Compression.GZipStream]::new($input, [IO.Compression.CompressionMode]::Decompress)
    $reader = [IO.StreamReader]::new($gzip, [Text.Encoding]::UTF8, $true)
    try {
        return $reader.ReadToEnd()
    }
    finally {
        $reader.Dispose()
        $gzip.Dispose()
        $input.Dispose()
    }
}

function ConvertTo-VariableMap {
    param(
        [string[]]$Records,
        [Parameter(Mandatory)][System.Collections.Generic.HashSet[string]]$KnownVariables
    )
    $values = [ordered]@{}
    foreach ($record in @($Records)) {
        $separator = $record.IndexOf('=')
        if ($separator -lt 1) {
            throw "Variable values must use name=value syntax. Invalid value: '$record'"
        }
        $name = $record.Substring(0, $separator)
        $value = $record.Substring($separator + 1)
        if ($name -notmatch '^xyz_[a-z0-9_]+$') {
            throw "Invalid prompt variable name '$name'. Expected xyz_<lowercase_name>."
        }
        if (-not $KnownVariables.Contains($name)) {
            throw "Variable '$name' is not defined by the V38 prompt registry."
        }
        if ($values.Contains($name)) {
            throw "Variable '$name' was supplied more than once."
        }
        $values[$name] = $value
    }
    return $values
}

function Write-Result {
    param([Parameter(Mandatory)][AllowNull()][AllowEmptyCollection()]$Value)
    if ($AsJson) {
        $Value | ConvertTo-Json -Depth 20
    }
    else {
        $Value
    }
}

$RegistryPath = [IO.Path]::GetFullPath($RegistryPath)
if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) {
    throw "Prompt registry not found: $RegistryPath"
}
$registryRoot = Split-Path -Parent $RegistryPath
$sourcePath = Join-Path $registryRoot 'source.json'
if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
    $source = Get-Content -LiteralPath $sourcePath -Raw | ConvertFrom-Json
    if ([string]$source.schemaVersion -ne 'agentswitchboard-prompt-kit-source/v1') {
        throw "Unsupported prompt-kit source schema: $($source.schemaVersion)"
    }
    $actualSnapshotHash = Get-Sha256File -Path $RegistryPath
    if ($actualSnapshotHash -ne [string]$source.snapshotSha256) {
        throw "Prompt registry snapshot hash mismatch. Expected $($source.snapshotSha256); observed $actualSnapshotHash."
    }
}

$registry = Get-RegistryJson -Path $RegistryPath | ConvertFrom-Json -Depth 100
if ([string]$registry.schemaVersion -ne 'ai-harness-prompt-registry/v1') {
    throw "Unsupported prompt registry schema: $($registry.schemaVersion)"
}
if ([string]$registry.kitVersion -ne 'v38') {
    throw "Unsupported prompt-kit version: $($registry.kitVersion)"
}
$prompts = @($registry.prompts | Sort-Object sequence)
if ($prompts.Count -ne 45) {
    throw "V38 registry must contain 45 prompts; found $($prompts.Count)."
}
for ($index = 0; $index -lt $prompts.Count; $index++) {
    $expectedId = 'P{0:d2}' -f $index
    $prompt = $prompts[$index]
    if ([string]$prompt.id -ne $expectedId -or [int]$prompt.sequence -ne $index) {
        throw "Prompt sequence is not contiguous at index $index."
    }
    $actualTextHash = Get-Sha256Text -Text ([string]$prompt.text)
    if ($actualTextHash -ne [string]$prompt.textSha256) {
        throw "Prompt text hash mismatch for $expectedId."
    }
}

$knownVariables = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($record in @($registry.variables)) {
    [void]$knownVariables.Add([string]$record.name)
}

if ($Mode -in @('Show', 'Render') -and [string]::IsNullOrWhiteSpace($PromptId)) {
    throw "-$Mode requires -PromptId P00 through P44."
}
if ($Mode -eq 'Search' -and [string]::IsNullOrWhiteSpace($Query)) {
    throw '-Search requires -Query.'
}
if ($Variable.Count -gt 0 -and $Mode -ne 'Render') {
    throw '-Variable is valid only with -Mode Render.'
}
if ($OutputPath -and $Mode -ne 'Render') {
    throw '-OutputPath is valid only with -Mode Render.'
}

$matches = @($prompts)
if ($ExecutionSurface) {
    $matches = @($matches | Where-Object { [string]$_.executionSurface -eq $ExecutionSurface })
}

switch ($Mode) {
    'List' {
        $rows = @($matches | ForEach-Object {
            [pscustomobject][ordered]@{
                id = [string]$_.id
                name = [string]$_.name
                promptClass = [string]$_.promptClass
                executionSurface = [string]$_.executionSurface
                useThisWhen = [string]$_.useThisWhen
                requiredVariables = @($_.requiredVariables)
            }
        })
        Write-Result -Value $rows
        exit 0
    }
    'Search' {
        $needle = $Query.Trim()
        $rows = @($matches | Where-Object {
            $haystack = @(
                [string]$_.id,
                [string]$_.name,
                [string]$_.moment,
                [string]$_.promptType,
                [string]$_.promptClass,
                [string]$_.sprintPathRole,
                [string]$_.useThisWhen,
                [string]$_.doNotUseWhen,
                [string]$_.expectedOutput,
                [string]$_.text
            ) -join "`n"
            $haystack.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0
        } | ForEach-Object {
            [pscustomobject][ordered]@{
                id = [string]$_.id
                name = [string]$_.name
                promptClass = [string]$_.promptClass
                executionSurface = [string]$_.executionSurface
                useThisWhen = [string]$_.useThisWhen
                expectedOutput = [string]$_.expectedOutput
                requiredVariables = @($_.requiredVariables)
            }
        })
        Write-Result -Value $rows
        exit 0
    }
}

$selected = @($prompts | Where-Object { [string]$_.id -eq $PromptId })
if ($selected.Count -ne 1) {
    throw "Prompt '$PromptId' was not found."
}
$selected = $selected[0]
if ($ExecutionSurface -and [string]$selected.executionSurface -ne $ExecutionSurface) {
    throw "Prompt $PromptId is '$($selected.executionSurface)', not '$ExecutionSurface'. Refusing to cross the regular-AI/GNHF artifact boundary."
}

if ($Mode -eq 'Show') {
    Write-Result -Value $selected
    exit 0
}

$variableMap = ConvertTo-VariableMap -Records $Variable -KnownVariables $knownVariables
$required = @($selected.requiredVariables | ForEach-Object { [string]$_ })
$missing = @($required | Where-Object { -not $variableMap.Contains($_) })
if ($missing.Count -gt 0 -and -not $AllowUnresolved) {
    throw "Prompt $PromptId requires values for: $($missing -join ', ')."
}

$rendered = [string]$selected.text
foreach ($name in $variableMap.Keys) {
    $pattern = '\b' + [regex]::Escape([string]$name) + '\b'
    $replacement = [string]$variableMap[$name]
    $rendered = [regex]::Replace(
        $rendered,
        $pattern,
        [Text.RegularExpressions.MatchEvaluator]{ param($match) $replacement }
    )
}
$unresolved = @([regex]::Matches($rendered, '\bxyz_[a-z0-9_]+\b') | ForEach-Object Value | Sort-Object -Unique)
if ($unresolved.Count -gt 0 -and -not $AllowUnresolved) {
    throw "Rendered prompt still contains unresolved variables: $($unresolved -join ', ')."
}

$result = [pscustomobject][ordered]@{
    schemaVersion = 'agentswitchboard-rendered-prompt/v1'
    kitVersion = [string]$registry.kitVersion
    promptId = [string]$selected.id
    name = [string]$selected.name
    promptClass = [string]$selected.promptClass
    executionSurface = [string]$selected.executionSurface
    sourceTextSha256 = [string]$selected.textSha256
    renderedTextSha256 = Get-Sha256Text -Text $rendered
    appliedVariables = @($variableMap.Keys)
    unresolvedVariables = $unresolved
    text = $rendered
}

if ($OutputPath) {
    $fullOutputPath = [IO.Path]::GetFullPath($OutputPath)
    $registryPrefix = $registryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($fullOutputPath.StartsWith($registryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Rendered prompts may not overwrite or enter the canonical prompt-kit snapshot directory.'
    }
    $parent = Split-Path -Parent $fullOutputPath
    if ($parent) {
        [void](New-Item -ItemType Directory -Path $parent -Force)
    }
    if ($AsJson) {
        $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $fullOutputPath -Encoding utf8NoBOM
    }
    else {
        Set-Content -LiteralPath $fullOutputPath -Value $rendered -Encoding utf8NoBOM
    }
    Write-Host "Rendered prompt: $fullOutputPath" -ForegroundColor Cyan
}
else {
    if ($AsJson) {
        $result | ConvertTo-Json -Depth 20
    }
    else {
        $rendered
    }
}
