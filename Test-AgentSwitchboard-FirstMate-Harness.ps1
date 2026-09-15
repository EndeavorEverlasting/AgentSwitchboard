[CmdletBinding()]
param(
    [ValidateSet('contract', 'physical-floor', 'physical-floor-continue')]
    [string]$Mode = 'contract',

    [string]$ExpectedHead,
    [string]$FirstMatePath,
    [string]$SourceRepositoryPath,
    [string]$EvidenceRoot,
    [string]$WslDistribution = 'Ubuntu',

    [ValidateRange(10, 300)]
    [int]$PrerequisiteTimeoutSeconds = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'PowerShell 7+ (pwsh) is required for the Windows FirstMate harness front door.'
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    & $Action
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        # Keep structured child exits — do not throw (throw collapses to unstructured exit 1).
        Write-Host "STATUS=BLOCKED_HARNESS_CONTRACT"
        Write-Host "FAILED_CHECK=$Name"
        Write-Host "CHILD_EXIT_CODE=$exitCode"
        Write-Host "NEXT=repair $Name (child exit $exitCode), then rerun Test-AgentSwitchboard-FirstMate-Harness.ps1"
        exit $exitCode
    }
}

Push-Location $Root
try {
    if ([string]::IsNullOrWhiteSpace($ExpectedHead)) {
        $ExpectedHead = (& git rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) {
            # Keep structured — do not throw (throw collapses to unstructured exit 1).
            Write-Host 'STATUS=BLOCKED_GIT_HEAD'
            Write-Host 'NEXT=repair the AgentSwitchboard checkout so git rev-parse HEAD succeeds, then rerun Test-AgentSwitchboard-FirstMate-Harness.ps1'
            exit 1
        }
    }

    switch ($Mode) {
        'contract' {
            # The Linux/WSL integration-contract suite intentionally exercises the Bash
            # probe and therefore belongs to Linux CI. The Windows front door validates
            # only platform-neutral/Windows bridge suites so Windows Python never needs
            # to launch a bare POSIX shell.
            # Python is only required for contract-mode unit suites — not physical-floor live modes.
            $Python = Get-Command python.exe -ErrorAction SilentlyContinue
            if (-not $Python) { $Python = Get-Command python -ErrorAction SilentlyContinue }
            if (-not $Python) {
                # Keep structured — do not throw (throw collapses to unstructured exit 1).
                Write-Host 'STATUS=BLOCKED_HARNESS_CONTRACT'
                Write-Host 'NEXT=install python.exe (or python) on PATH for contract-mode unit suites, then rerun Test-AgentSwitchboard-FirstMate-Harness.ps1 -Mode contract'
                exit 52
            }
            foreach ($test in @(
                'tests/test_firstmate_asb_convergence_contract.py',
                'tests/test_firstmate_operational_harness.py',
                'tests/test_firstmate_windows_harness_portability.py',
                'tests/test_firstmate_windows_wsl_bridge.py',
                'tests/test_firstmate_windows_wsl_prerequisite_gate.py'
            )) {
                Invoke-NativeChecked -Name $test -Action { & $Python.Source $test }
            }

            $bridge = Join-Path $Root 'Test-AgentSwitchboard-FirstMate-WindowsWSL.ps1'
            & pwsh -NoLogo -NoProfile -File $bridge -ExpectedHead $ExpectedHead -WslDistribution $WslDistribution -ContractOnly
            if ($LASTEXITCODE -ne 0) {
                # Preserve structured child exits — do not throw (throw collapses to unstructured exit 1).
                exit $LASTEXITCODE
            }

            $physical = Join-Path $Root 'Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1'
            & pwsh -NoLogo -NoProfile -File $physical -ExpectedHead $ExpectedHead -WslDistribution $WslDistribution -ContractOnly
            if ($LASTEXITCODE -ne 0) {
                # Preserve structured child exits — do not throw (throw collapses to unstructured exit 1).
                exit $LASTEXITCODE
            }

            $continuation = Join-Path $Root 'Invoke-FirstMatePhysicalFloorContinuation.ps1'
            & pwsh -NoLogo -NoProfile -File $continuation -ExpectedHead $ExpectedHead -WslDistribution $WslDistribution -ContractOnly
            if ($LASTEXITCODE -ne 0) {
                # Preserve structured child exits — do not throw (throw collapses to unstructured exit 1).
                exit $LASTEXITCODE
            }

            $adminBoxLive = Join-Path $Root 'Invoke-FmWsl12AdminBoxLiveProof.ps1'
            & pwsh -NoLogo -NoProfile -File $adminBoxLive -ExpectedHead $ExpectedHead -WslDistribution $WslDistribution -ContractOnly
            if ($LASTEXITCODE -ne 0) {
                # Preserve structured child exits — do not throw (throw collapses to unstructured exit 1).
                exit $LASTEXITCODE
            }

            $asq017LiveFloor = Join-Path $Root 'Invoke-Asq017AdminBoxLiveFloor.ps1'
            & pwsh -NoLogo -NoProfile -File $asq017LiveFloor -WslDistribution $WslDistribution -ContractOnly
            if ($LASTEXITCODE -ne 0) {
                # Preserve structured child exits — do not throw (throw collapses to unstructured exit 1).
                exit $LASTEXITCODE
            }

            Invoke-NativeChecked -Name 'Working-tree diff hygiene' -Action { & git diff --check }
            Invoke-NativeChecked -Name 'Staged diff hygiene' -Action { & git diff --cached --check }

            Write-Host '[PASS] FIRSTMATE_WINDOWS_OPERATIONAL_HARNESS'
            Write-Host "HEAD=$ExpectedHead"
            Write-Host 'WINDOWS_ROLE=bridge-only'
            Write-Host 'RUNTIME_OWNER=FirstMate'
            Write-Host '[PROOF_CEILING] Hosted/contract proof only; no physical WSL or live crew runtime is claimed.'
            return
        }

        'physical-floor' {
            $physical = Join-Path $Root 'Test-AgentSwitchboard-FirstMate-PhysicalFloor.ps1'
            $args = @(
                '-NoLogo', '-NoProfile', '-File', $physical,
                '-ExpectedHead', $ExpectedHead,
                '-WslDistribution', $WslDistribution,
                '-PrerequisiteTimeoutSeconds', "$PrerequisiteTimeoutSeconds"
            )
            if (-not [string]::IsNullOrWhiteSpace($FirstMatePath)) {
                $args += @('-FirstMatePath', $FirstMatePath)
            }
            if (-not [string]::IsNullOrWhiteSpace($SourceRepositoryPath)) {
                $args += @('-SourceRepositoryPath', $SourceRepositoryPath)
            }
            if (-not [string]::IsNullOrWhiteSpace($EvidenceRoot)) {
                $args += @('-EvidenceRoot', $EvidenceRoot)
            }
            & pwsh @args
            # Preserve structured prerequisite exits (44 missing tools / 45 GitHub auth).
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            return
        }

        'physical-floor-continue' {
            # FM-WSL-12 / P08 continuation authority: execution owner may run allowlisted
            # Ubuntu apt-get repair then rerun. The physical-floor harness remains
            # non-installing; this mode owns the repair→rerun loop and still stops on
            # BLOCKED_GITHUB_AUTH / non-package blockers.
            $continuation = Join-Path $Root 'Invoke-FirstMatePhysicalFloorContinuation.ps1'
            if (-not (Test-Path -LiteralPath $continuation -PathType Leaf)) {
                # Keep structured — do not throw (throw collapses to unstructured exit 1).
                Write-Host 'STATUS=BLOCKED_HARNESS_CONTRACT'
                Write-Host "MISSING_SURFACE=$continuation"
                Write-Host "NEXT=restore Invoke-FirstMatePhysicalFloorContinuation.ps1 at checkout root ($continuation), then rerun Test-AgentSwitchboard-FirstMate-Harness.ps1 -Mode physical-floor-continue"
                exit 52
            }
            $args = @(
                '-NoLogo', '-NoProfile', '-File', $continuation,
                '-ExpectedHead', $ExpectedHead,
                '-WslDistribution', $WslDistribution,
                '-PrerequisiteTimeoutSeconds', "$PrerequisiteTimeoutSeconds"
            )
            if (-not [string]::IsNullOrWhiteSpace($FirstMatePath)) {
                $args += @('-FirstMatePath', $FirstMatePath)
            }
            if (-not [string]::IsNullOrWhiteSpace($SourceRepositoryPath)) {
                $args += @('-SourceRepositoryPath', $SourceRepositoryPath)
            }
            if (-not [string]::IsNullOrWhiteSpace($EvidenceRoot)) {
                $args += @('-EvidenceRoot', $EvidenceRoot)
            }
            & pwsh @args
            # Preserve 44/45 (and other non-zero) so Admin Box callers can stop only on
            # genuine credential/non-package blockers after bounded package repair.
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            return
        }
    }
}
finally {
    Pop-Location
}
