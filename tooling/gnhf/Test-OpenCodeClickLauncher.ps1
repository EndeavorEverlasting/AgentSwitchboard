[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$cmdPath = Join-Path $repoRoot 'Start-AgentSwitchboard-OpenCode.cmd'
$clickLauncher = Join-Path $PSScriptRoot 'Start-AgentSwitchboardOpenCode.ps1'
$sprintLauncher = Join-Path $PSScriptRoot 'Start-GnhfSprint.ps1'
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param([bool]$Passed, [string]$Name, [string]$Failure = '')
    if ($Passed) { [void]$passes.Add($Name) }
    else { [void]$failures.Add("$Name`: $Failure") }
}

foreach ($path in @($cmdPath, $clickLauncher, $sprintLauncher)) {
    Add-Result -Passed (Test-Path -LiteralPath $path -PathType Leaf) -Name "required/$([IO.Path]::GetFileName($path))" -Failure 'file is missing'
}

foreach ($path in @($clickLauncher, $sprintLauncher, $PSCommandPath)) {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    Add-Result -Passed ($errors.Count -eq 0) -Name "parse/$([IO.Path]::GetFileName($path))" -Failure (($errors | ForEach-Object Message) -join '; ')
}

if (Test-Path -LiteralPath $cmdPath -PathType Leaf) {
    $cmd = Get-Content -LiteralPath $cmdPath -Raw
    Add-Result -Passed $cmd.Contains('tooling\gnhf\Start-AgentSwitchboardOpenCode.ps1') -Name 'cmd/routes-to-owned-launcher' -Failure 'CMD does not route to the repo-owned PowerShell launcher'
    Add-Result -Passed $cmd.Contains('Test-OperatorChildExecutableLaunch.ps1') -Name 'cmd/proves-pwsh-child' -Failure 'CMD promotes PowerShell discovery without the concrete child-launch probe'
    Add-Result -Passed $cmd.Contains('AGENT_SWITCHBOARD_NO_PAUSE') -Name 'cmd/preserves-visible-diagnostics' -Failure 'click window has no explicit pause/automation boundary'
    foreach ($token in @('-MaxIterations', '-MaxTokens', '-StopWhen', 'Get-Clipboard')) {
        Add-Result -Passed (-not $cmd.Contains($token)) -Name "cmd/no-operator-reconstruction/$token" -Failure 'bounded sprint implementation leaked back into the CMD surface'
    }
}

if (Test-Path -LiteralPath $clickLauncher -PathType Leaf) {
    $click = Get-Content -LiteralPath $clickLauncher -Raw
    foreach ($token in @('Get-Clipboard -Raw','Start-GnhfSprint.ps1','Detached HEAD is not a valid sprint base','--porcelain=v1','--show-current','logs\opencode-click','-Agent',"'opencode'",'-PromptPath','[switch]$PlanOnly')) {
        Add-Result -Passed $click.Contains($token) -Name "launcher/contract/$token" -Failure "missing token: $token"
    }
    Add-Result -Passed (-not $click.Contains('Start-AgentSwitchboard.ps1')) -Name 'launcher/avoids-stale-installed-sprint-indirection' -Failure 'click launcher can still delegate through an installed stale Start-AgentSwitchboard copy'
}

