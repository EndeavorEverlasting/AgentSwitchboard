[CmdletBinding()]
param(
    [string]$RootPath = (Join-Path $PSScriptRoot '..')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Check {
    param([bool]$Condition, [string]$Name, [string]$Message)
    if ($Condition) { [void]$passes.Add($Name) } else { [void]$failures.Add("$Name`: $Message") }
}

$files = @(
    'Start-LiveCertModelRouteProof.ps1',
    'Start-LiveCertWezTermSprint.ps1'
)
foreach ($relative in $files) {
    $path = Join-Path $RootPath $relative
    Check (Test-Path -LiteralPath $path -PathType Leaf) "required/$relative" 'file missing'
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        Check ($errors.Count -eq 0) "parse/$relative" (($errors | ForEach-Object Message) -join '; ')
    }
}

$matrixText = Get-Content -LiteralPath (Join-Path $RootPath 'Start-LiveCertModelRouteProof.ps1') -Raw
Check ($matrixText.Contains('AGENT_SWITCHBOARD_MODEL_READY')) 'matrix/marker' 'exact marker missing'
Check ($matrixText.Contains('Invoke-GnhfBoundedCommand')) 'matrix/windows-dispatch' 'does not use Windows-safe process helper'
Check ($matrixText.Contains('model-not-listed')) 'matrix/classification' 'missing precise failure classes'
Check ($matrixText.Contains('AI_Harness_Prompt_Kit_v39')) 'matrix/prompt-kit' 'v39 prompt kit not referenced'
Check (-not $matrixText.Contains('DEEPSEEK_API_KEY')) 'matrix/no-secret' 'secret handling embedded'

$wezText = Get-Content -LiteralPath (Join-Path $RootPath 'Start-LiveCertWezTermSprint.ps1') -Raw
Check ($wezText.Contains("wezterm")) 'wezterm/command' 'WezTerm launch missing'
Check ($wezText.Contains('BlacksmithCompile')) 'wezterm/bounded-profile' 'bounded compile profile missing'
Check ($wezText.Contains('Start-BlacksmithGuildNightShift.ps1')) 'wezterm/night-launcher' 'night launcher not used'
Check ($wezText.Contains('refusing to start a GNHF sprint')) 'wezterm/fail-fast' 'failed matrix can still start GNHF'

Write-Host 'LIVE CERT CONTRACTS' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ''
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
