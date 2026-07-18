[CmdletBinding()]
param(
    [string]$RootPath = (Join-Path $PSScriptRoot "..")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path
$failures = [System.Collections.Generic.List[string]]::new()
$passes = [System.Collections.Generic.List[string]]::new()

function Check {
    param([bool]$Condition, [string]$Name, [string]$Message)
    if ($Condition) { [void]$passes.Add($Name) } else { [void]$failures.Add("$Name`: $Message") }
}

$files = @(
    "Gnhf.Process.ps1",
    "Start-ProviderRoutedGnhfSprint.ps1",
    "Install-ProviderRoutedGnhf.ps1"
)
foreach ($relative in $files) {
    $path = Join-Path $RootPath $relative
    Check (Test-Path -LiteralPath $path -PathType Leaf) "required/$relative" "file missing"
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        Check ($errors.Count -eq 0) "parse/$relative" (($errors | ForEach-Object Message) -join "; ")
    }
}

$processText = Get-Content -LiteralPath (Join-Path $RootPath "Gnhf.Process.ps1") -Raw
Check ($processText.Contains('EndsWith(".ps1"')) "dispatch/ps1-detected" "PowerShell shims are not detected"
Check ($processText.Contains('"-NonInteractive"')) "dispatch/pwsh-noninteractive" "pwsh dispatch is not noninteractive"
Check ($processText.Contains('EndsWith(".cmd"')) "dispatch/cmd-detected" "CMD shims are not detected"
Check ($processText.Contains('WaitForExit(5000)')) "dispatch/bounded-post-kill" "timeout cleanup can block indefinitely"

$launcherText = Get-Content -LiteralPath (Join-Path $RootPath "Start-ProviderRoutedGnhfSprint.ps1") -Raw
Check ($launcherText.Contains('Set-Location -LiteralPath $RepoPath')) "launcher/directory-first" "repository is not entered before runtime logic"
Check ($launcherText.Contains('GNHF 0.1.42 or newer is required')) "launcher/gnhf-floor" "GNHF compatibility floor missing"
Check ($launcherText.Contains('"--model", $Model')) "launcher/explicit-model" "GNHF does not receive the exact provider/model"
Check ($launcherText.Contains('$evidence.sprintInvoked = $true')) "launcher/invocation-evidence" "GNHF invocation state is not recorded"
Check ($launcherText.Contains('Process exit zero is not delivery proof')) "launcher/commit-proof" "exit code can be mistaken for delivery"
Check ($launcherText.Contains('DeepSeek provider probe failed; GNHF was not started')) "launcher/provider-fail-fast" "provider failure can fall through into GNHF retries"
Check (-not $launcherText.Contains('DEEPSEEK_API_KEY')) "launcher/no-secret" "provider key handling is embedded"
Check (-not $launcherText.Contains('"--push"')) "launcher/no-push" "unattended provider route enables push"

$installerText = Get-Content -LiteralPath (Join-Path $RootPath "Install-ProviderRoutedGnhf.ps1") -Raw
Check ($installerText.Contains('Set-Location -LiteralPath $RepoRoot')) "installer/directory-first" "installer does not enter AgentSwitchboard first"
Check ($installerText.Contains('"gnhf@$required"')) "installer/pinned-gnhf" "installer uses an unpinned GNHF package"
Check ($installerText.Contains('modelFlagVerified')) "installer/model-capability-state" "installed state does not record model capability"

$temp = Join-Path ([IO.Path]::GetTempPath()) ("agentswitchboard-shim-contract-{0}" -f [guid]::NewGuid().ToString("N"))
try {
    [void](New-Item -ItemType Directory -Path $temp -Force)
    $shim = Join-Path $temp "fake-opencode.ps1"
    @'
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Remaining)
Write-Output "WINDOWS_SHIM_OK:$($Remaining -join ',')"
exit 0
'@ | Set-Content -LiteralPath $shim -Encoding utf8NoBOM

    . (Join-Path $RootPath "Gnhf.Process.ps1")
    $probe = Invoke-GnhfBoundedCommand -FilePath $shim -ArgumentList @("--version") -WorkingDirectory $temp -TimeoutSeconds 10
    Check ($probe.exitCode -eq 0) "runtime/ps1-shim-exits" "PowerShell shim exit code was $($probe.exitCode)"
    Check ($probe.dispatch -eq "pwsh-file") "runtime/ps1-shim-dispatch" "dispatch was $($probe.dispatch)"
    Check ($probe.output -match 'WINDOWS_SHIM_OK:--version') "runtime/ps1-shim-output" "shim output missing: $($probe.output)"
}
finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}

Write-Host "PROVIDER-ROUTED GNHF CONTRACTS" -ForegroundColor Cyan
$passes | ForEach-Object { Write-Host "[PASS] $_" -ForegroundColor Green }
$failures | ForEach-Object { Write-Host "[FAIL] $_" -ForegroundColor Red }
Write-Host ""
Write-Host ("Result: {0} passed / {1} failed" -f $passes.Count, $failures.Count)
if ($failures.Count -gt 0) { exit 1 }
exit 0
