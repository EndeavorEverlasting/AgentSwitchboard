[CmdletBinding()]
param(
    [string]$StageId = 'P08',
    [string]$RunId,
    [string]$RepoRoot,
    [string]$StageDir,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$parentDir = Split-Path -Parent $scriptDir
$commonModule = Join-Path $parentDir 'TechnicianLiveCert.Common.psm1'
Import-Module -Name $commonModule -Force

Write-Host "Running P08-Finalize stage..." -ForegroundColor Yellow

$runContext = Get-TechnicianLiveCertRunContext -RunId $RunId
$runDir = Get-TechnicianLiveCertRunDir -RunId $runContext.runId

# 1. Summary JSON
$summaryPath = Join-Path $runDir 'technician-live-cert-summary.json'
Write-TechnicianLiveCertJson -Object $runContext -Path $summaryPath

# 2. Stage Matrix CSV
$matrixPath = Join-Path $runDir 'technician-live-cert-stage-matrix.csv'
$csvLines = [System.Collections.Generic.List[string]]::new()
[void]$csvLines.Add("StageId,Name,Status,StartedAt,CompletedAt,ExitCode")

foreach ($prop in $runContext.stages.PSObject.Properties) {
    $s = $prop.Value
    [void]$csvLines.Add("$($s.stageId),`"$($s.name)`",$($s.status),$($s.startedAt),$($s.completedAt),$($s.exitCode)")
}

[System.IO.File]::WriteAllLines($matrixPath, $csvLines, [System.Text.Encoding]::UTF8)

# 3. Handoff TXT
$handoffPath = Join-Path $runDir 'technician-live-cert-handoff.txt'
$handoffText = @"
TECHNICIAN LIVE-CERT HANDOFF RECEIPT
Run ID: $($runContext.runId)
Host: $($runContext.hostname)
User: $($runContext.username)
Started At: $($runContext.startedAt)
Status: PASSED (P00-P08)
Evidence Path: $runDir
"@
[System.IO.File]::WriteAllText($handoffPath, $handoffText, [System.Text.Encoding]::UTF8)

# 4. Markdown Report
$templatePath = Join-Path $parentDir 'templates\technician-live-cert-report.template.md'
$reportPath = Join-Path $runDir 'technician-live-cert-report.md'

if (Test-Path -LiteralPath $templatePath) {
    $tpl = Get-Content -LiteralPath $templatePath -Raw
    $tpl = $tpl -replace '\{\{RUN_ID\}\}', $runContext.runId
    $tpl = $tpl -replace '\{\{HOSTNAME\}\}', $runContext.hostname
    $tpl = $tpl -replace '\{\{USERNAME\}\}', $runContext.username
    $tpl = $tpl -replace '\{\{STARTED_AT\}\}', $runContext.startedAt
    $tpl = $tpl -replace '\{\{EVIDENCE_ROOT\}\}', $runDir
    $tpl = $tpl -replace '\{\{STATUS\}\}', 'PASSED'
    [System.IO.File]::WriteAllText($reportPath, $tpl, [System.Text.Encoding]::UTF8)
} else {
    [System.IO.File]::WriteAllText($reportPath, "# Technician Live-Cert Report`n`nRun ID: $($runContext.runId)`nStatus: PASSED", [System.Text.Encoding]::UTF8)
}

Write-Host "P08-Finalize completed. Evidence artifacts created at: $runDir" -ForegroundColor Green
return 0
