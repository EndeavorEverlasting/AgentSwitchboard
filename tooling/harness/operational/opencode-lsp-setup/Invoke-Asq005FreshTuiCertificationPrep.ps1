<#
.SYNOPSIS
  ASQ-005 G0 floor + G1 Configure prep for Admin Box 1 fresh-TUI certification.

.DESCRIPTION
  Reusable executable for the recurring Admin Box 1 prep sequence formerly
  carried only as a WORK_QUEUE snippet. Completes G0 repository-floor checks,
  optionally runs Configure (G1), and prints the G2-G8 operator checklist.

  Configure success never marks ASQ-005 DONE. Live TUI hover/definition/references
  remain operator-observed on Admin Box 1. This script never writes runtime-smoke
  receipts and never claims LSP_RUNTIME_SMOKE_TEST: PASS.
#>
[CmdletBinding()]
param(
    [string]$RepoPath,
    [switch]$SkipConfigure,
    [string]$LiveFloorCommit = '24cce9e321a4913dda32f21a2d51a599dd0e4bb4',
    [string]$HeadlessBaselineId = '20260912T194619Z-e3f423df',
    [string]$ModelId = 'opencode/nemotron-3-ultra-free'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$global:LASTEXITCODE = 0

function Write-Asq005Status {
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Value)
    Write-Host ("{0}={1}" -f $Key, $Value)
}

function Stop-Asq005Prep {
    param([Parameter(Mandatory)][string]$Code, [Parameter(Mandatory)][string]$Message)
    Write-Asq005Status -Key 'ASQ005_FAILURE_CODE' -Value $Code
    Write-Asq005Status -Key 'ASQ005_LIVE_PROOF_STATUS' -Value 'UNPROVEN'
    Write-Asq005Status -Key 'ASQ005_CONFIGURE_IS_NOT_DONE' -Value 'true'
    Write-Asq005Status -Key 'ASQ005_DONE' -Value 'false'
    Write-Host ("ASQ005_ERROR={0}|{1}" -f $Code, $Message)
    exit 1
}

function Get-NormalizedOrigin {
    param([Parameter(Mandatory)][string]$OriginUrl)
    $value = $OriginUrl.Trim()
    # Strip embedded credentials without echoing them.
    $value = [regex]::Replace($value, '^https://[^/@]+@', 'https://')
    $value = [regex]::Replace($value, '^http://[^/@]+@', 'http://')
    $value = ($value -replace '\.git$', '').TrimEnd('/')
    return $value
}

function Get-NormalizedLocalPath {
    param([Parameter(Mandatory)][string]$PathValue)
    # Git on Windows often emits forward slashes from rev-parse; Resolve-Path uses backslashes.
    $value = $PathValue.Trim().TrimEnd('\', '/')
    $value = $value -replace '/', '\'
    if ($env:OS -like '*Windows*') {
        return $value.ToLowerInvariant()
    }
    return $value
}

$canonicalOrigin = 'https://github.com/EndeavorEverlasting/AgentSwitchboard'
$fixtureRel = 'tests/test_technician_live_cert_surface.py'
$symbol = 'read_text'
$contractRel = 'tooling/harness/operational/opencode-lsp-setup/asq005-runtime-gates.contract.json'

Write-Asq005Status -Key 'ASQ005_LIVE_PROOF_STATUS' -Value 'UNPROVEN'
Write-Asq005Status -Key 'ASQ005_CONFIGURE_IS_NOT_DONE' -Value 'true'
Write-Asq005Status -Key 'ASQ005_DONE' -Value 'false'

if ([string]::IsNullOrWhiteSpace($RepoPath)) {
    if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        Stop-Asq005Prep -Code 'USERPROFILE_REQUIRED' -Message 'Canonical Live root requires USERPROFILE, or pass -RepoPath.'
    }
    $RepoPath = Join-Path $env:USERPROFILE 'dev\AgentSwitchBoard-Live'
}

if (-not (Test-Path -LiteralPath $RepoPath -PathType Container)) {
    Stop-Asq005Prep -Code 'LIVE_CHECKOUT_MISSING' -Message ("Canonical Live checkout is missing at {0}" -f $RepoPath)
}

$RepoPath = (Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).Path
Set-Location -LiteralPath $RepoPath

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Stop-Asq005Prep -Code 'GIT_NOT_FOUND' -Message 'Git is required for ASQ-005 G0 floor checks.'
}

$root = (& git rev-parse --show-toplevel 2>$null | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) {
    Stop-Asq005Prep -Code 'NOT_A_GIT_REPOSITORY' -Message 'ASQ-005 requires a Git checkout at the Live root.'
}
$root = $root.Trim()
if ((Get-NormalizedLocalPath -PathValue $root) -ne (Get-NormalizedLocalPath -PathValue $RepoPath)) {
    Stop-Asq005Prep -Code 'WRONG_REPOSITORY_ROOT' -Message ("actual={0}|expected={1}" -f $root, $RepoPath)
}

