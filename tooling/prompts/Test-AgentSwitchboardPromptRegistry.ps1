[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$selector = Join-Path $RootPath 'tooling\prompts\Select-AgentSwitchboardPrompt.ps1'
$registry = Join-Path $RootPath '.ai\prompt-kits\v38\prompt-registry.v1.json.gz.b64'
$source = Join-Path $RootPath '.ai\prompt-kits\v38\source.json'
$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Check {
    param([bool]$Passed, [string]$Name, [string]$Message = '')
    if ($Passed) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("$Name`: $Message") }
}

function Invoke-Selector {
    param([string[]]$Arguments, [switch]$ExpectFailure)
    $output = @(& pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -File $selector @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($ExpectFailure) {
        if ($exitCode -eq 0) { throw "Selector unexpectedly succeeded: $($Arguments -join ' ')" }
    }
    elseif ($exitCode -ne 0) {
        throw "Selector failed ($exitCode): $($output -join [Environment]::NewLine)"
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = $output; Text = ($output -join [Environment]::NewLine) }
}

foreach ($path in @($selector, $registry, $source, (Join-Path $RootPath 'Select-AgentSwitchboardPrompt.cmd'))) {
    Add-Check -Passed (Test-Path -LiteralPath $path -PathType Leaf) -Name "required/$path" -Message 'file missing'
}

$sourceRecord = Get-Content -LiteralPath $source -Raw | ConvertFrom-Json
Add-Check -Passed ($sourceRecord.schemaVersion -eq 'agentswitchboard-prompt-kit-source/v1') -Name 'source/schema' -Message 'wrong source schema'
Add-Check -Passed ((Get-FileHash -LiteralPath $registry -Algorithm SHA256).Hash.ToLowerInvariant() -eq $sourceRecord.snapshotSha256) -Name 'source/snapshot-sha' -Message 'snapshot hash mismatch'

$list = Invoke-Selector -Arguments @('-Mode', 'List', '-AsJson')
$listRows = @($list.Text | ConvertFrom-Json)
Add-Check -Passed ($listRows.Count -eq 64) -Name 'selector/list-count' -Message "expected 64; got $($listRows.Count)"
Add-Check -Passed ($listRows[0].id -eq 'P00' -and $listRows[-1].id -eq 'P63') -Name 'selector/list-range' -Message 'P00-P63 not preserved'

$search = Invoke-Selector -Arguments @('-Mode', 'Search', '-Query', 'pull request', '-ExecutionSurface', 'regular_ai_prompt', '-AsJson')
$searchRows = @($search.Text | ConvertFrom-Json)
Add-Check -Passed ($searchRows.Count -gt 0) -Name 'selector/search' -Message 'search returned no prompts'
Add-Check -Passed (@($searchRows | Where-Object executionSurface -ne 'regular_ai_prompt').Count -eq 0) -Name 'selector/search-surface' -Message 'surface filter leaked'

$show = Invoke-Selector -Arguments @('-Mode', 'Show', '-PromptId', 'P07', '-ExecutionSurface', 'regular_ai_prompt', '-AsJson')
$showRecord = $show.Text | ConvertFrom-Json
Add-Check -Passed ($showRecord.id -eq 'P07') -Name 'selector/show' -Message 'wrong prompt returned'
Add-Check -Passed ($showRecord.text.StartsWith('EXECUTE THE REPO SPRINT')) -Name 'selector/show-text' -Message 'P07 text mismatch'

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('agentswitchboard-prompt-registry-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $tempRoot -Force)
try {
    $outputPath = Join-Path $tempRoot 'rendered-p07.txt'
    $render = Invoke-Selector -Arguments @(
        '-Mode', 'Render',
        '-PromptId', 'P07',
        '-ExecutionSurface', 'regular_ai_prompt',
        '-Variable', 'xyz_repo_or_path=EndeavorEverlasting/AgentSwitchboard,xyz_sprint_name=prompt-registry-proof,xyz_owned_scope=prompt-selector-and-tests,xyz_forbidden_scope=provider-calls,xyz_plan_directory=docs/prompt-kits/v38.md',
        '-OutputPath', $outputPath
    )
    Add-Check -Passed (Test-Path -LiteralPath $outputPath -PathType Leaf) -Name 'selector/render-file' -Message 'rendered file missing'
    $renderedText = Get-Content -LiteralPath $outputPath -Raw
    Add-Check -Passed ($renderedText.Contains('EndeavorEverlasting/AgentSwitchboard')) -Name 'selector/render-substitution' -Message 'variable not rendered'
    Add-Check -Passed ($renderedText -notmatch '\bxyz_[a-z0-9_]+\b') -Name 'selector/render-closure' -Message 'unresolved variables remain'

    [void](Invoke-Selector -Arguments @('-Mode', 'Show', '-PromptId', 'P07', '-ExecutionSurface', 'gnhf_launch_artifact') -ExpectFailure)
    [void](Invoke-Selector -Arguments @('-Mode', 'Render', '-PromptId', 'P07', '-Variable', 'xyz_repo_or_path=only-one') -ExpectFailure)
    Add-Check -Passed $true -Name 'selector/fail-closed' -Message ''

    $gnhf = Invoke-Selector -Arguments @('-Mode', 'Show', '-PromptId', 'P26', '-ExecutionSurface', 'gnhf_launch_artifact', '-AsJson')
    $gnhfRecord = $gnhf.Text | ConvertFrom-Json
    Add-Check -Passed ($gnhfRecord.text.Length -gt 20) -Name 'selector/gnhf-surface' -Message 'P26 GNHF launch content not found'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host 'AGENTSWITCHBOARD PROMPT REGISTRY' -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host "`nResult: $($passes.Count) passed / $($failures.Count) failed"
if ($failures.Count -gt 0) { exit 1 }
exit 0
