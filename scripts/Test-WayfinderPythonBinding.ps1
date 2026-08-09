[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot),
    [string]$PythonPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

. (Join-Path $RootPath 'tooling/harness/wayfinder/Resolve-WayfinderPython.ps1')

if ([string]::IsNullOrWhiteSpace($PythonPath)) {
    $fallback = Get-Command python -ErrorAction SilentlyContinue
    if (-not $fallback) { $fallback = Get-Command python3 -ErrorAction SilentlyContinue }
    if (-not $fallback) { throw 'Python 3 is required for the Wayfinder runtime-binding regression.' }
    $PythonPath = if ($fallback.Source) { $fallback.Source } else { $fallback.Path }
}

$explicit = Resolve-WayfinderPython -PythonPath $PythonPath -RootPath $RootPath
if ($explicit.Source -ne 'explicit-parameter') { throw 'Explicit PythonPath did not win interpreter precedence.' }
if (-not (Test-Path -LiteralPath $explicit.Path -PathType Leaf)) { throw 'Resolved explicit interpreter path does not exist.' }

$previousOverride = $env:ASB_WAYFINDER_PYTHON
try {
    $env:ASB_WAYFINDER_PYTHON = $explicit.Path
    $fromEnvironment = Resolve-WayfinderPython -RootPath $RootPath
    if ($fromEnvironment.Source -ne 'ASB_WAYFINDER_PYTHON') { throw 'ASB_WAYFINDER_PYTHON did not win fallback precedence.' }
    if ($fromEnvironment.Path -ne $explicit.Path) { throw 'Environment override resolved a different interpreter than the explicit proof interpreter.' }

    $threw = $false
    try {
        [void](Resolve-WayfinderPython -PythonPath (Join-Path $RootPath 'definitely-missing-wayfinder-python.exe') -RootPath $RootPath)
    }
    catch {
        $threw = $true
    }
    if (-not $threw) { throw 'An invalid explicit PythonPath silently fell back instead of failing closed.' }
}
finally {
    $env:ASB_WAYFINDER_PYTHON = $previousOverride
}

Write-Host 'PASS: Wayfinder Python runtime binding' -ForegroundColor Green
Write-Host "Python: $($explicit.Path)"
Write-Host "Version: $($explicit.Version)"
Write-Host 'Proof: explicit interpreter binding wins, environment override is deterministic, and invalid explicit paths fail closed.'
exit 0
