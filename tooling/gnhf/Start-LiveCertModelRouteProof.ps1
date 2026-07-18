[CmdletBinding()]
param(
    [string[]]$Models = @(
        'deepseek/deepseek-v4-pro',
        'deepseek/deepseek-v4-flash',
        'deepseek/deepseek-chat',
        'deepseek/deepseek-reasoner'
    ),
    [ValidateRange(5, 120)][int]$ProbeTimeoutSeconds = 30,
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [switch]$OpenWezTermWindows,
    [switch]$EnableSound
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'Live cert model-route proof requires PowerShell 7.'
}

$processHelpers = Join-Path $PSScriptRoot 'Gnhf.Process.ps1'
if (-not (Test-Path -LiteralPath $processHelpers -PathType Leaf)) {
    $processHelpers = Join-Path $InstallRoot 'Gnhf.Process.ps1'
}
if (-not (Test-Path -LiteralPath $processHelpers -PathType Leaf)) {
    throw "Windows-safe process helpers not found. Run Install-ProviderRoutedGnhf.ps1 -Apply first."
}
. $processHelpers

$logsRoot = Join-Path $InstallRoot 'logs\live-cert'
[void](New-Item -ItemType Directory -Path $logsRoot -Force)
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$reportPath = Join-Path $logsRoot "$stamp-model-route-matrix.json"
$markdownPath = Join-Path $logsRoot "$stamp-model-route-matrix.md"

$openCode = Get-Command opencode -ErrorAction Stop
$gnhf = Get-Command gnhf -ErrorAction SilentlyContinue
$gnhfVersion = if ($gnhf) { (& $gnhf.Source --version 2>&1 | Out-String).Trim() } else { '<missing>' }
$gnhfHelp = if ($gnhf) { (& $gnhf.Source --help 2>&1 | Out-String) } else { '' }
$gnhfModelFlag = $gnhfHelp -match '(?m)^\s*(-m,\s*)?--model\b'

$modelsProbe = Invoke-GnhfBoundedCommand `
    -FilePath $openCode.Source `
    -ArgumentList @('models', 'deepseek') `
    -WorkingDirectory (Get-Location).Path `
    -TimeoutSeconds $ProbeTimeoutSeconds

$listed = @()
if ($modelsProbe.exitCode -eq 0 -and -not $modelsProbe.timedOut) {
    $listed = @(
        $modelsProbe.output -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^deepseek/' }
    )
}

$marker = 'AGENT_SWITCHBOARD_MODEL_READY'
$markerPrompt = "Return exactly $marker. Do not inspect files, call tools, or modify state."
$results = [System.Collections.Generic.List[object]]::new()

function Write-LiveCertSound {
    param([bool]$Success)
    if (-not $EnableSound) { return }
    try {
        if ($Success) {
            [Console]::Beep(880, 120)
            [Console]::Beep(1175, 160)
        }
        else {
            [Console]::Beep(220, 240)
        }
    }
    catch {
        # Sound is best-effort and must not fail the cert.
    }
}

