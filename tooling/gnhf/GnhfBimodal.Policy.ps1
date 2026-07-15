$modulePath = Join-Path $PSScriptRoot "GnhfBimodal.Policy.psm1"
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Bimodal policy module not found: $modulePath"
}
Import-Module $modulePath -Force -Global
