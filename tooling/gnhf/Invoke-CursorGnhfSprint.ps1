[CmdletBinding(DefaultParameterSetName = "Plan")]
param(
    [Parameter(Mandatory)][string]$RequestPath,
    [Parameter(Mandatory)][string]$CompiledPromptPath,
    [string]$TargetRepo,
    [Parameter(ParameterSetName = "Plan")][switch]$PlanOnly,
    [Parameter(Mandatory, ParameterSetName = "Run")][switch]$Run,
    [switch]$CreateDisposableProofRepo
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$canonicalEntrypoint = Join-Path $PSScriptRoot "Invoke-ChatGPTDesktopGnhfSprint.ps1"
if (-not (Test-Path -LiteralPath $canonicalEntrypoint -PathType Leaf)) {
    throw "Canonical GNHF desktop/Cursor runtime is missing: $canonicalEntrypoint"
}

$forward = @{
    RequestPath = $RequestPath
    CompiledPromptPath = $CompiledPromptPath
    RuntimeFamily = "Cursor"
}
if (-not [string]::IsNullOrWhiteSpace($TargetRepo)) {
    $forward.TargetRepo = $TargetRepo
}
if ($PlanOnly) {
    $forward.PlanOnly = $true
}
if ($Run) {
    $forward.Run = $true
}
if ($CreateDisposableProofRepo) {
    $forward.CreateDisposableProofRepo = $true
}

& $canonicalEntrypoint @forward
exit $LASTEXITCODE
