[CmdletBinding()]
param(
    [string]$RootPath = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Add-CheckResult {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][AllowEmptyString()][string]$FailureMessage = ""
    )

    if ($Passed) {
        [void]$passes.Add($Name)
    }
    else {
        [void]$failures.Add("$Name`: $FailureMessage")
    }
}

function Get-FileText {
    param([Parameter(Mandatory)][string]$RelativePath)

    $path = Join-Path $RootPath $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        [void]$failures.Add("required-file/$RelativePath`: file is missing")
        return $null
    }

    return Get-Content -LiteralPath $path -Raw
}

$requiredFiles = @(
    "GnhfFleet.Paths.ps1",
    "Install-AgentSwitchboardGnhf.ps1",
    "Start-AgentSwitchboard.ps1",
    "Start-GnhfSprint.ps1",
    "Start-GnhfFleet.ps1",
    "Get-GnhfFleetStatus.ps1",
    "Test-GnhfFleetContracts.ps1",
    "gnhf-fleet.example.json",
    "README.md"
)

foreach ($relativePath in $requiredFiles) {
    Add-CheckResult `
        -Passed (Test-Path -LiteralPath (Join-Path $RootPath $relativePath) -PathType Leaf) `
        -Name "required-file/$relativePath" `
        -FailureMessage "file is missing"
}

$powerShellFiles = Get-ChildItem -LiteralPath $RootPath -Filter "*.ps1" -File
foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )

    Add-CheckResult `
        -Passed ($parseErrors.Count -eq 0) `
        -Name "powershell-parse/$($file.Name)" `
        -FailureMessage (($parseErrors | ForEach-Object { $_.Message }) -join "; ")
}

$manifestPath = Join-Path $RootPath "gnhf-fleet.example.json"
try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    Add-CheckResult -Passed ($manifest.schemaVersion -eq 1) -Name "manifest/schema-version" -FailureMessage "expected schemaVersion 1"
    Add-CheckResult -Passed ($manifest.sprints.Count -eq 4) -Name "manifest/sprint-count" -FailureMessage "expected four defined sprint lanes"

    foreach ($sprint in $manifest.sprints) {
        $name = [string]$sprint.name
        Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace($name)) -Name "manifest/name" -FailureMessage "a sprint has no name"
        Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace([string]$sprint.agent)) -Name "manifest/$name/agent" -FailureMessage "agent is missing"
        Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace([string]$sprint.repoPath)) -Name "manifest/$name/repoPath" -FailureMessage "repoPath is missing"
        Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace([string]$sprint.promptPath)) -Name "manifest/$name/promptPath" -FailureMessage "promptPath is missing"
        Add-CheckResult -Passed (-not [string]::IsNullOrWhiteSpace([string]$sprint.stopWhen)) -Name "manifest/$name/stopWhen" -FailureMessage "observable stop condition is missing"
    }
}
catch {
    [void]$failures.Add("manifest/json`: $($_.Exception.Message)")
}

