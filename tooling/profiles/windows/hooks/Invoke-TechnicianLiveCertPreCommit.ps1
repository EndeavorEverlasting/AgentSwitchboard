[CmdletBinding()]
param(
    [string]$RootPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        throw 'Unable to resolve hook directory. Supply -RootPath explicitly.'
    }
    $RootPath = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
}
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

& git -C $RootPath --no-pager diff --cached --check
if ($LASTEXITCODE -ne 0) {
    throw "Staged diff hygiene failed with exit code $LASTEXITCODE."
}

$staged = @(& git -C $RootPath --no-pager diff --cached --name-only --diff-filter=ACMRTUXB)
if ($LASTEXITCODE -ne 0) {
    throw "Unable to inspect staged paths; git exited with $LASTEXITCODE."
}

$forbidden = @(
    $staged | Where-Object {
        $_ -match '(^|/)(runs|evidence|logs?)/' -or
        $_ -match 'technician-live-cert-harness-status\.(json|md)$' -or
        $_ -match 'operator-command-envelope-report\.(json|md)$' -or
        $_ -match 'preflight-summary\.json$' -or
        $_ -match 'stage-result\.json$'
    }
)
if ($forbidden.Count -gt 0) {
    throw "Generated technician evidence must not be committed: $($forbidden -join ', ')"
}

$tree = (& git -C $RootPath write-tree).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($tree)) {
    throw "Unable to write the staged Git tree; git exited with $LASTEXITCODE."
}

$snapshotCommit = (& git -C $RootPath `
    -c 'user.name=AgentSwitchboard Harness' `
    -c 'user.email=harness@localhost' `
    commit-tree $tree -p HEAD -m 'AgentSwitchboard staged pre-commit snapshot').Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($snapshotCommit)) {
    throw "Unable to create the staged snapshot commit; git exited with $LASTEXITCODE."
}

$snapshotRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('AgentSwitchboard-PreCommit-' + [guid]::NewGuid().ToString('N'))
$snapshotAdded = $false
$cleanupFailure = $null
$validationFailure = $null

try {
    & git -C $RootPath worktree add --detach $snapshotRoot $snapshotCommit
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to create the staged snapshot worktree; git exited with $LASTEXITCODE."
    }
    $snapshotAdded = $true

    $contractPath = Join-Path $snapshotRoot 'tooling\profiles\windows\harness\technician-live-cert\operator-command-contract.json'
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    $registered = @($contract.scanPaths | ForEach-Object { ([string]$_).Replace('\', '/') })

    $candidatePaths = @(
        $staged |
            Where-Object {
                $normalized = ([string]$_).Replace('\', '/')
                $extension = [System.IO.Path]::GetExtension($normalized).ToLowerInvariant()
                $extension -in @('.md', '.markdown', '.txt') -and $normalized -notin $registered
            } |
            ForEach-Object {
                $candidate = Join-Path $snapshotRoot ([string]$_)
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    $candidate
                }
            }
    )

    $operatorValidator = Join-Path $snapshotRoot 'scripts\Test-OperatorCommandEnvelope.ps1'
    & $operatorValidator -RootPath $snapshotRoot -CandidatePath $candidatePaths
    if ($LASTEXITCODE -ne 0) {
        throw "Operator command envelope validation failed for the staged snapshot with exit code $LASTEXITCODE."
    }

    $validator = Join-Path $snapshotRoot 'scripts\Test-TechnicianLiveCertHarness.ps1'
    & $validator -RootPath $snapshotRoot
    if ($LASTEXITCODE -ne 0) {
        throw "Technician live-cert harness validation failed for the staged snapshot with exit code $LASTEXITCODE."
    }
}
catch {
    $validationFailure = $_
}
finally {
    if ($snapshotAdded) {
        & git -C $RootPath worktree remove $snapshotRoot
        if ($LASTEXITCODE -ne 0) {
            $cleanupFailure = "Unable to remove the clean staged snapshot worktree '$snapshotRoot'; git exited with $LASTEXITCODE."
        }
    }
}

if ($null -ne $validationFailure) {
    throw $validationFailure
}
if ($null -ne $cleanupFailure) {
    throw $cleanupFailure
}

Write-Host 'Technician live-cert staged-snapshot pre-commit checks passed.' -ForegroundColor Green
exit 0
