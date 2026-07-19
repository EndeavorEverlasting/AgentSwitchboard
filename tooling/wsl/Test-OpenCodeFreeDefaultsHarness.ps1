[CmdletBinding()]
param(
    [string]$RepoPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedRepo = (Resolve-Path -LiteralPath $RepoPath -ErrorAction Stop).Path
Set-Location -LiteralPath $resolvedRepo

$passes = [System.Collections.Generic.List[string]]::new()
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$FailureMessage
    )

    if ($Passed) {
        [void]$passes.Add($Name)
    }
    if (-not $Passed) {
        [void]$failures.Add("$Name`: $FailureMessage")
    }
}

function Read-RequiredText {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $resolvedRepo $RelativePath
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    Add-Result -Passed $exists -Name "file/$RelativePath" -FailureMessage "required file is missing"
    if (-not $exists) {
        return $null
    }
    Get-Content -LiteralPath $path -Raw
}

$requiredFiles = @(
    "Repair-OpenCodeFreeDefaults.cmd",
    "tooling/wsl/AGENTS.md",
    ".ai/skills/opencode-free-defaults-repair/SKILL.md",
    "tooling/wsl/harness/opencode-free-defaults/CODEBASE_MAP.md",
    "tooling/wsl/harness/opencode-free-defaults/workflow.json",
    "tooling/wsl/harness/opencode-free-defaults/artifact-catalog.json",
    "tooling/wsl/Invoke-OpenCodeFreeDefaultsRepair.ps1",
    "tooling/wsl/Get-OpenCodeFreeDefaultsHarnessStatus.ps1",
    "tooling/wsl/Test-OpenCodeFreeDefaultsHarness.ps1",
    "tooling/wsl/schemas/opencode-free-defaults-run-context.schema.json",
    "tooling/wsl/schemas/opencode-free-defaults-artifact-registry.schema.json",
    "tooling/wsl/schemas/opencode-free-defaults-handoff.schema.json",
    "tooling/wsl/tests/test_opencode_free_defaults_harness.py"
)
foreach ($relativePath in $requiredFiles) {
    [void](Read-RequiredText -RelativePath $relativePath)
}

$powerShellFiles = @(
    "tooling/wsl/Invoke-OpenCodeFreeDefaultsRepair.ps1",
    "tooling/wsl/Get-OpenCodeFreeDefaultsHarnessStatus.ps1",
    "tooling/wsl/Test-OpenCodeFreeDefaultsHarness.ps1",
    "tooling/wsl/Set-OpenCodeFreeDefaults.ps1"
)
foreach ($relativePath in $powerShellFiles) {
    $path = Join-Path $resolvedRepo $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        continue
    }
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    $errorText = (@($errors | ForEach-Object { $_.Message }) -join "; ")
    Add-Result -Passed (@($errors).Count -eq 0) -Name "powershell/$relativePath" -FailureMessage $errorText
}

$jsonFiles = @(
    "tooling/wsl/harness/opencode-free-defaults/workflow.json",
    "tooling/wsl/harness/opencode-free-defaults/artifact-catalog.json",
    "tooling/wsl/schemas/opencode-free-defaults-run-context.schema.json",
    "tooling/wsl/schemas/opencode-free-defaults-artifact-registry.schema.json",
    "tooling/wsl/schemas/opencode-free-defaults-handoff.schema.json"
)
foreach ($relativePath in $jsonFiles) {
    $text = Read-RequiredText -RelativePath $relativePath
    if ($null -eq $text) {
        continue
    }
    try {
        [void]($text | ConvertFrom-Json)
        Add-Result -Passed $true -Name "json/$relativePath" -FailureMessage ""
    }
    catch {
        Add-Result -Passed $false -Name "json/$relativePath" -FailureMessage $_.Exception.Message
    }
}

$workflow = Get-Content -LiteralPath (Join-Path $resolvedRepo "tooling/wsl/harness/opencode-free-defaults/workflow.json") -Raw | ConvertFrom-Json
Add-Result -Passed ($workflow.workflowId -eq "opencode-free-defaults-repair") -Name "workflow/id" -FailureMessage "unexpected workflow ID"
Add-Result -Passed ($workflow.entrypoints.oneClick -eq "Repair-OpenCodeFreeDefaults.cmd") -Name "workflow/one-click" -FailureMessage "root launcher is not registered"
Add-Result -Passed ($workflow.entrypoints.orchestrator -eq "tooling/wsl/Invoke-OpenCodeFreeDefaultsRepair.ps1") -Name "workflow/orchestrator" -FailureMessage "orchestrator is not registered"
Add-Result -Passed ($workflow.entrypoints.status -eq "tooling/wsl/Get-OpenCodeFreeDefaultsHarnessStatus.ps1") -Name "workflow/status" -FailureMessage "read-only status probe is not registered"
Add-Result -Passed (@($workflow.validators).Count -ge 4) -Name "workflow/validators" -FailureMessage "focused and broad validators are incomplete"
Add-Result -Passed (-not [bool]$workflow.localHooks.installedByDefault) -Name "workflow/hook-boundary" -FailureMessage "mutating workflow must not install a default local hook"
Add-Result -Passed (-not [bool]$workflow.outputPolicy.tracked) -Name "workflow/output-policy" -FailureMessage "runtime artifacts must remain outside Git"