$pathHelpersPath = Join-Path $RootPath "GnhfFleet.Paths.ps1"
if (Test-Path -LiteralPath $pathHelpersPath -PathType Leaf) {
    . $pathHelpersPath

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("agent-switchboard-path-contract-{0}" -f [guid]::NewGuid().ToString("N"))
    try {
        $nestedPath = Join-Path $tempRoot "one\two\three"
        $createdPath = Ensure-GnhfFleetDirectory -Path $nestedPath
        Add-CheckResult -Passed (Test-Path -LiteralPath $createdPath -PathType Container) -Name "paths/creates-missing-directory-tree" -FailureMessage "nested directory was not created"

        $existingPath = Ensure-GnhfFleetDirectory -Path $nestedPath
        Add-CheckResult -Passed ($createdPath -eq $existingPath) -Name "paths/reuses-existing-directory" -FailureMessage "existing directory was not reused idempotently"

        $sampleFile = Join-Path $tempRoot "sample.txt"
        [void](Ensure-GnhfFleetParentDirectory -Path $sampleFile)
        Set-Content -LiteralPath $sampleFile -Value "sample" -Encoding utf8NoBOM
        $resolvedFile = Resolve-GnhfFleetFile -Path $sampleFile -Description "sample file"
        Add-CheckResult -Passed ($resolvedFile -eq (Get-Item -LiteralPath $sampleFile).FullName) -Name "paths/resolves-existing-file" -FailureMessage "existing file did not resolve"

        $sameFile = Copy-GnhfFleetFile -Source $sampleFile -Destination $sampleFile
        Add-CheckResult -Passed ($sameFile -eq $resolvedFile) -Name "paths/skips-self-copy" -FailureMessage "copying an installed file onto itself failed"

        $copiedFile = Join-Path $tempRoot "copy\sample.txt"
        [void](Copy-GnhfFleetFile -Source $sampleFile -Destination $copiedFile)
        Add-CheckResult -Passed (Test-Path -LiteralPath $copiedFile -PathType Leaf) -Name "paths/creates-copy-parent" -FailureMessage "copy helper did not create the destination parent"

        $collisionThrown = $false
        try {
            [void](Ensure-GnhfFleetDirectory -Path $sampleFile)
        }
        catch {
            $collisionThrown = $_.Exception.Message -match "existing non-directory item"
        }
        Add-CheckResult -Passed $collisionThrown -Name "paths/rejects-file-directory-collision" -FailureMessage "a file occupying a directory path was not rejected clearly"

        $missingDirectoryThrown = $false
        try {
            [void](Resolve-GnhfFleetDirectory -Path (Join-Path $tempRoot "missing") -Description "test directory")
        }
        catch {
            $missingDirectoryThrown = $_.Exception.Message -match "not found"
        }
        Add-CheckResult -Passed $missingDirectoryThrown -Name "paths/reports-missing-directory" -FailureMessage "missing directory did not produce a clear error"
    }
    catch {
        [void]$failures.Add("paths/behavior`: $($_.Exception.Message)")
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

$pathHelpers = Get-FileText "GnhfFleet.Paths.ps1"
if ($null -ne $pathHelpers) {
    Add-CheckResult -Passed ($pathHelpers.Contains("function Ensure-GnhfFleetDirectory")) -Name "paths/ensure-directory-helper" -FailureMessage "shared directory helper is missing"
    Add-CheckResult -Passed ($pathHelpers.Contains("function Copy-GnhfFleetFile")) -Name "paths/idempotent-copy-helper" -FailureMessage "shared file copy helper is missing"
    Add-CheckResult -Passed ($pathHelpers.Contains('sourceFullPath.Equals($destinationFullPath')) -Name "paths/self-copy-guard" -FailureMessage "same-source and destination copies are not skipped"
    Add-CheckResult -Passed ($pathHelpers.Contains("-PathType Container")) -Name "paths/distinguishes-directory-type" -FailureMessage "directory type is not validated"
    Add-CheckResult -Passed ($pathHelpers.Contains("existing non-directory item")) -Name "paths/clear-collision-error" -FailureMessage "file/directory collisions are not explicit"
}

$installer = Get-FileText "Install-AgentSwitchboardGnhf.ps1"
if ($null -ne $installer) {
    Add-CheckResult -Passed ($installer.Contains("ReadToEndAsync()")) -Name "installer/async-probe-drain" -FailureMessage "redirected output is not drained asynchronously"
    Add-CheckResult -Passed ($installer.Contains('Available = $probeSucceeded')) -Name "installer/probe-gates-readiness" -FailureMessage "command presence can still be mistaken for readiness"
    Add-CheckResult -Passed ($installer.Contains('if ($gnhf.Available -and -not $RebuildGnhf)')) -Name "installer/reuses-healthy-gnhf" -FailureMessage "healthy GNHF is rebuilt unnecessarily"
    Add-CheckResult -Passed ($installer.Contains('[switch]$RebuildGnhf')) -Name "installer/explicit-source-rebuild" -FailureMessage "source rebuild cannot be requested explicitly"
    Add-CheckResult -Passed ($installer.Contains('[switch]$ResetManifest')) -Name "installer/explicit-manifest-reset" -FailureMessage "manifest reset is not explicit"
    Add-CheckResult -Passed ($installer.Contains('Preserving existing customized fleet manifest')) -Name "installer/preserves-existing-manifest" -FailureMessage "bootstrap can overwrite a customized manifest"
    Add-CheckResult -Passed ($installer.Contains('Copy-GnhfFleetFile -Source $source -Destination $destination')) -Name "installer/uses-idempotent-copy" -FailureMessage "bootstrap can copy installed files onto themselves"
    Add-CheckResult -Passed ($installer.Contains('GnhfFleet.Paths.ps1')) -Name "installer/copies-path-helpers" -FailureMessage "path helpers are not installed with the fleet"
    Add-CheckResult -Passed ($installer.Contains('Test-GnhfFleetContracts.ps1')) -Name "installer/copies-validator" -FailureMessage "contract validator is not installed with the fleet"
}

$operatorLauncher = Get-FileText "Start-AgentSwitchboard.ps1"
if ($null -ne $operatorLauncher) {
    Add-CheckResult -Passed ($operatorLauncher.Contains('[switch]$Bootstrap')) -Name "operator/explicit-bootstrap" -FailureMessage "bootstrap is not explicit"
    Add-CheckResult -Passed ($operatorLauncher.Contains('if ($Bootstrap)')) -Name "operator/bootstrap-repairs-existing-install" -FailureMessage "bootstrap does not refresh an existing partial installation"
    Add-CheckResult -Passed ($operatorLauncher.Contains('[switch]$PushBranch')) -Name "operator/explicit-push" -FailureMessage "push is not an explicit switch"
    Add-CheckResult -Passed ($operatorLauncher.Contains('[ValidateRange(1, 1000000000)]')) -Name "operator/requires-token-cap" -FailureMessage "operator permits an unbounded zero token cap"
    Add-CheckResult -Passed ($operatorLauncher.Contains('Start-GnhfSprint.ps1')) -Name "operator/delegates-to-bounded-sprint" -FailureMessage "operator launcher bypasses the bounded sprint launcher"
    Add-CheckResult -Passed ($operatorLauncher.Contains('agent-switchboard.cmd')) -Name "operator/installs-reusable-command" -FailureMessage "reusable command launcher is not installed"
    Add-CheckResult -Passed ($operatorLauncher.Contains('repoName.Equals("AgentSwitchboard"')) -Name "operator/restricts-bundled-prompts" -FailureMessage "AgentSwitchboard-specific prompts can be silently applied to another repo"
    Add-CheckResult -Passed ($operatorLauncher.Contains('Get-Clipboard -Raw')) -Name "operator/external-prompt-guidance" -FailureMessage "external repos do not receive actionable prompt guidance"
    Add-CheckResult -Passed ($operatorLauncher.Contains('Ensure-GnhfFleetDirectory')) -Name "operator/idempotent-runtime-directories" -FailureMessage "operator directories do not use shared idempotent handling"
    Add-CheckResult -Passed (-not $operatorLauncher.Contains('PushBranch = $true')) -Name "operator/no-default-push" -FailureMessage "branch push is enabled by default"
    Add-CheckResult -Passed ($operatorLauncher.Contains('ValidateSet("opencode", "deepseek"')) -Name "operator/deepseek-alias" -FailureMessage "DeepSeek is not exposed as an operator route"
    Add-CheckResult -Passed ($operatorLauncher.Contains('$stateAgentName = if ($Agent -eq "deepseek") { "opencode" }')) -Name "operator/deepseek-uses-opencode-readiness" -FailureMessage "DeepSeek readiness is not derived from the OpenCode adapter"
    Add-CheckResult -Passed ($operatorLauncher.Contains('function Assert-DeepSeekRouteReady')) -Name "operator/deepseek-route-gate" -FailureMessage "DeepSeek has no deterministic runtime gate"
    Add-CheckResult -Passed ($operatorLauncher.Contains('[version]"1.14.24"')) -Name "operator/opencode-version-floor" -FailureMessage "DeepSeek-compatible OpenCode version is not enforced"
    Add-CheckResult -Passed ($operatorLauncher.Contains('@("models", "deepseek")')) -Name "operator/deepseek-model-discovery" -FailureMessage "exact DeepSeek models are not enumerated before launch"
    Add-CheckResult -Passed ($operatorLauncher.Contains('@("run", "--model", $Model, "--format", "json", $spawnPrompt)')) -Name "operator/exact-model-spawn-probe" -FailureMessage "the exact DeepSeek model is not spawned during preflight"
    Add-CheckResult -Passed ($operatorLauncher.Contains('AGENT_SWITCHBOARD_MODEL_READY')) -Name "operator/positive-spawn-marker" -FailureMessage "spawnability does not require a positive success marker"
    Add-CheckResult -Passed ($operatorLauncher.Contains('OPENCODE_CONFIG_CONTENT')) -Name "operator/runtime-model-pin" -FailureMessage "the GNHF child does not inherit the selected OpenCode model"
    Add-CheckResult -Passed ($operatorLauncher.Contains('logs\provider-routes')) -Name "operator/provider-route-evidence" -FailureMessage "provider route evidence is not recorded outside the repository"
    Add-CheckResult -Passed ($operatorLauncher.Contains('gnhfAgent = "opencode"')) -Name "operator/truthful-gnhf-adapter" -FailureMessage "route evidence does not record OpenCode as the GNHF adapter"
    Add-CheckResult -Passed ($operatorLauncher.Contains('"-Agent", $(if ($Agent -eq "deepseek") { "opencode" } else { $Agent })')) -Name "operator/deepseek-routes-to-opencode" -FailureMessage "DeepSeek is not translated to the native OpenCode adapter"
    Add-CheckResult -Passed (-not $operatorLauncher.Contains('"-Agent", "deepseek"')) -Name "operator/no-fictional-gnhf-agent" -FailureMessage "DeepSeek is incorrectly passed as a native GNHF adapter"
    Add-CheckResult -Passed (-not $operatorLauncher.Contains('DEEPSEEK_API_KEY')) -Name "operator/no-provider-secret-contract" -FailureMessage "provider credentials are embedded in the launcher"
}

$sprintLauncher = Get-FileText "Start-GnhfSprint.ps1"
if ($null -ne $sprintLauncher) {
    Add-CheckResult -Passed ($sprintLauncher.Contains('$objective | & $gnhfPath @gnhfArguments')) -Name "sprint/stdin-prompt" -FailureMessage "prompt is not streamed through stdin"
    Add-CheckResult -Passed (-not $sprintLauncher.Contains('[void]$gnhfArguments.Add($objective)')) -Name "sprint/no-prompt-argv" -FailureMessage "prompt is still appended to argv"
    Add-CheckResult -Passed ($sprintLauncher.Contains('Write-Error -ErrorRecord $_ -ErrorAction Continue')) -Name "sprint/controlled-error-path" -FailureMessage "catch block can terminate before the explicit exit path"
    Add-CheckResult -Passed ($sprintLauncher.Contains('Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "logs")')) -Name "sprint/recreates-log-directory" -FailureMessage "log directory is not recreated"
    Add-CheckResult -Passed ($sprintLauncher.Contains('Resolve-GnhfFleetDirectory -Path $RepoPath')) -Name "sprint/requires-repo-directory" -FailureMessage "repo path type is not validated"
    Add-CheckResult -Passed (-not $sprintLauncher.Contains('Assert-DeepSeekRouteReady')) -Name "sprint/no-deepseek-router-collision" -FailureMessage "explicit DeepSeek routing leaked into the shared sprint core and collides with the stacked automatic router"
}

$fleetLauncher = Get-FileText "Start-GnhfFleet.ps1"
if ($null -ne $fleetLauncher) {
    Add-CheckResult -Passed ($fleetLauncher.Contains('if ($Wait -and $KeepWindowsOpen)')) -Name "fleet/rejects-deadlock-flags" -FailureMessage "-Wait and -KeepWindowsOpen can still be combined"
    Add-CheckResult -Passed ($fleetLauncher.Contains('Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "reports")')) -Name "fleet/recreates-report-directory" -FailureMessage "launch report directory is not recreated"
    Add-CheckResult -Passed ($fleetLauncher.Contains('status = "skipped-invalid-path"')) -Name "fleet/skips-invalid-lane-paths" -FailureMessage "one missing repo or prompt can abort the whole fleet"
    Add-CheckResult -Passed ($fleetLauncher.Contains('status = "skipped-unknown-agent"')) -Name "fleet/skips-unknown-agents" -FailureMessage "unknown agents are launched without readiness evidence"
}

$statusReporter = Get-FileText "Get-GnhfFleetStatus.ps1"
if ($null -ne $statusReporter) {
    Add-CheckResult -Passed ($statusReporter.Contains('Ensure-GnhfFleetDirectory -Path (Join-Path $InstallRoot "reports")')) -Name "status/recreates-report-directory" -FailureMessage "morning report directory is not recreated"
    Add-CheckResult -Passed ($statusReporter.Contains('Add-UnavailableRepoRow')) -Name "status/records-missing-repositories" -FailureMessage "a missing configured repository aborts the whole morning report"
    Add-CheckResult -Passed ($statusReporter.Contains('availability = "worktree-missing"')) -Name "status/records-stale-worktrees" -FailureMessage "missing worktree directories are not reported"
}

Write-Host "GNHF FLEET CONTRACT VALIDATION" -ForegroundColor Cyan
foreach ($pass in $passes) {
    Write-Host "[PASS] $pass" -ForegroundColor Green
}
foreach ($failure in $failures) {
    Write-Host "[FAIL] $failure" -ForegroundColor Red
}

Write-Host ""
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) {
    exit 1
}

exit 0
