[CmdletBinding()]
param(
    [string]$RootPath = $PSScriptRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$modulePath = Join-Path $RootPath "WslRepositoryContracts.psm1"
$installerPath = Join-Path $RootPath "Install-AgentSwitchboardWsl.ps1"
Import-Module -Name $modulePath -Force

$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Add-Result {
    param(
        [Parameter(Mandatory)][bool]$Passed,
        [Parameter(Mandatory)][string]$Name,
        [string]$Message = ""
    )

    if ($Passed) {
        [void]$passes.Add($Name)
    }
    else {
        [void]$failures.Add("$Name`: $Message")
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$Name
    )

    try {
        & $Action
        Add-Result -Passed $false -Name $Name -Message "expected an exception"
    }
    catch {
        Add-Result -Passed $true -Name $Name
    }
}

Add-Result `
    -Passed ((ConvertTo-WslHomeRelativePath -Path "~") -eq "") `
    -Name "home-path/root"

Add-Result `
    -Passed ((ConvertTo-WslHomeRelativePath -Path "~/dev/agents/AgentSwitchboard") -eq "dev/agents/AgentSwitchboard") `
    -Name "home-path/nested"

foreach ($invalidPath in @(
    "",
    "/tmp/repo",
    "C:\repo",
    "~/../repo",
    "~/dev/./repo",
    "~/dev//repo",
    "~/dev;touch/repo",
    "~/$HOME/repo"
)) {
    Assert-Throws `
        -Action { ConvertTo-WslHomeRelativePath -Path $invalidPath } `
        -Name "home-path/reject/$invalidPath"
}

foreach ($validUrl in @(
    "https://github.com/EndeavorEverlasting/AgentSwitchboard.git",
    "git@github.com:EndeavorEverlasting/AgentSwitchboard.git"
)) {
    Add-Result `
        -Passed ((Assert-GitHubRepositoryUrl -Url $validUrl) -eq $validUrl) `
        -Name "repo-url/accept/$validUrl"
}

foreach ($invalidUrl in @(
    "https://example.com/owner/repo.git",
    "file:///tmp/repo",
    "https://github.com/owner/repo",
    "https://github.com/owner/repo.git;touch"
)) {
    Assert-Throws `
        -Action { Assert-GitHubRepositoryUrl -Url $invalidUrl } `
        -Name "repo-url/reject/$invalidUrl"
}

foreach ($validBranch in @("main", "feature/wsl-paths", "release_2026.07")) {
    Add-Result `
        -Passed ((Assert-GitBranchName -Branch $validBranch) -eq $validBranch) `
        -Name "branch/accept/$validBranch"
}

foreach ($invalidBranch in @("", "-main", "feature/../main", "feature branch", "feature/", "main.")) {
    Assert-Throws `
        -Action { Assert-GitBranchName -Branch $invalidBranch } `
        -Name "branch/reject/$invalidBranch"
}

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile(
    $installerPath,
    [ref]$tokens,
    [ref]$parseErrors
)
Add-Result `
    -Passed ($parseErrors.Count -eq 0) `
    -Name "installer/powershell-parse" `
    -Message (($parseErrors | ForEach-Object { $_.Message }) -join "; ")

$installerText = Get-Content -LiteralPath $installerPath -Raw
Add-Result `
    -Passed ($installerText -match 'ConvertTo-WslHomeRelativePath') `
    -Name "installer/uses-home-contract"

Add-Result `
    -Passed ($installerText -match '-ShellArgumentList @\(\$relativeDestination') `
    -Name "installer/uses-positional-arguments"

$unsafeProbe = '$checkCmd = "test -d ''$destPath/.git'' && echo EXISTS || echo MISSING"'
Add-Result `
    -Passed ($installerText -notmatch [regex]::Escape($unsafeProbe)) `
    -Name "installer/removes-quoted-tilde-probe"

Add-Result `
    -Passed ($installerText -match 'git clone --branch "\$repository_branch" -- "\$repository_url" "\$destination"') `
    -Name "installer/clone-argv-is-quoted"

if ($failures.Count -gt 0) {
    Write-Host "FAIL: $($failures.Count) WSL repository path contract check(s)" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}

Write-Host "PASS: $($passes.Count) WSL repository path contract checks" -ForegroundColor Green
