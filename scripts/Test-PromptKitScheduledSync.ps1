[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$required = @(
    'PromptKit-Website-Sync.cmd',
    'tooling\profiles\windows\Sync-PromptKitWebsite.ps1',
    'tooling\profiles\windows\Manage-PromptKitWebsiteSchedule.ps1',
    'tooling\profiles\windows\harness\prompt-kit-sync\prompt-kit-sync.manifest.json',
    'tooling\profiles\windows\harness\prompt-kit-sync\codebase-map.json',
    'docs\harness\prompt-kit-scheduled-sync.md',
    'tests\test_prompt_kit_scheduled_sync.py'
)

foreach ($relativePath in $required) {
    $path = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing Prompt Kit scheduled-sync contract file: $relativePath"
    }
}

$manifestPath = Join-Path $repoRoot 'tooling\profiles\windows\harness\prompt-kit-sync\prompt-kit-sync.manifest.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($manifest.id -ne 'prompt-kit-scheduled-sync') { throw 'Unexpected Prompt Kit sync manifest id.' }
if ([bool]$manifest.consent.defaultEnabled) { throw 'Prompt Kit scheduled sync must remain disabled by default.' }
if (-not [bool]$manifest.consent.networkRequiresEnabledToggle) { throw 'Network polling must require the enabled toggle.' }
if ($manifest.schedule.runLevel -ne 'limited') { throw 'Scheduled sync must run at limited privilege.' }

foreach ($relativePath in @(
    'tooling\profiles\windows\Sync-PromptKitWebsite.ps1',
    'tooling\profiles\windows\Manage-PromptKitWebsiteSchedule.ps1'
)) {
    $path = Join-Path $repoRoot $relativePath
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $details = ($errors | ForEach-Object { $_.Message }) -join [Environment]::NewLine
        throw "PowerShell parser errors in $relativePath`r`n$details"
    }
}

$python = if (Get-Command py -ErrorAction SilentlyContinue) {
    @{ File = 'py'; Prefix = @('-3') }
}
elseif (Get-Command python -ErrorAction SilentlyContinue) {
    @{ File = 'python'; Prefix = @() }
}
else {
    throw 'Python 3 is required for Prompt Kit scheduled-sync contract tests.'
}

$arguments = @($python.Prefix) + @('-m', 'unittest', 'tests.test_prompt_kit_scheduled_sync', '-v')
Push-Location $repoRoot
try {
    & $python.File @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Prompt Kit scheduled-sync Python tests failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

Write-Host 'Prompt Kit scheduled-sync contracts: PASS'
