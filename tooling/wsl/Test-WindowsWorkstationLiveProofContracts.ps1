[CmdletBinding()]
param(
    [string]$RootPath = $PSScriptRoot,
    [switch]$InstalledMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Test-Contract {
    param([bool]$Condition, [string]$Name, [string]$Message = "contract failed")
    if ($Condition) {
        [void]$passes.Add($Name)
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    else {
        [void]$failures.Add("${Name}: $Message")
        Write-Host "[FAIL] $Name - $Message" -ForegroundColor Red
    }
}

$RootPath = [IO.Path]::GetFullPath($RootPath)
$proofPath = Join-Path $RootPath "Invoke-WindowsWorkstationLiveProof.ps1"
$commonPath = Join-Path $RootPath "WindowsWorkstationLiveProof.Common.psm1"
$sessionPath = Join-Path $RootPath "Invoke-WindowsWorkstationSessionProof.ps1"
$gnhfPath = Join-Path $RootPath "Invoke-WindowsWorkstationGnhfProof.ps1"
$installerPath = Join-Path $RootPath "Install-WindowsWorkstationLiveProof.ps1"
$validatorPath = Join-Path $RootPath "Test-WindowsWorkstationLiveProofContracts.ps1"
$manifestPath = if ($InstalledMode) {
    Join-Path $RootPath "tmux-gnhf-workstation.json"
}
else {
    Join-Path $RootPath "tmux-gnhf-workstation.example.json"
}
$schemaPath = Join-Path $RootPath "schemas\windows-workstation-live-proof.schema.json"
$cmdPath = if ($InstalledMode) {
    Join-Path $RootPath "Run-WindowsWorkstationLiveProof.cmd"
}
else {
    Join-Path ([IO.Path]::GetFullPath((Join-Path $RootPath "..\.."))) "Run-WindowsWorkstationLiveProof.cmd"
}

$required = @($proofPath, $commonPath, $sessionPath, $gnhfPath, $validatorPath, $manifestPath, $schemaPath, $cmdPath)
if (-not $InstalledMode) { $required += $installerPath }
foreach ($path in $required) {
    Test-Contract (Test-Path -LiteralPath $path -PathType Leaf) "required/$([IO.Path]::GetFileName($path))"
}

foreach ($path in @($proofPath, $commonPath, $sessionPath, $gnhfPath, $validatorPath) + $(if (-not $InstalledMode) { @($installerPath) } else { @() })) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    Test-Contract ($errors.Count -eq 0) "parse/$([IO.Path]::GetFileName($path))" (($errors | ForEach-Object Message) -join "; ")
}

try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    Test-Contract ($manifest.schemaVersion -eq 1) "manifest/schema"
    Test-Contract ([string]$manifest.distribution -match '^[A-Za-z0-9._-]+$') "manifest/distribution"
    Test-Contract ([string]$manifest.workspace.sessionName -match '^[A-Za-z0-9_-]+$') "manifest/session"
}
catch {
    Test-Contract $false "manifest/json" $_.Exception.Message
}

try {
    $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json -Depth 50
    Test-Contract ([string]$schema.'$id' -match 'windows-workstation-live-proof') "schema/id"
    Test-Contract (@($schema.required) -contains "proofLevel") "schema/proof-level"
    Test-Contract (@($schema.required) -contains "proof") "schema/proof-chain"
    Test-Contract (@($schema.required) -contains "handoff") "schema/handoff"
}
catch {
    Test-Contract $false "schema/json" $_.Exception.Message
}

