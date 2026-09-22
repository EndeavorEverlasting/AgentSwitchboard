[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ManifestPath = Join-Path $Root 'tooling\lua\harness\manifest.json'

if (-not (Test-Path -LiteralPath $ManifestPath)) {
    throw "Missing Lua harness manifest: $ManifestPath"
}

$Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$required = @($Manifest.components.PSObject.Properties.Value)

foreach ($relative in $required) {
    $path = Join-Path $Root $relative
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing Lua harness component: $relative"
    }
    & git -C $Root ls-files --error-unmatch -- $relative *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "Lua harness component is not tracked: $relative"
    }
}

$jsonFiles = @(
    'tooling/lua/harness/manifest.json',
    'tooling/lua/harness/codebase-map.json',
    'tooling/lua/harness/lua-embedding.contract.json',
    'tooling/lua/harness/workflow-registry.json',
    'tooling/lua/harness/artifact-registry.json',
    'tooling/lua/harness/validator-registry.json',
    'tooling/lua/harness/schemas/lua-harness.schema.json'
) + @(
    Get-ChildItem -LiteralPath (Join-Path $Root 'tooling\lua\harness\workflows') -Filter '*.json' |
    ForEach-Object { Resolve-Path -Relative $_.FullName }
)

foreach ($relative in $jsonFiles) {
    $path = if ([System.IO.Path]::IsPathRooted($relative)) { $relative } else { Join-Path $Root $relative }
    try {
        $null = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    }
    catch {
        throw "Invalid JSON: $relative :: $($_.Exception.Message)"
    }
}

$Python = Get-Command python -ErrorAction SilentlyContinue
if (-not $Python) { $Python = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $Python) { throw 'Python is required to validate the Lua harness contracts.' }

& $Python.Source (Join-Path $Root 'tests\test_lua_harness_contracts.py')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Python.Source (Join-Path $Root 'tooling\lua\Get-LuaHarnessStatus.py') --no-write *> $null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host '[PASS] LUA_HARNESS_COMPLETENESS'
