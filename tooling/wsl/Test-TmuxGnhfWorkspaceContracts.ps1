[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$requiredFiles = @(
    "Setup-TmuxGnhfWorkspace.cmd",
    "tooling/wsl/Start-TmuxGnhfWorkspaceSetup.ps1",
    "tooling/wsl/Install-TmuxGnhfWorkspace.ps1",
    "tooling/wsl/Invoke-TmuxGnhfRuntimeProof.ps1",
    "tooling/wsl/tmux-gnhf-workstation.example.json",
    "tooling/wsl/wsl-tmux-gnhf-base.example.json",
    "tooling/wsl/scripts/bootstrap-agent-workstation.sh",
    "tooling/wsl/scripts/configure-gnhf-workspace.sh",
    "tooling/wsl/templates/wezterm-tmux.lua",
    "tooling/wsl/fixtures/tmux-gnhf-manifest.valid.json",
    "tooling/wsl/fixtures/tmux-gnhf-manifest.invalid.json",
    "tooling/wsl/tests/test_tmux_gnhf_workspace_contracts.py",
    "docs/workstation/tmux-gnhf-other-computer.md",
    "docs/workstation/tmux-gnhf-technician-quickstart.md"
)

$failures = [System.Collections.Generic.List[string]]::new()
$passes = 0

function Assert-Contract {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    if ($Condition) {
        $script:passes++
        Write-Host "[PASS] $Message" -ForegroundColor Green
    }
    else {
        $script:failures.Add($Message)
        Write-Host "[FAIL] $Message" -ForegroundColor Red
    }
}

foreach ($relativePath in $requiredFiles) {
    $path = Join-Path $repoRoot $relativePath
    Assert-Contract -Condition (Test-Path -LiteralPath $path -PathType Leaf) -Message "required file: $relativePath"
}

foreach ($relativePath in @(
    "tooling/wsl/Start-TmuxGnhfWorkspaceSetup.ps1",
    "tooling/wsl/Install-TmuxGnhfWorkspace.ps1",
    "tooling/wsl/Invoke-TmuxGnhfRuntimeProof.ps1",
    "tooling/wsl/Test-TmuxGnhfWorkspaceContracts.ps1"
)) {
    $path = Join-Path $repoRoot $relativePath
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    Assert-Contract -Condition ($parseErrors.Count -eq 0) -Message "PowerShell parse: $relativePath"
    if ($parseErrors.Count -gt 0) {
        foreach ($parseError in $parseErrors) {
            Write-Host "  $($parseError.Message)" -ForegroundColor DarkRed
        }
    }
}

foreach ($relativePath in @(
    "tooling/wsl/tmux-gnhf-workstation.example.json",
    "tooling/wsl/wsl-tmux-gnhf-base.example.json",
    "tooling/wsl/fixtures/tmux-gnhf-manifest.valid.json",
    "tooling/wsl/fixtures/tmux-gnhf-manifest.invalid.json"
)) {
    $path = Join-Path $repoRoot $relativePath
    try {
        [void](Get-Content -LiteralPath $path -Raw | ConvertFrom-Json)
        Assert-Contract -Condition $true -Message "JSON parse: $relativePath"
    }
    catch {
        Assert-Contract -Condition $false -Message "JSON parse: $relativePath"
    }
}

$bash = Get-Command bash -ErrorAction SilentlyContinue
if ($bash) {
    foreach ($relativePath in @(
        "tooling/wsl/scripts/bootstrap-agent-workstation.sh",
        "tooling/wsl/scripts/configure-gnhf-workspace.sh"
    )) {
        $bashScript = Join-Path $repoRoot $relativePath
        $bashExitCode = 1
        if ($IsWindows) {
            $normalizedBash = (Get-Content -LiteralPath $bashScript -Raw).Replace("`r`n", "`n")
            $normalizedBash | & $bash.Source -n
            $bashExitCode = if ($?) { 0 } else { 1 }
        }
        else {
            & $bash.Source -n $bashScript
            $bashExitCode = if ($?) { 0 } else { 1 }
        }
        Assert-Contract -Condition ($bashExitCode -eq 0) -Message "Bash syntax: $relativePath"
    }
}
else {
    Write-Host "[SKIP] Bash syntax: bash_not_available" -ForegroundColor Yellow
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command python3 -ErrorAction SilentlyContinue
}
if ($python) {
    $pythonTest = Join-Path $repoRoot "tooling/wsl/tests/test_tmux_gnhf_workspace_contracts.py"
    & $python.Source $pythonTest
    Assert-Contract -Condition ($LASTEXITCODE -eq 0) -Message "Python contract suite"
}
else {
    Write-Host "[SKIP] Python contracts: python_not_available" -ForegroundColor Yellow
}

$installer = Get-Content -LiteralPath (Join-Path $repoRoot "tooling/wsl/Install-TmuxGnhfWorkspace.ps1") -Raw
Assert-Contract -Condition ($installer -match '\$planMode = -not \$Apply') -Message "plan mode is default"
Assert-Contract -Condition ($installer -match 'wezterm-gui\.exe') -Message "launcher targets WezTerm GUI"
Assert-Contract -Condition ($installer -match 'ConfirmImpact = ''High''') -Message "Stop is high-impact and confirmed"
Assert-Contract -Condition ($installer -notmatch '--unregister') -Message "no WSL unregister"
Assert-Contract -Condition ($installer -notmatch 'reset --hard') -Message "no destructive Git reset"

$guided = Get-Content -LiteralPath (Join-Path $repoRoot "tooling/wsl/Start-TmuxGnhfWorkspaceSetup.ps1") -Raw
Assert-Contract -Condition ($guided -match 'ValidateSet\("Guided", "Plan", "Apply"\)') -Message "guided launcher exposes bounded modes"
Assert-Contract -Condition ($guided -match 'Start-Process -FilePath "dism\.exe" -Verb RunAs') -Message "Windows feature enablement is explicit and elevated"
Assert-Contract -Condition ($guided -match 'Read-Host "Confirmation"' -and $guided -match 'INSTALL') -Message "apply requires exact operator confirmation"
Assert-Contract -Condition ($guided -match 'setup-runs' -and $guided -match 'operator-summary\.json') -Message "guided setup writes durable local evidence"
Assert-Contract -Condition ($guided -match '"-u", "root"' -or $guided -match '-u root') -Message "Linux package preparation has a root-only phase"
Assert-Contract -Condition ($guided -match 'skipPackageInstallation') -Message "user setup suppresses duplicate sudo package work"
Assert-Contract -Condition ($guided -match 'Get-TmuxGnhfWorkspaceStatus\.ps1') -Message "guided apply validates the generated workspace"
Assert-Contract -Condition ($guided -match 'Replace\(\[string\]\[char\]0, \[string\]::Empty\)') -Message "guided setup removes WSL NUL separators without ambiguous char replacement"
Assert-Contract -Condition ($guided -notmatch '--unregister|reset --hard') -Message "guided setup forbids destructive WSL or Git reset"
Assert-Contract -Condition ($guided -notmatch '(?im)^\s*(?:&\s*)?git(?:\.exe)?\s+push\b') -Message "guided setup does not execute Git push"
Assert-Contract -Condition ($guided -notmatch 'api[_-]?key|access[_-]?token|refresh[_-]?token') -Message "guided setup does not collect authentication secrets"

$rootCmd = Get-Content -LiteralPath (Join-Path $repoRoot "Setup-TmuxGnhfWorkspace.cmd") -Raw
Assert-Contract -Condition ($rootCmd -match 'Start-TmuxGnhfWorkspaceSetup\.ps1') -Message "root CMD delegates to the guided orchestrator"
Assert-Contract -Condition ($rootCmd -match 'pwsh\.exe -NoLogo -NoProfile') -Message "root CMD uses PowerShell 7 without profile side effects"
Assert-Contract -Condition ($rootCmd -match 'pause >nul') -Message "root CMD keeps failures visible"

$userBootstrap = Get-Content -LiteralPath (Join-Path $repoRoot "tooling/wsl/scripts/bootstrap-agent-workstation.sh") -Raw
Assert-Contract -Condition ($userBootstrap -match 'skipPackageInstallation') -Message "WSL bootstrap accepts prepared package state"
Assert-Contract -Condition ($userBootstrap -match 'prepared by the Windows guided orchestrator') -Message "prepared package state is reported honestly"

$runtimeProof = Get-Content -LiteralPath (Join-Path $repoRoot "tooling/wsl/Invoke-TmuxGnhfRuntimeProof.ps1") -Raw
Assert-Contract -Condition ($runtimeProof -match 'git.+status.+--short' -or $runtimeProof -match '"status", "--short"') -Message "runtime proof requires a clean repository floor"
Assert-Contract -Condition ($runtimeProof -match 'Test-TmuxGnhfWorkspaceContracts\.ps1') -Message "runtime proof runs targeted validation first"
Assert-Contract -Condition ($runtimeProof -match 'Start-TmuxGnhfWorkspace\.ps1') -Message "runtime proof uses repo-owned launcher"
Assert-Contract -Condition ($runtimeProof -match 'Get-TmuxGnhfWorkspaceStatus\.ps1') -Message "runtime proof uses repo-owned status collector"
Assert-Contract -Condition ($runtimeProof -match 'Wait-ForCondition') -Message "runtime waits are bounded"
Assert-Contract -Condition ($runtimeProof -match 'surfaceReadyObserved' -and $runtimeProof -match 'behaviorObserved') -Message "surface and behavior observation remain distinct"
Assert-Contract -Condition ($runtimeProof -match 'persistenceObserved' -and $runtimeProof -match 'reattachObserved') -Message "detach persistence and reattach are separate gates"
Assert-Contract -Condition ($runtimeProof -match 'RoutingEvidencePath') -Message "runtime proof can consume concurrent routing evidence"
Assert-Contract -Condition ($runtimeProof -match 'selectedModel' -and $runtimeProof -match 'tokenAvailability' -and $runtimeProof -match 'switchReason') -Message "model and token routing evidence is normalized without owning policy"
Assert-Contract -Condition ($runtimeProof -match 'evidenceHash') -Message "external routing evidence is referenced by hash"
Assert-Contract -Condition ($runtimeProof -notmatch 'api[_-]?key|access[_-]?token|refresh[_-]?token|oauth') -Message "runtime proof does not collect authentication secrets"
Assert-Contract -Condition ($runtimeProof -match 'live-runtime-observed' -and $runtimeProof -match 'launcher-and-command-ack') -Message "proof levels distinguish ACK from live observation"

$bashContent = Get-Content -LiteralPath (Join-Path $repoRoot "tooling/wsl/scripts/configure-gnhf-workspace.sh") -Raw
Assert-Contract -Condition ($bashContent -match 'SHASUMS256\.txt') -Message "official Node checksum verification"
Assert-Contract -Condition ($bashContent -notmatch 'curl\s+[^\r\n]*\|\s*(bash|sh)') -Message "no pipe-to-shell installer"
Assert-Contract -Condition ($bashContent -match 'GNHF_TELEMETRY=0') -Message "telemetry posture is explicit"
Assert-Contract -Condition ($bashContent -match '--worktree' -and $bashContent -match '--max-iterations' -and $bashContent -match '--max-tokens') -Message "GNHF safe wrapper is isolated and capped"

$quickStart = Get-Content -LiteralPath (Join-Path $repoRoot "docs/workstation/tmux-gnhf-technician-quickstart.md") -Raw
Assert-Contract -Condition ($quickStart -match 'Setup-TmuxGnhfWorkspace\.cmd') -Message "technician guide names the one-click launcher"
Assert-Contract -Condition ($quickStart -match 'type INSTALL' -and $quickStart -match 'same CMD') -Message "technician guide explains confirmation and resume"
Assert-Contract -Condition ($quickStart -match 'operator-summary\.json' -and $quickStart -match 'Technician completion checklist') -Message "technician guide explains evidence and acceptance"

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "Result: $passes passed / $($failures.Count) failed" -ForegroundColor Red
    exit 1
}

Write-Host "Result: $passes passed / 0 failed" -ForegroundColor Green
exit 0
