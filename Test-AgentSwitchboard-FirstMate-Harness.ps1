[CmdletBinding()]
param(
    [ValidateSet('contract', 'report', 'route', 'runtime-floor')]
    [string]$Mode = 'contract',

    [string]$ExpectedHead,

    [switch]$RepairWslIfNeeded,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7+ (pwsh) is required for the Windows First Mate harness front door.'
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Python = Get-Command python.exe -ErrorAction SilentlyContinue
if (-not $Python) {
    $Python = Get-Command python -ErrorAction SilentlyContinue
}
if (-not $Python) {
    throw 'Python is unavailable on PATH.'
}

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    & $Action
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$Name failed with exit code $exitCode."
    }
}

Push-Location $Root
try {
    switch ($Mode) {
        'contract' {
            Invoke-NativeChecked -Name 'First Mate integration contract' -Action {
                & $Python.Source tests/test_firstmate_integration_contract.py
            }
            Invoke-NativeChecked -Name 'First Mate operational harness completeness' -Action {
                & $Python.Source tests/test_firstmate_operational_harness.py
            }
            Invoke-NativeChecked -Name 'First Mate Windows portability contract' -Action {
                & $Python.Source tests/test_firstmate_windows_harness_portability.py
            }
            Invoke-NativeChecked -Name 'First Mate Windows-to-WSL bridge contract' -Action {
                & $Python.Source tests/test_firstmate_windows_wsl_bridge.py
            }

            if ([string]::IsNullOrWhiteSpace($ExpectedHead)) {
                $ExpectedHead = (& git rev-parse HEAD).Trim()
                if ($LASTEXITCODE -ne 0) {
                    throw 'Unable to resolve the exact AgentSwitchboard HEAD.'
                }
            }

            $bridge = Join-Path $Root 'Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1'
            & pwsh -NoLogo -NoProfile -File $bridge `
                -ExpectedHead $ExpectedHead `
                -ContractOnly
            if ($LASTEXITCODE -ne 0) {
                throw "Windows-to-WSL bridge ContractOnly gate failed with exit code $LASTEXITCODE."
            }

            Invoke-NativeChecked -Name 'Working-tree diff hygiene' -Action {
                & git diff --check
            }
            Invoke-NativeChecked -Name 'Staged diff hygiene' -Action {
                & git diff --cached --check
            }

            Write-Host '[PASS] FIRSTMATE_WINDOWS_OPERATIONAL_HARNESS'
            Write-Host "HEAD=$ExpectedHead"
            Write-Host 'SHELL=windows-powershell'
            return
        }

        'report' {
            & $Python.Source tooling/firstmate/harness/operational/Build-FirstMateHarnessReport.py @RemainingArgs
            if ($LASTEXITCODE -ne 0) {
                throw "First Mate report generation failed with exit code $LASTEXITCODE."
            }
            return
        }

        'route' {
            & $Python.Source tooling/firstmate/harness/operational/Select-FirstMateWorkflow.py @RemainingArgs
            if ($LASTEXITCODE -ne 0) {
                throw "First Mate route selection failed with exit code $LASTEXITCODE."
            }
            return
        }

        'runtime-floor' {
            if ([string]::IsNullOrWhiteSpace($ExpectedHead)) {
                $ExpectedHead = (& git rev-parse HEAD).Trim()
                if ($LASTEXITCODE -ne 0) {
                    throw 'Unable to resolve the exact AgentSwitchboard HEAD.'
                }
            }

            $bridge = Join-Path $Root 'Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1'
            $bridgeArgs = @(
                '-NoLogo', '-NoProfile', '-File', $bridge,
                '-ExpectedHead', $ExpectedHead
            )
            if ($RepairWslIfNeeded) {
                $bridgeArgs += '-RepairWslIfNeeded'
            }

            & pwsh @bridgeArgs
            if ($LASTEXITCODE -ne 0) {
                throw "First Mate physical runtime floor failed with exit code $LASTEXITCODE."
            }
            return
        }
    }
}
finally {
    Pop-Location
}