Write-Host "`n=== LIVE CERT MODEL-ROUTE MATRIX ===" -ForegroundColor Cyan
Write-Host "OpenCode:     $($openCode.Source)"
Write-Host "GNHF:         $gnhfVersion"
Write-Host "GNHF --model: $gnhfModelFlag"
Write-Host "Listed models:`n  $($listed -join "`n  ")"
Write-Host "Report:       $reportPath"

foreach ($model in $Models) {
    $entry = [ordered]@{
        model = $model
        listed = ($listed -contains $model)
        dispatch = $null
        exitCode = $null
        timedOut = $false
        markerObserved = $false
        elapsedMs = $null
        classification = 'not-run'
        why = $null
        outputSnippet = $null
    }

    if (-not $entry.listed) {
        $entry.classification = 'model-not-listed'
        $entry.why = 'OpenCode models deepseek did not list this model id.'
        Write-Host "[SKIP] $model — not listed" -ForegroundColor Yellow
        Write-LiveCertSound -Success:$false
        [void]$results.Add([pscustomobject]$entry)
        continue
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $probe = Invoke-GnhfBoundedCommand `
        -FilePath $openCode.Source `
        -ArgumentList @('run', '--model', $model, '--format', 'json', $markerPrompt) `
        -WorkingDirectory (Get-Location).Path `
        -TimeoutSeconds $ProbeTimeoutSeconds
    $sw.Stop()

    $entry.dispatch = $probe.dispatch
    $entry.exitCode = $probe.exitCode
    $entry.timedOut = $probe.timedOut
    $entry.elapsedMs = $sw.ElapsedMilliseconds
    $entry.markerObserved = ($probe.output -match [regex]::Escape($marker))
    $sanitized = ($probe.output -replace '(?i)(api[_-]?key|token|authorization)\s*[:=]\s*\S+', '$1=[REDACTED]')
    $entry.outputSnippet = $sanitized.Substring(0, [Math]::Min(1200, $sanitized.Length))

    if ($probe.timedOut) {
        $entry.classification = 'timeout'
        $entry.why = "Probe exceeded $ProbeTimeoutSeconds seconds."
    }
    elseif ($probe.exitCode -ne 0) {
        $entry.classification = 'provider-error'
        $entry.why = 'OpenCode exited nonzero before returning the exact marker.'
    }
    elseif (-not $entry.markerObserved) {
        $entry.classification = 'malformed-response'
        $entry.why = 'OpenCode returned output without AGENT_SWITCHBOARD_MODEL_READY.'
    }
    else {
        $entry.classification = 'ready'
        $entry.why = 'Exact model listed and returned AGENT_SWITCHBOARD_MODEL_READY through Windows-safe dispatch.'
    }

    $color = if ($entry.classification -eq 'ready') { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1} — {2} ({3} ms, dispatch={4})" -f $entry.classification.ToUpperInvariant(), $model, $entry.why, $entry.elapsedMs, $entry.dispatch) -ForegroundColor $color
    Write-LiveCertSound -Success:($entry.classification -eq 'ready')
    [void]$results.Add([pscustomobject]$entry)
}

$readyModels = @($results | Where-Object { $_.classification -eq 'ready' } | ForEach-Object { $_.model })
$report = [ordered]@{
    schemaVersion = 1
    kind = 'agentswitchboard.live-cert.model-route-matrix'
    promptKit = 'AI_Harness_Prompt_Kit_v39'
    relatedPrompts = @('P37', 'P45', 'P47', 'P48', 'P49')
    startedAt = (Get-Date).ToString('o')
    openCodePath = $openCode.Source
    openCodeDispatchHint = if ($openCode.Source.EndsWith('.ps1', [StringComparison]::OrdinalIgnoreCase)) { 'pwsh-file' } elseif ($openCode.Source.EndsWith('.cmd', [StringComparison]::OrdinalIgnoreCase)) { 'cmd-file' } else { 'native' }
    gnhfVersion = $gnhfVersion
    gnhfCliModelFlag = $gnhfModelFlag
    modelPinAuthority = 'opencode-preflight-plus-OPENCODE_CONFIG_CONTENT'
    listedDeepSeekModels = $listed
    probed = @($results)
    readyModels = $readyModels
    recommendedDefault = $(if ($readyModels -contains 'deepseek/deepseek-v4-pro') { 'deepseek/deepseek-v4-pro' } elseif ($readyModels.Count -gt 0) { $readyModels[0] } else { $null })
    proofCeiling = 'Local authenticated model marker proof and Windows dispatch classification only. Does not prove GNHF mutation, BlacksmithGuild delivery, Excel for Web, or production behavior.'
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding utf8

$md = @(
    '# Live cert model-route matrix',
    '',
    "- Prompt kit: AI_Harness_Prompt_Kit_v39",
    "- Related prompts: P37, P45, P47, P48, P49",
    "- GNHF: $gnhfVersion (CLI --model=$gnhfModelFlag)",
    "- Model pin authority: OpenCode preflight + OPENCODE_CONFIG_CONTENT",
    "- Recommended default: $($report.recommendedDefault)",
    '',
    '| Model | Listed | Classification | Elapsed ms | Why |',
    '| --- | --- | --- | --- | --- |'
)
foreach ($row in $results) {
    $md += "| `$($row.model)` | $($row.listed) | $($row.classification) | $($row.elapsedMs) | $($row.why) |"
}
$md += ''
$md += 'Proof ceiling: local authenticated marker and Windows dispatch only.'
$md -join [Environment]::NewLine | Set-Content -LiteralPath $markdownPath -Encoding utf8

# Mirror the latest matrix into the install root for operator dashboards.
Copy-Item -LiteralPath $reportPath -Destination (Join-Path $InstallRoot 'latest-live-cert-model-route-matrix.json') -Force
Copy-Item -LiteralPath $markdownPath -Destination (Join-Path $InstallRoot 'latest-live-cert-model-route-matrix.md') -Force

if ($OpenWezTermWindows) {
    $wezterm = Get-Command wezterm -ErrorAction SilentlyContinue
    if (-not $wezterm) {
        Write-Host 'WezTerm not found on PATH; matrix completed in the current shell only.' -ForegroundColor Yellow
    }
    else {
        $summaryScript = @"
`$Host.UI.RawUI.WindowTitle = 'AgentSwitchboard Live Cert — Model Route Matrix'
Write-Host 'Live cert model-route matrix complete.' -ForegroundColor Cyan
Write-Host 'Report: $reportPath'
Get-Content -LiteralPath '$markdownPath'
Write-Host ''
Write-Host 'Press Enter to close this WezTerm surface.'
[void][Console]::ReadLine()
"@
        $summaryPath = Join-Path $logsRoot "$stamp-wezterm-summary.ps1"
        Set-Content -LiteralPath $summaryPath -Value $summaryScript -Encoding utf8
        Start-Process -FilePath $wezterm.Source -ArgumentList @('start', '--cwd', (Get-Location).Path, '--', 'pwsh.exe', '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $summaryPath) | Out-Null
        Write-Host "Opened WezTerm summary window for $reportPath" -ForegroundColor Green
    }
}

Write-Host "`nReady models: $($readyModels -join ', ')" -ForegroundColor Green
Write-Host "Matrix JSON: $reportPath"
Write-Host "Matrix MD:   $markdownPath"

if ($readyModels.Count -eq 0) {
    exit 2
}
exit 0