if (Test-Path -LiteralPath $sprintLauncher -PathType Leaf) {
    $sprint = Get-Content -LiteralPath $sprintLauncher -Raw
    Add-Result -Passed $sprint.Contains('$branchOutput = @(Invoke-Git -Arguments @("branch", "--show-current"))') -Name 'sprint/null-safe-branch-read' -Failure 'branch output is still trimmed before null normalization'
    Add-Result -Passed (-not $sprint.Contains('(Invoke-Git -Arguments @("branch", "--show-current") | Select-Object -First 1).Trim()')) -Name 'sprint/rejects-null-trim-regression' -Failure 'original null-valued .Trim() regression is still present'
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("agentswitchboard-opencode-click-contract-{0}" -f [guid]::NewGuid().ToString('N'))
try {
    $fixtureRepo = Join-Path $tempRoot 'fixture-repo'
    $installRoot = Join-Path $tempRoot 'fleet'
    $null = New-Item -ItemType Directory -Path $fixtureRepo -Force
    $null = New-Item -ItemType Directory -Path $installRoot -Force

    & git -C $fixtureRepo init -b main | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
    & git -C $fixtureRepo config user.email 'fixture@example.invalid'
    & git -C $fixtureRepo config user.name 'AgentSwitchboard Fixture'
    Set-Content -LiteralPath (Join-Path $fixtureRepo 'README.md') -Value '# fixture' -Encoding utf8NoBOM
    & git -C $fixtureRepo add README.md
    & git -C $fixtureRepo commit -m 'fixture' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'fixture commit failed' }

    [ordered]@{
        schemaVersion = 1
        gnhf = [ordered]@{ commandPath = (Join-Path $tempRoot 'unused-gnhf.exe') }
        agents = [ordered]@{
            opencode = [ordered]@{
                available = $true
                agentSpec = 'opencode'
                evidence = 'fixture adapter readiness'
            }
        }
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $installRoot 'state.json') -Encoding utf8NoBOM

    & git -C $fixtureRepo checkout --detach HEAD | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'fixture detach failed' }

    $detachedOutput = & (Join-Path $PSHOME 'pwsh.exe') -NoLogo -NoProfile -ExecutionPolicy Bypass -File $sprintLauncher `
        -RepoPath $fixtureRepo `
        -Agent opencode `
        -Prompt 'detached fixture prompt' `
        -Name 'detached-fixture' `
        -MaxIterations 1 `
        -MaxTokens 1 `
        -StopWhen 'fixture gate' `
        -InstallRoot $installRoot 2>&1 | Out-String
    $detachedCode = $LASTEXITCODE
    Add-Result -Passed ($detachedCode -ne 0) -Name 'behavior/detached-head-rejected' -Failure 'detached sprint unexpectedly returned zero'
    Add-Result -Passed ($detachedOutput -match 'Detached HEAD is not allowed for an unattended sprint') -Name 'behavior/detached-head-explicit-gate' -Failure $detachedOutput
    Add-Result -Passed ($detachedOutput -notmatch 'null-valued expression') -Name 'behavior/no-null-method-crash' -Failure $detachedOutput

    & git -C $fixtureRepo switch main | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'fixture reattach failed' }

    $planOutput = & (Join-Path $PSHOME 'pwsh.exe') -NoLogo -NoProfile -ExecutionPolicy Bypass -File $clickLauncher `
        -RepoPath $fixtureRepo `
        -Prompt 'bounded fixture prompt' `
        -PlanOnly `
        -InstallRoot $installRoot 2>&1 | Out-String
    $planCode = $LASTEXITCODE
    Add-Result -Passed ($planCode -eq 0) -Name 'behavior/click-plan-passes-attached-clean-repo' -Failure $planOutput
    Add-Result -Passed ($planOutput -match 'No GNHF or provider process was started') -Name 'behavior/plan-proof-ceiling-visible' -Failure $planOutput

    $summary = Get-ChildItem -LiteralPath (Join-Path $installRoot 'logs\opencode-click') -Filter 'opencode-click-launch.json' -File -Recurse | Sort-Object LastWriteTimeUtc | Select-Object -Last 1
    Add-Result -Passed ($null -ne $summary) -Name 'behavior/click-summary-written' -Failure 'plan did not write launch evidence'
    if ($summary) {
        $summaryObject = Get-Content -LiteralPath $summary.FullName -Raw | ConvertFrom-Json
        Add-Result -Passed ($summaryObject.status -eq 'planned') -Name 'behavior/summary-status-planned' -Failure "status=$($summaryObject.status)"
        $summaryText = Get-Content -LiteralPath $summary.FullName -Raw
        Add-Result -Passed (-not $summaryText.Contains('bounded fixture prompt')) -Name 'behavior/summary-does-not-copy-raw-prompt' -Failure 'raw prompt leaked into launch summary'
    }

    $oldNoPause = $env:AGENT_SWITCHBOARD_NO_PAUSE
    try {
        $env:AGENT_SWITCHBOARD_NO_PAUSE = '1'
        $cmdOutput = & $cmdPath $fixtureRepo -Prompt 'bounded cmd fixture prompt' -PlanOnly -InstallRoot $installRoot 2>&1 | Out-String
        $cmdCode = $LASTEXITCODE
    }
    finally {
        $env:AGENT_SWITCHBOARD_NO_PAUSE = $oldNoPause
    }
    Add-Result -Passed ($cmdCode -eq 0) -Name 'behavior/actual-cmd-plan-passes' -Failure $cmdOutput
    Add-Result -Passed ($cmdOutput -match '\[DONE\] AgentSwitchboard OpenCode launcher completed') -Name 'behavior/actual-cmd-visible-result' -Failure $cmdOutput
}
catch {
    [void]$failures.Add("behavior/setup: $($_.Exception.Message)")
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    Write-Host 'OpenCode click launcher contract: FAIL' -ForegroundColor Red
    foreach ($failure in $failures) { Write-Host "- $failure" -ForegroundColor Red }
    throw "OpenCode click launcher contract failed: $($failures.Count) check(s)."
}

Write-Host "OpenCode click launcher contract: PASS ($($passes.Count) checks)" -ForegroundColor Green
