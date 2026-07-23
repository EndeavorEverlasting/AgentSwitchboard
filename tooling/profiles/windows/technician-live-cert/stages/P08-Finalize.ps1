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

Write-Host 'Running P08-Finalize stage...' -ForegroundColor Yellow

$runContext = Get-TechnicianLiveCertRunContext -RunId $RunId
$runDir = Get-TechnicianLiveCertRunDir -RunId $runContext.runId

$requiredPredecessors = @('P00', 'P01', 'P02', 'P03', 'P04', 'P05', 'P06', 'P07')
$notPassed = @($requiredPredecessors | Where-Object { $runContext.stages.$_.status -ne 'passed' })
if ($notPassed.Count -gt 0) {
    throw "P08 cannot finalize because required stages are not passed: $($notPassed -join ', ')."
}

# P08 is executing only after all dependency gates have passed. Record its
# anticipated success in the report context; the dispatcher writes the final
# authoritative stage result immediately after this script returns 0.
$completedAt = (Get-Date).ToUniversalTime().ToString('o')
$runContext.stages.P08.name = 'Finalize'
$runContext.stages.P08.status = 'passed'
$runContext.stages.P08.startedAt = $completedAt
$runContext.stages.P08.completedAt = $completedAt
$runContext.stages.P08.exitCode = 0
$runContext.stages.P08.evidencePath = $StageDir
$runContext.stages.P08.classification = 'passed'
$runContext.status = 'completed'
$runContext.completedAt = $completedAt

$summaryPath = Join-Path $runDir 'technician-live-cert-summary.json'
Write-TechnicianLiveCertJson -Object $runContext -Path $summaryPath

$matrixPath = Join-Path $runDir 'technician-live-cert-stage-matrix.csv'
$rows = foreach ($prop in $runContext.stages.PSObject.Properties) {
    $s = $prop.Value
    [pscustomobject]@{
        StageId = $s.stageId
        Name = $s.name
        Status = $s.status
        StartedAt = $s.startedAt
        CompletedAt = $s.completedAt
        ExitCode = $s.exitCode
        Classification = $s.classification
    }
}
$rows | Export-Csv -LiteralPath $matrixPath -NoTypeInformation -Encoding utf8

$handoffPath = Join-Path $runDir 'technician-live-cert-handoff.txt'
$handoffText = @"
TECHNICIAN LIVE-CERT HANDOFF RECEIPT
Run ID: $($runContext.runId)
Host: $($runContext.hostname)
User: $($runContext.username)
Repository: $($runContext.repositoryRoot)
Branch: $($runContext.branch)
Head: $($runContext.head)
Started At: $($runContext.startedAt)
Completed At: $completedAt
Core Status: PASSED (P00-P08)
Evidence Path: $runDir
Proof Ceiling: Core setup, command, launcher-observation, and repeatability gates recorded. Provider authentication/response remains separate unless explicitly observed and recorded.
"@
[System.IO.File]::WriteAllText($handoffPath, $handoffText, [System.Text.UTF8Encoding]::new($false))

$templatePath = Join-Path $parentDir 'templates\technician-live-cert-report.template.md'
$reportPath = Join-Path $runDir 'technician-live-cert-report.md'
if (Test-Path -LiteralPath $templatePath -PathType Leaf) {
    $tpl = Get-Content -LiteralPath $templatePath -Raw
    $tpl = $tpl -replace '\{\{RUN_ID\}\}', $runContext.runId
    $tpl = $tpl -replace '\{\{HOSTNAME\}\}', $runContext.hostname
    $tpl = $tpl -replace '\{\{USERNAME\}\}', $runContext.username
    $tpl = $tpl -replace '\{\{STARTED_AT\}\}', $runContext.startedAt
    $tpl = $tpl -replace '\{\{EVIDENCE_ROOT\}\}', $runDir
    $tpl = $tpl -replace '\{\{STATUS\}\}', 'PASSED'
    [System.IO.File]::WriteAllText($reportPath, $tpl, [System.Text.UTF8Encoding]::new($false))
} else {
    [System.IO.File]::WriteAllText($reportPath, "# Technician Live-Cert Report`n`nRun ID: $($runContext.runId)`nStatus: PASSED", [System.Text.UTF8Encoding]::new($false))
}

Write-Host "P08-Finalize completed. Evidence artifacts created at: $runDir" -ForegroundColor Green
return 0