if ((Test-Path -LiteralPath $proofPath -PathType Leaf) -and (Test-Path -LiteralPath $commonPath -PathType Leaf) -and (Test-Path -LiteralPath $sessionPath -PathType Leaf) -and (Test-Path -LiteralPath $gnhfPath -PathType Leaf)) {
    $runtime = @($proofPath, $commonPath, $sessionPath, $gnhfPath) | ForEach-Object { Get-Content -LiteralPath $_ -Raw }
    $runtime = $runtime -join "`n"
    foreach ($token in @(
        "'status','--short'",
        "'diff','--check'",
        'Start-TmuxGnhfWorkspace.ps1',
        'Get-TmuxGnhfWorkspaceStatus.ps1',
        'tmux new-session',
        'tmux send-keys',
        'tmux capture-pane',
        'tmux detach-client',
        '--always-new-process',
        'Wait-ProofCondition',
        'command -v git && command -v gnhf && command -v opencode',
        'opencode auth list',
        'opencode models --refresh',
        'deepseek/deepseek-v4-pro',
        'WSL OpenCode did not report authenticated DeepSeek credentials',
        'OPENCODE_CONFIG_CONTENT',
        "share='disabled'",
        'GNHF_TELEMETRY=0',
        '--worktree',
        '--max-iterations',
        '--max-tokens',
        '--prevent-sleep',
        'disposable-repo',
        'agent-runtime-proof.json',
        'AGENTSWITCHBOARD_GNHF_STARTED',
        'AGENTSWITCHBOARD_GNHF_EXIT',
        'AGENTSWITCHBOARD_GNHF_FINISHED',
        'diff --name-only main...',
        'live-windows-wsl-tmux-gnhf-behavior-observed',
        'live-wezterm-wsl-tmux-session-persistence',
        'readyForAutomatedAgents',
        'readyForSysAdminSuiteTandem',
        'no pixel-level GUI rendering claim'
    )) { Test-Contract ($runtime.Contains($token)) "runtime/token/$token" }
    Test-Contract (-not $runtime.Contains('Read-Host')) 'runtime/no-operator-attestation'
    Test-Contract (-not $runtime.Contains('System.Windows.Forms.SendKeys')) 'runtime/no-focus-sendkeys'
    Test-Contract (-not $runtime.Contains('--push')) 'runtime/no-push'
    Test-Contract (-not $runtime.Contains('reset --hard')) 'runtime/no-destructive-reset'
    Test-Contract (-not $runtime.Contains('wsl --unregister')) 'runtime/no-wsl-reset'
    Test-Contract ($runtime.Contains('destructive_stop_skipped_persistent_session_reuse_is_repo_doctrine')) 'runtime/stop-doctrine'
    Test-Contract ($runtime.Contains('$runtime.runtimeArtifactCollected=$true')) 'runtime/artifact-proof'
    Test-Contract ($runtime.Contains('$runtime.commandAckObserved -and $runtime.behaviorObserved')) 'runtime/full-live-requires-behavior'
    Test-Contract ($runtime.Contains('Stop-Process -Id $proofPid -Force')) 'runtime/proof-wezterm-cleanup'
    Test-Contract ($runtime.Contains('failureReason=$failureReason')) 'runtime/failure-capture'
}

if (-not $InstalledMode -and (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
    $installer = Get-Content -LiteralPath $installerPath -Raw
    foreach ($token in @(
        '[switch]$Apply',
        '[switch]$RunAfterInstall',
        'Core workstation dependency is missing',
        'Start-TmuxGnhfWorkspace.ps1',
        'Get-TmuxGnhfWorkspaceStatus.ps1',
        'state\setup-summary.json',
        'windows-workstation-live-proof.config.json',
        'Run-WindowsWorkstationLiveProof.cmd',
        '-PlanOnly',
        'automaticAuthentication = $false',
        'automaticPush = $false'
    )) {
        Test-Contract ($installer.Contains($token)) "installer/token/$token"
    }
    Test-Contract ($installer.Contains('status --short')) "installer/clean-source-gate"
    Test-Contract (-not $installer.Contains('Remove-Item -Recurse')) "installer/no-broad-delete"
}

if (Test-Path -LiteralPath $cmdPath -PathType Leaf) {
    $cmd = Get-Content -LiteralPath $cmdPath -Raw
    Test-Contract ($cmd.Contains("pwsh.exe -NoLogo -NoProfile")) "cmd/pwsh7"
    if ($InstalledMode) {
        Test-Contract ($cmd.Contains("Invoke-WindowsWorkstationLiveProof.ps1")) "cmd/installed-proof-entrypoint"
        Test-Contract (-not $cmd.Contains("Setup-TmuxGnhfWorkspace.cmd")) "cmd/installed-does-not-redeploy-core"
    }
    else {
        Test-Contract ($cmd.Contains("Setup-TmuxGnhfWorkspace.cmd") -and $cmd.Contains(" apply")) "cmd/deploys-core-first"
        Test-Contract ($cmd.Contains('branch --show-current') -and $cmd.Contains('status --porcelain=v1')) 'cmd/repo-floor-before-deploy'
        Test-Contract ($cmd.Contains('tmux-gnhf-workstation.local.json') -and $cmd.Contains('WORKSTATION_MANIFEST')) 'cmd/reuses-local-manifest'
        Test-Contract ($cmd.Contains("Install-WindowsWorkstationLiveProof.ps1")) "cmd/installs-proof-lane"
        Test-Contract ($cmd.Contains('if "%_setup_code%"=="30"')) "cmd/reboot-resume-gate"
    }
    Test-Contract ($cmd.Contains("pause >nul")) "cmd/failure-visible"
}

$scanPaths = @($proofPath, $commonPath, $sessionPath, $gnhfPath, $manifestPath, $schemaPath, $cmdPath)
if (-not $InstalledMode) { $scanPaths += $installerPath }
$allText = @()
foreach ($path in $scanPaths) {
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $allText += Get-Content -LiteralPath $path -Raw
    }
}
$joined = $allText -join "`n"
foreach ($secretToken in @("DEEPSEEK_API_KEY", "OPENAI_API_KEY", "ANTHROPIC_API_KEY", "access_token", "refresh_token", "sk-")) {
    Test-Contract (-not $joined.Contains($secretToken)) "secrets/absent/$secretToken"
}

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "Result: $($passes.Count) passed / $($failures.Count) failed" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}
Write-Host "Result: $($passes.Count) passed / 0 failed" -ForegroundColor Green
exit 0
