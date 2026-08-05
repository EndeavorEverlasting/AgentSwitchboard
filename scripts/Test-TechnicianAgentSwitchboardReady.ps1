[CmdletBinding()]
param(
    [string]$RootPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw 'Unable to resolve validator directory. Supply -RootPath explicitly.'
    }
    $RootPath = Split-Path -Parent $PSScriptRoot
}
$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path

$gitCommand = Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $gitCommand) {
    $gitCommand = Get-Command git -ErrorAction Stop
}

$paths = [ordered]@{
    readyCmd = 'Technician-AgentSwitchboard-Ready.cmd'
    readyEngine = 'tooling\profiles\windows\Invoke-TechnicianAgentSwitchboardReady.ps1'
    compatibilitySetup = 'tooling\profiles\windows\Setup-TechnicianAgentSwitchboard.ps1'
    profileLauncher = 'tooling\profiles\windows\Invoke-AgentSwitchboardOpenOrActivate.ps1'
    p02 = 'tooling\profiles\windows\technician-live-cert\stages\P02-Pull-And-Setup.ps1'
    p03 = 'tooling\profiles\windows\technician-live-cert\stages\P03-Verify-Commands.ps1'
    shortcuts = 'tooling\profiles\windows\technician-live-cert\Install-TechnicianLiveCertShortcuts.ps1'
    exactCmd = 'Validate-Technician-ExactHead.cmd'
    exactValidator = 'scripts\Invoke-TechnicianExactHeadValidation.ps1'
    pythonContracts = 'tests\test_technician_agentswitchboard_ready.py'
}

$failures = [Collections.Generic.List[string]]::new()

function Add-Failure {
    param([Parameter(Mandatory)][string]$Message)
    [void]$failures.Add($Message)
    Write-Host "FAIL: $Message" -ForegroundColor Red
}

function Require-Token {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$Label
    )
    if (-not $Text.Contains($Token)) {
        Add-Failure "$Label is missing token: $Token"
    }
}

foreach ($entry in $paths.GetEnumerator()) {
    $full = Join-Path $RootPath $entry.Value
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        Add-Failure "Missing $($entry.Key): $($entry.Value)"
        continue
    }
    & $gitCommand.Source -C $RootPath ls-files --error-unmatch -- $entry.Value *> $null
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "Untracked $($entry.Key): $($entry.Value)"
    }
}

if ($failures.Count -eq 0) {
    $ready = Get-Content -LiteralPath (Join-Path $RootPath $paths.readyEngine) -Raw
    $compat = Get-Content -LiteralPath (Join-Path $RootPath $paths.compatibilitySetup) -Raw
    $launcher = Get-Content -LiteralPath (Join-Path $RootPath $paths.profileLauncher) -Raw
    $p02 = Get-Content -LiteralPath (Join-Path $RootPath $paths.p02) -Raw
    $p03 = Get-Content -LiteralPath (Join-Path $RootPath $paths.p03) -Raw
    $exact = Get-Content -LiteralPath (Join-Path $RootPath $paths.exactValidator) -Raw

    foreach ($item in @(
        [pscustomobject]@{ Name = 'readiness engine'; Text = $ready },
        [pscustomobject]@{ Name = 'compatibility setup'; Text = $compat },
        [pscustomobject]@{ Name = 'profile launcher'; Text = $launcher },
        [pscustomobject]@{ Name = 'P02'; Text = $p02 },
        [pscustomobject]@{ Name = 'P03'; Text = $p03 },
        [pscustomobject]@{ Name = 'exact-head validator'; Text = $exact }
    )) {
        if ($item.Text.Contains(".Replace([char]0, '')")) {
            Add-Failure "$($item.Name) contains ambiguous char/string Replace."
        }
        $strictIndex = $item.Text.IndexOf('Set-StrictMode')
        $prefix = if ($strictIndex -gt 0) { $item.Text.Substring(0, $strictIndex) } else { $item.Text }
        if ($prefix.Contains('$PSScriptRoot')) {
            Add-Failure "$($item.Name) evaluates `$PSScriptRoot in a parameter default."
        }
    }

    foreach ($token in @('Setup-AgentSwitchboard.ps1','Get-AgentSwitchboardStartupReport.ps1',"Write-CommandShim -Name 'AgentSwitchboard'",'AgentSwitchboard.lnk','-ListAgents','fresh-shell-agentswitchboard','stateObserved','proofCeiling')) {
        Require-Token -Text $ready -Token $token -Label 'readiness engine'
    }

    Require-Token -Text $compat -Token 'Invoke-TechnicianAgentSwitchboardReady.ps1' -Label 'compatibility setup'
    Require-Token -Text $launcher -Token 'windows-profile-launch-plan.v2' -Label 'profile launcher'
    Require-Token -Text $launcher -Token 'tmux kill-session' -Label 'profile launcher rollback'
    Require-Token -Text $p02 -Token 'GnhfFleet\state.json' -Label 'P02 fleet proof'
    Require-Token -Text $p02 -Token 'technician-ready-summary.json' -Label 'P02 readiness evidence'
    Require-Token -Text $p03 -Token "@('AgentSwitchboard', 'wezterm', 'tmux', 'agy', 'opencode')" -Label 'P03 five-command set'
    Require-Token -Text $p03 -Token 'AgentSwitchboard -ListAgents' -Label 'P03 AgentSwitchboard proof'
    Require-Token -Text $exact -Token 'worktree add --detach' -Label 'exact-head worktree'
    Require-Token -Text $exact -Token 'Verified HEAD: $actualHead' -Label 'truthful exact-head report'
    Require-Token -Text $exact -Token 'LastWriteTimeUtc -ge $p00StartedUtc' -Label 'fresh P00 evidence'

    foreach ($forbidden in @('git reset', 'git clean', 'git stash', 'push --force')) {
        if ($ready.ToLowerInvariant().Contains($forbidden) -or $exact.ToLowerInvariant().Contains($forbidden)) {
            Add-Failure "Forbidden destructive token appears: $forbidden"
        }
    }

    foreach ($path in @($paths.readyEngine,$paths.compatibilitySetup,$paths.profileLauncher,$paths.p02,$paths.p03,$paths.shortcuts,$paths.exactValidator)) {
        $tokens = $null
        $parseErrors = $null
        [void][Management.Automation.Language.Parser]::ParseFile((Join-Path $RootPath $path),[ref]$tokens,[ref]$parseErrors)
        foreach ($parseError in $parseErrors) {
            Add-Failure "PowerShell parse error in $path at $($parseError.Extent.StartLineNumber): $($parseError.Message)"
        }
    }
}

if ($failures.Count -gt 0) {
    Write-Host ''
    Write-Host "Technician AgentSwitchboard readiness validation failed with $($failures.Count) issue(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'PASS: Technician AgentSwitchboard readiness surface is complete, tracked, parseable, and guarded.' -ForegroundColor Green
exit 0
