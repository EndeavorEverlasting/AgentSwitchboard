[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$requiredFiles = @(
    "tooling/wsl/Install-TmuxGnhfWorkspace.ps1",
    "tooling/wsl/tmux-gnhf-workstation.example.json",
    "tooling/wsl/wsl-tmux-gnhf-base.example.json",
    "tooling/wsl/scripts/configure-gnhf-workspace.sh",
    "tooling/wsl/templates/wezterm-tmux.lua",
    "tooling/wsl/fixtures/tmux-gnhf-manifest.valid.json",
    "tooling/wsl/fixtures/tmux-gnhf-manifest.invalid.json",
    "tooling/wsl/tests/test_tmux_gnhf_workspace_contracts.py",
    "docs/workstation/tmux-gnhf-other-computer.md"
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
    "tooling/wsl/Install-TmuxGnhfWorkspace.ps1",
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
    $bashScript = Join-Path $repoRoot "tooling/wsl/scripts/configure-gnhf-workspace.sh"
    & $bash.Source -n $bashScript
    Assert-Contract -Condition ($LASTEXITCODE -eq 0) -Message "Bash syntax: configure-gnhf-workspace.sh"
}
else {
    Write-Host "[SKIP] bash syntax: bash_not_available" -ForegroundColor Yellow
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

$bashContent = Get-Content -LiteralPath (Join-Path $repoRoot "tooling/wsl/scripts/configure-gnhf-workspace.sh") -Raw
Assert-Contract -Condition ($bashContent -match 'SHASUMS256\.txt') -Message "official Node checksum verification"
Assert-Contract -Condition ($bashContent -notmatch 'curl\s+[^\r\n]*\|\s*(bash|sh)') -Message "no pipe-to-shell installer"
Assert-Contract -Condition ($bashContent -match 'GNHF_TELEMETRY=0') -Message "telemetry posture is explicit"
Assert-Contract -Condition ($bashContent -match '--worktree' -and $bashContent -match '--max-iterations' -and $bashContent -match '--max-tokens') -Message "GNHF safe wrapper is isolated and capped"

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "Result: $passes passed / $($failures.Count) failed" -ForegroundColor Red
    exit 1
}

Write-Host "Result: $passes passed / 0 failed" -ForegroundColor Green
exit 0