$origin = (& git remote get-url origin 2>$null | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($origin)) {
    Stop-Asq005Prep -Code 'ORIGIN_UNRESOLVED' -Message 'Unable to read git remote origin.'
}
$originNormalized = Get-NormalizedOrigin -OriginUrl $origin
if ($originNormalized -ne $canonicalOrigin) {
    Stop-Asq005Prep -Code 'WRONG_REPOSITORY_ORIGIN' -Message $originNormalized
}

& git fetch --all --prune --tags
if ($LASTEXITCODE -ne 0) {
    Stop-Asq005Prep -Code 'FETCH_FAILED' -Message 'git fetch --all --prune --tags failed.'
}

$branch = (& git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -ne 'main') {
    Stop-Asq005Prep -Code 'NOT_ON_MAIN' -Message ("ASQ-005 G0 requires branch main; actual={0}" -f $branch)
}

& git pull --ff-only origin main
if ($LASTEXITCODE -ne 0) {
    Stop-Asq005Prep -Code 'MAIN_NOT_CLEAN_BEHIND_ONLY' -Message 'git pull --ff-only origin main failed; reconcile without force.'
}

if ((& git status --porcelain) ) {
    Stop-Asq005Prep -Code 'WORKTREE_NOT_CLEAN' -Message 'ASQ-005 G0 requires a clean Live worktree.'
}

$head = (& git rev-parse HEAD).Trim()
& git merge-base --is-ancestor $LiveFloorCommit HEAD
if ($LASTEXITCODE -ne 0) {
    Stop-Asq005Prep -Code 'MAIN_MISSING_ASQ005_FLOOR' -Message ("head={0}|floor={1}" -f $head, $LiveFloorCommit)
}

$contractPath = Join-Path $RepoPath $contractRel
if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    Stop-Asq005Prep -Code 'ASQ005_CONTRACT_MISSING' -Message $contractRel
}
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
if ([string]$contract.liveProofStatus -ne 'UNPROVEN') {
    Stop-Asq005Prep -Code 'ASQ005_CONTRACT_LIVE_STATUS_DRIFT' -Message 'Tracked contract liveProofStatus must remain UNPROVEN until Admin Box 1 observes live PASS.'
}
if (-not [bool]$contract.configureNeverPromotesToDone) {
    Stop-Asq005Prep -Code 'ASQ005_CONTRACT_CONFIGURE_PROMOTION_DRIFT' -Message 'Tracked contract must keep configureNeverPromotesToDone=true.'
}

$frontier = Join-Path $RepoPath 'scripts\Get-RepositoryWorkLedgerFrontier.ps1'
if (-not (Test-Path -LiteralPath $frontier -PathType Leaf)) {
    Stop-Asq005Prep -Code 'FRONTIER_SCRIPT_MISSING' -Message 'scripts/Get-RepositoryWorkLedgerFrontier.ps1'
}
& pwsh -NoLogo -NoProfile -File $frontier -Json
if ($LASTEXITCODE -ne 0) {
    Stop-Asq005Prep -Code 'FRONTIER_FAILED' -Message 'Work-ledger frontier probe failed.'
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $python) {
    Stop-Asq005Prep -Code 'PYTHON_REQUIRED' -Message 'python or python3 is required for ASQ-005 portable contract tests.'
}
& $python.Source -m unittest tests.test_asq005_canonical_runtime_floor tests.test_opencode_lsp_harness -q
if ($LASTEXITCODE -ne 0) {
    Stop-Asq005Prep -Code 'ASQ005_UNIT_TESTS_FAILED' -Message 'Portable ASQ-005 / OpenCode LSP harness tests failed.'
}

Write-Asq005Status -Key 'ASQ005_G0' -Value 'PASS'
Write-Asq005Status -Key 'ASQ005_HEAD' -Value $head
Write-Asq005Status -Key 'ASQ005_BASELINE' -Value $HeadlessBaselineId
Write-Asq005Status -Key 'ASQ005_FIXTURE' -Value $fixtureRel
Write-Asq005Status -Key 'ASQ005_SYMBOL' -Value $symbol

$configureExit = 0
$runDir = $null
$launcherCmd = $null

