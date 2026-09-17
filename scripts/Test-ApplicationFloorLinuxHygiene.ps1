[CmdletBinding()]
param(
    [string]$RootPath = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

Write-Host "APPLICATION_FLOOR_LINUX_HYGIENE: Testing from $RootPath"

function Get-PythonCommand {
    foreach ($candidate in @('python3', 'python')) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $cmd) { return $cmd.Source }
    }
    throw 'Python interpreter not found (python3/python).'
}

$python = Get-PythonCommand
$failures = [System.Collections.Generic.List[string]]::new()

# 1. Parse tracked JSON
Write-Host "`n=== Parsing tracked JSON files ==="
$jsonScript = @'
import json
from pathlib import Path

failed = []
passed = []

for path in Path('.').rglob('*.json'):
    if any(part in {'.git', '.gnhf', 'node_modules'} for part in path.parts):
        continue
    try:
        json.loads(path.read_text(encoding='utf-8-sig'))
        passed.append(str(path))
        print(f'PASS: {path}')
    except Exception as e:
        failed.append((str(path), str(e)))
        print(f'FAIL: {path} - {e}')

if failed:
    print(f'\nFailed to parse {len(failed)} JSON file(s):')
    for path, error in failed:
        print(f'  {path}: {error}')
    exit(1)
else:
    print(f'\nParsed {len(passed)} JSON file(s) successfully.')
    exit(0)
'@

$psi = [System.Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $python
$psi.WorkingDirectory = $RootPath
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.RedirectStandardInput = $true
$psi.CreateNoWindow = $true
[void]$psi.ArgumentList.Add('-')

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $psi
try {
    [void]$process.Start()
    $process.StandardInput.Write($jsonScript)
    $process.StandardInput.Close()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $stdout = [string]$stdoutTask.GetAwaiter().GetResult()
    $stderr = [string]$stderrTask.GetAwaiter().GetResult()
    $combined = ($stdout + [Environment]::NewLine + $stderr).Trim()
    Write-Host $combined
    if ($process.ExitCode -ne 0) {
        $failures.Add('JSON parsing failed')
    }
}
finally {
    $process.Dispose()
}

# 2. Check shell scripts
Write-Host "`n=== Checking shell scripts ==="
$bashCmd = Get-Command bash -ErrorAction SilentlyContinue
if ($null -eq $bashCmd) {
    Write-Warning "bash not found; skipping shell script syntax checks (acceptable on Windows)"
}
else {
    $shellFiles = Get-ChildItem -LiteralPath (Join-Path $RootPath 'tooling') -Recurse -File -Filter '*.sh' -ErrorAction SilentlyContinue
    $shellCheckCount = 0
    foreach ($file in $shellFiles) {
        $shellCheckCount++
        $result = & bash -n $file.FullName 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host ("FAIL: {0}" -f $file.FullName)
            if ($result) {
                Write-Host $result
            }
            $failures.Add("Shell script syntax error: $($file.Name)")
        }
        else {
            Write-Host ("PASS: {0}" -f $file.FullName)
        }
    }
    Write-Host ("Checked {0} shell script(s)" -f $shellCheckCount)
}

# 3. Git diff --check (if in a git repository)
Write-Host "`n=== Git diff hygiene ==="
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCmd) {
    Write-Warning "git not found; skipping diff hygiene check"
}
else {
    $diffCheck = & git -C $RootPath diff --check 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAIL: git diff --check failed"
        if ($diffCheck) {
            Write-Host $diffCheck
        }
        $failures.Add('git diff --check failed')
    }
    else {
        Write-Host "PASS: git diff --check"
    }
}

# 4. Verify clean checkout
Write-Host "`n=== Checkout cleanliness ==="
if ($null -ne $gitCmd) {
    $statusOutput = & git -C $RootPath status --short 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "git status failed"
    }
    elseif ([string]::IsNullOrWhiteSpace($statusOutput)) {
        Write-Host "PASS: checkout is clean"
    }
    else {
        Write-Host "FAIL: checkout is dirty"
        Write-Host $statusOutput
        $failures.Add('checkout is dirty after application-floor linux-hygiene validation')
    }
}

# Summary
Write-Host "`n=== Summary ==="
if ($failures.Count -eq 0) {
    Write-Host "APPLICATION_FLOOR_LINUX_HYGIENE: PASS"
    exit 0
}
else {
    Write-Host "APPLICATION_FLOOR_LINUX_HYGIENE: FAIL"
    Write-Host "Failures:"
    foreach ($failure in $failures) {
        Write-Host ("  - {0}" -f $failure)
    }
    exit 1
}