$catalog = Get-Content -LiteralPath (Join-Path $resolvedRepo "tooling/wsl/harness/opencode-free-defaults/artifact-catalog.json") -Raw | ConvertFrom-Json
$roles = @($catalog.artifacts | ForEach-Object { [string]$_.role })
foreach ($role in @("run-context", "artifact-registry", "effective-config", "operator-report", "final-handoff")) {
    Add-Result -Passed ($roles -contains $role) -Name "artifact/$role" -FailureMessage "artifact role missing"
}
Add-Result -Passed (-not [bool]$catalog.tracked) -Name "artifact/untracked" -FailureMessage "runtime artifacts must remain outside Git"

$orchestratorText = Read-RequiredText -RelativePath "tooling/wsl/Invoke-OpenCodeFreeDefaultsRepair.ps1"
$operationTokens = @(
    '$sourceStatus = Invoke-BoundedNative',
    '$fetch = Invoke-BoundedNative',
    '$ancestorProbe = Invoke-BoundedNative',
    '$add = Invoke-BoundedNative',
    '$installer = Invoke-BoundedNative',
    '$inspection = Invoke-BoundedNative',
    'run-context.json',
    'artifact-registry.json',
    'operator-report.md',
    'final-handoff.json',
    'effective-opencode-config.json'
)
foreach ($token in $operationTokens) {
    Add-Result -Passed ($orchestratorText.Contains($token)) -Name "orchestrator/$token" -FailureMessage "required workflow operation or artifact is missing"
}

$orchestratorForbidden = @(
    "reset --hard",
    "git clean",
    "git push --force",
    "DEEPSEEK_API_KEY",
    "OPENAI_API_KEY",
    "ANTHROPIC_API_KEY",
    "C:\Users\Cheex",
    "deepseek/deepseek-v4-pro"
)
foreach ($token in $orchestratorForbidden) {
    Add-Result -Passed (-not $orchestratorText.Contains($token)) -Name "orchestrator-forbidden/$token" -FailureMessage "forbidden workflow behavior is present"
}

$agentsText = Read-RequiredText -RelativePath "tooling/wsl/AGENTS.md"
$skillText = Read-RequiredText -RelativePath ".ai/skills/opencode-free-defaults-repair/SKILL.md"
$guidanceText = ($agentsText + "`n" + $skillText).ToLowerInvariant()
foreach ($token in @("isolated detached worktree", "run context", "artifact registry", "operator report", "final handoff")) {
    Add-Result -Passed ($guidanceText.Contains($token)) -Name "guidance/$token" -FailureMessage "required harness guidance is missing"
}

$statusText = Read-RequiredText -RelativePath "tooling/wsl/Get-OpenCodeFreeDefaultsHarnessStatus.ps1"
Add-Result -Passed ($statusText.Contains("git status --short")) -Name "status/git" -FailureMessage "read-only Git inspection is missing"
Add-Result -Passed ($statusText.Contains('cat "$HOME/.config/opencode/opencode.json"')) -Name "status/config" -FailureMessage "read-only configuration inspection is missing"
foreach ($token in @("apt-get install", "worktree add", "Start-Process")) {
    Add-Result -Passed (-not $statusText.Contains($token)) -Name "status-forbidden/$token" -FailureMessage "status probe contains mutation behavior"
}

$cmdText = Read-RequiredText -RelativePath "Repair-OpenCodeFreeDefaults.cmd"
Add-Result -Passed ($cmdText.Contains('cd /d "%~dp0"')) -Name "cmd/directory-first" -FailureMessage "root CMD does not enter its repository directory"
Add-Result -Passed ($cmdText.Contains("Invoke-OpenCodeFreeDefaultsRepair.ps1")) -Name "cmd/delegation" -FailureMessage "root CMD does not delegate to the canonical orchestrator"

Write-Host "OPENCODE FREE-DEFAULTS HARNESS CONTRACT" -ForegroundColor Cyan
foreach ($failure in $failures) {
    Write-Host "[FAIL] $failure" -ForegroundColor Red
}
foreach ($pass in $passes) {
    Write-Host "[PASS] $pass" -ForegroundColor Green
}
Write-Host ""
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)

if ($failures.Count -gt 0) {
    exit 1
}
exit 0