if ($SkipConfigure) {
    Write-Asq005Status -Key 'ASQ005_G1' -Value 'SKIPPED_BY_OPERATOR'
}
elseif ($env:OS -ne 'Windows_NT') {
    Write-Asq005Status -Key 'ASQ005_G1' -Value 'FAIL_CLOSED'
    Write-Asq005Status -Key 'ASQ005_FAILURE_CODE' -Value 'WINDOWS_REQUIRED'
    Write-Host 'ASQ005_PREP: G0 static floor checks passed on a non-Windows host; Configure (G1) and live TUI (G2-G8) require Admin Box 1 Windows.'
    Write-Asq005Status -Key 'ASQ005_LIVE_PROOF_STATUS' -Value 'UNPROVEN'
    Write-Asq005Status -Key 'ASQ005_CONFIGURE_IS_NOT_DONE' -Value 'true'
    Write-Asq005Status -Key 'ASQ005_DONE' -Value 'false'
    exit 2
}
else {
    $env:OPENCODE_EXPERIMENTAL_LSP_TOOL = 'true'
    $configureScript = Join-Path $RepoPath 'tooling\harness\operational\opencode-lsp-setup\Invoke-OpenCodeLspWorkstationSetup.ps1'
    if (-not (Test-Path -LiteralPath $configureScript -PathType Leaf)) {
        Stop-Asq005Prep -Code 'CONFIGURE_SCRIPT_MISSING' -Message $configureScript
    }
    & pwsh -NoLogo -NoProfile -File $configureScript -Mode Configure -RepoPath $RepoPath -ModelId $ModelId
    $configureExit = $LASTEXITCODE
    if ($configureExit -ne 0) {
        Write-Asq005Status -Key 'ASQ005_G1' -Value 'FAIL'
        Write-Asq005Status -Key 'ASQ005_LIVE_PROOF_STATUS' -Value 'UNPROVEN'
        Write-Asq005Status -Key 'ASQ005_CONFIGURE_IS_NOT_DONE' -Value 'true'
        Write-Asq005Status -Key 'ASQ005_DONE' -Value 'false'
        exit $configureExit
    }

    $runsRoot = Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\opencode-lsp\runs'
    if (-not (Test-Path -LiteralPath $runsRoot -PathType Container)) {
        Stop-Asq005Prep -Code 'CONFIGURE_RUN_ROOT_MISSING' -Message $runsRoot
    }
    $runDir = Get-ChildItem -LiteralPath $runsRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $runDir) {
        Stop-Asq005Prep -Code 'CONFIGURE_RUN_MISSING' -Message 'Configure reported success but no immutable run directory was found.'
    }
    $launcherCmd = Join-Path $runDir.FullName 'Open-AgentSwitchboard-OpenCode-Lsp.cmd'
    if (-not (Test-Path -LiteralPath $launcherCmd -PathType Leaf)) {
        Stop-Asq005Prep -Code 'LAUNCHER_MISSING' -Message $launcherCmd
    }
    Write-Asq005Status -Key 'ASQ005_G1' -Value 'PASS_CONFIGURE_ONLY'
    Write-Asq005Status -Key 'ASQ005_CONFIGURE_RUN' -Value $runDir.FullName
    Write-Asq005Status -Key 'ASQ005_LAUNCHER' -Value $launcherCmd
}

Write-Host ''
Write-Host 'ASQ005_PREP: Configure/CI is G1 only and never ASQ-005 DONE.'
Write-Host 'ASQ005_PREP: LIVE_RUNTIME_PROOF remains UNPROVEN until G2-G8 pass on Admin Box 1.'
Write-Host 'ASQ005_OPERATOR_CHECKLIST_G2_G8:'
Write-Host ("  G2 Launch fresh TUI: {0}" -f $(if ($launcherCmd) { $launcherCmd } else { '<generated Open-AgentSwitchboard-OpenCode-Lsp.cmd>' }))
Write-Host ("  G3 Open fixture exactly once: {0}" -f $fixtureRel)
Write-Host ("  G4 LSP-only hover -> goToDefinition -> findReferences on {0}; nonLspSemanticFallbackUsed=No" -f $symbol)
Write-Host ("  G5 Classify vs headless baseline {0}" -f $HeadlessBaselineId)
Write-Host '  G6 Write local untracked opencode-lsp-runtime-smoke.json/.md under the Configure run directory'
Write-Host '  G7 pwsh -NoLogo -NoProfile -File .\scripts\Test-OpenCodeLspHarness.ps1 -RootPath <Live>; git diff --check'
Write-Host '  G8 Mark ASQ-005 DONE only when verdict is exactly LSP_RUNTIME_SMOKE_TEST: PASS'
Write-Asq005Status -Key 'ASQ005_LIVE_PROOF_STATUS' -Value 'UNPROVEN'
Write-Asq005Status -Key 'ASQ005_CONFIGURE_IS_NOT_DONE' -Value 'true'
Write-Asq005Status -Key 'ASQ005_DONE' -Value 'false'
exit 0
