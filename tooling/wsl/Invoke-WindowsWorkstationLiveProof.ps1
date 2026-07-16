[CmdletBinding()]
param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'tmux-gnhf-workstation.json'),
    [string]$SourceRepoPath,
    [string]$ArtifactRoot,
    [ValidateRange(15,300)][int]$WorkspaceWaitSeconds = 90,
    [ValidateRange(60,3600)][int]$GnhfTimeoutSeconds = 1200,
    [ValidateRange(1,10)][int]$MaxIterations = 2,
    [ValidateRange(1000,1000000)][int]$MaxTokens = 60000,
    [string]$ModelId,
    [switch]$SkipWorkspaceLaunch,
    [switch]$SkipGnhfBehaviorProof,
    [switch]$PlanOnly,
    [string]$WslExe = "$env:SystemRoot\System32\wsl.exe"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'This runtime proof requires PowerShell 7.' }
Import-Module (Join-Path $PSScriptRoot 'WindowsWorkstationLiveProof.Common.psm1') -Force
. (Join-Path $PSScriptRoot 'Invoke-WindowsWorkstationSessionProof.ps1')
. (Join-Path $PSScriptRoot 'Invoke-WindowsWorkstationGnhfProof.ps1')

$events = [Collections.Generic.List[object]]::new()
$failureReason=$null; $proofSessionName=$null; $sessionResult=$null; $gnhfResult=$null
$runtime=[ordered]@{
    floorSafe=$false; targetedValidation=$false; destructiveStopSkippedByDoctrine=$false; safeStart=$false
    launcherAttached=$false; targetSurfaceReady=$false; commandIssued=$false; commandAckObserved=$false
    behaviorObserved=$false; detachObserved=$false; persistenceObserved=$false; reattachObserved=$false
    runtimeArtifactCollected=$false; finalGitClean=$false; liveRuntime=$false
}

$resolvedManifest = (Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop).Path
$manifest = Get-Content -LiteralPath $resolvedManifest -Raw | ConvertFrom-Json
if ($manifest.schemaVersion -ne 1) { throw "Unsupported manifest schemaVersion: $($manifest.schemaVersion)" }
$distribution=[string]$manifest.distribution; $managedSession=[string]$manifest.workspace.sessionName
if ($distribution -notmatch '^[A-Za-z0-9._-]+$' -or $managedSession -notmatch '^[A-Za-z0-9_-]+$') { throw 'Unsafe distribution or tmux session name.' }
$installRoot=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$manifest.workspace.installRoot))
$startScript=Join-Path $installRoot 'Start-TmuxGnhfWorkspace.ps1'; $statusScript=Join-Path $installRoot 'Get-TmuxGnhfWorkspaceStatus.ps1'
if (-not $ArtifactRoot) { $ArtifactRoot=Join-Path (Join-Path $installRoot 'runtime-proof') (Get-Date -Format 'yyyyMMdd-HHmmss') }
$ArtifactRoot=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($ArtifactRoot)); New-Item -ItemType Directory -Path $ArtifactRoot -Force | Out-Null
$proofPath=Join-Path $ArtifactRoot 'windows-workstation-live-proof.json'; $eventPath=Join-Path $ArtifactRoot 'runtime-events.jsonl'
$nonce=[guid]::NewGuid().ToString('N'); $proofSessionName="as-proof-$($nonce.Substring(0,10))"

if ($PlanOnly) {
    [ordered]@{
        schemaVersion='agentswitchboard-windows-workstation-live-proof-plan/v1'; sourceRepoPath=$SourceRepoPath
        manifestPath=$resolvedManifest; workspaceInstallRoot=$installRoot; artifactRoot=$ArtifactRoot
        distribution=$distribution; managedSessionName=$managedSession; proofSessionName=$proofSessionName
        skipWorkspaceLaunch=[bool]$SkipWorkspaceLaunch; skipGnhfBehaviorProof=[bool]$SkipGnhfBehaviorProof; modelId=$ModelId
        safety=[ordered]@{disposableRepositoryOnly=$true;terminalFocusRequired=$false;destructiveStop=$false;personalDataMutation=$false;automaticPush=$false}
    } | ConvertTo-Json -Depth 10
    exit 0
}

$source=$null; $sourceBranch=$null; $sourceHead=$null
try {
    $source=Get-ProofSourceRepository -RequestedPath $SourceRepoPath -ConfigRoot $PSScriptRoot
    $status=Invoke-ProofBoundedProcess -FilePath $source.Git -ArgumentList @('-C',$source.Root,'status','--short') -TimeoutSeconds 20
    if ($status.ExitCode -ne 0 -or $status.Stdout) { throw 'Repository floor is not clean. Preserve unknown work and rerun from a clean checkout.' }
    $sourceBranch=(Invoke-ProofBoundedProcess -FilePath $source.Git -ArgumentList @('-C',$source.Root,'branch','--show-current') -TimeoutSeconds 20).Stdout.Trim()
    $sourceHead=(Invoke-ProofBoundedProcess -FilePath $source.Git -ArgumentList @('-C',$source.Root,'rev-parse','HEAD') -TimeoutSeconds 20).Stdout.Trim()
    if (-not $sourceBranch) { throw 'Detached HEAD is not allowed for workstation runtime proof.' }
    $runtime.floorSafe=$true; Add-ProofEvent -Events $events -Step repo-floor -State PASS -Message clean_attached_checkout -Data @{branch=$sourceBranch;head=$sourceHead}

    $validator=Join-Path $PSScriptRoot 'Test-WindowsWorkstationLiveProofContracts.ps1'; $pwsh=(Get-Command pwsh.exe -ErrorAction Stop).Source
    $validation=Invoke-ProofBoundedProcess -FilePath $pwsh -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$validator,'-RootPath',$PSScriptRoot,'-InstalledMode') -TimeoutSeconds 180
    if ($validation.ExitCode -ne 0) { throw "Targeted runtime proof contracts failed. $($validation.Output)" }
    foreach ($required in @($startScript,$statusScript)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Required installed workspace script is missing: $required" }
        $tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($required,[ref]$tokens,[ref]$errors)
        if ($errors.Count) { throw "Installed workspace script does not parse: $required" }
    }
    $runtime.targetedValidation=$true; Add-ProofEvent -Events $events -Step targeted-validation -State PASS -Message runtime_and_installed_launcher_contracts_passed
    $runtime.destructiveStopSkippedByDoctrine=$true; Add-ProofEvent -Events $events -Step stop-safe-start -State INFO -Message destructive_stop_skipped_persistent_session_reuse_is_repo_doctrine

    if (-not $SkipWorkspaceLaunch) {
        $start=Invoke-ProofBoundedProcess -FilePath $pwsh -ArgumentList @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$startScript) -TimeoutSeconds 90
        if ($start.ExitCode -ne 0) { throw "Repo-owned workspace launcher failed. $($start.Output)" }
        Add-ProofEvent -Events $events -Step safe-start -State PASS -Message repo_owned_workspace_launcher_completed
    } else { Add-ProofEvent -Events $events -Step safe-start -State SKIP -Message workspace_launch_skipped_by_operator_existing_runtime_required }
    $runtime.safeStart=$true
    $preStatus=& $statusScript
    if (-not $preStatus.keepAliveRunning -or -not $preStatus.sessionAvailable) { throw 'Managed workspace is not ready after safe start.' }
    Add-ProofEvent -Events $events -Step managed-workspace-status -State PASS -Message keepalive_and_managed_session_ready

    $wezTerm=Find-ProofWezTermCli; if (-not $wezTerm) { throw 'wezterm.exe was not found.' }
    $sessionResult=Invoke-WindowsWorkstationSessionProof -WslExe $WslExe -Distribution $distribution -WezTermCli $wezTerm -SessionName $proofSessionName -Nonce $nonce -WaitSeconds $WorkspaceWaitSeconds -Events $events
    $runtime.launcherAttached=$true; $runtime.targetSurfaceReady=$true; $runtime.commandIssued=$true; $runtime.commandAckObserved=$true
    $runtime.detachObserved=$true; $runtime.persistenceObserved=$true; $runtime.reattachObserved=$true

    if ($SkipGnhfBehaviorProof) { Add-ProofEvent -Events $events -Step gnhf-behavior -State SKIP -Message gnhf_behavior_proof_skipped_by_operator }
    else {
        $gnhfResult=Invoke-WindowsWorkstationGnhfProof -WslExe $WslExe -Distribution $distribution -SessionName $proofSessionName -ArtifactRoot $ArtifactRoot -Nonce $nonce -RequestedModel $ModelId -MaxIterations $MaxIterations -MaxTokens $MaxTokens -TimeoutSeconds $GnhfTimeoutSeconds -Events $events
        $runtime.behaviorObserved=$true
    }

    $diff=Invoke-ProofBoundedProcess -FilePath $source.Git -ArgumentList @('-C',$source.Root,'diff','--check') -TimeoutSeconds 30
    $final=Invoke-ProofBoundedProcess -FilePath $source.Git -ArgumentList @('-C',$source.Root,'status','--short') -TimeoutSeconds 30
    if ($diff.ExitCode -ne 0 -or $final.ExitCode -ne 0 -or $final.Stdout) { throw 'Source repository hygiene changed during runtime proof.' }
    $runtime.finalGitClean=$true; Add-ProofEvent -Events $events -Step final-git-hygiene -State PASS -Message git_diff_check_and_status_clean
}
catch { $failureReason=$_.Exception.Message; Add-ProofEvent -Events $events -Step runtime-proof -State FAIL -Message $failureReason }
finally {
    if ($proofSessionName) { try { [void](Invoke-ProofWslBash -WslExe $WslExe -Distribution $distribution -Command "tmux kill-session -t $(ConvertTo-ProofBashSingleQuoted $proofSessionName) 2>/dev/null || true" -TimeoutSeconds 20) } catch {} }
    $runtime.liveRuntime=($runtime.floorSafe -and $runtime.targetedValidation -and $runtime.destructiveStopSkippedByDoctrine -and $runtime.safeStart -and $runtime.launcherAttached -and $runtime.targetSurfaceReady -and $runtime.commandIssued -and $runtime.commandAckObserved -and ($runtime.behaviorObserved -or $SkipGnhfBehaviorProof) -and $runtime.detachObserved -and $runtime.persistenceObserved -and $runtime.reattachObserved -and $runtime.finalGitClean)
    $proofLevel = if ($runtime.liveRuntime -and $runtime.behaviorObserved) {'live-windows-wsl-tmux-gnhf-behavior-observed'} elseif ($runtime.launcherAttached -and $runtime.persistenceObserved -and $runtime.reattachObserved) {'live-wezterm-wsl-tmux-session-persistence'} elseif ($runtime.commandAckObserved) {'launcher-and-command-ack'} elseif ($runtime.targetedValidation) {'targeted-static-validation'} else {'preflight-only'}
    $runtime.runtimeArtifactCollected=$true
    $result=[ordered]@{
        schemaVersion='agentswitchboard-windows-workstation-live-proof/v1'; completedAt=(Get-Date).ToString('o')
        status=if($failureReason){'failed'}else{'completed'}; proofLevel=$proofLevel
        proofCeiling=if($runtime.behaviorObserved){'process, tmux session, captured terminal output, and committed disposable GNHF behavior observed; no pixel-level GUI rendering claim'}else{"no higher than $proofLevel; no hosted-agent behavior claim"}
        failureReason=$failureReason
        runtimeState=[ordered]@{distribution=$distribution;managedSessionName=$managedSession;proofSessionName=$proofSessionName;sourceRepoPath=if($source){$source.Root}else{$null};sourceBranch=$sourceBranch;sourceHead=$sourceHead;workspaceInstallRoot=$installRoot;artifactRoot=$ArtifactRoot;selectedAgent=if($gnhfResult){$gnhfResult.Agent}else{$null};selectedModel=if($gnhfResult){$gnhfResult.Model}else{$null};disposableRepositoryPath=if($gnhfResult){$gnhfResult.RepositoryPath}else{$null};gnhfProofBranch=if($gnhfResult){$gnhfResult.Branch}else{$null};gnhfProofCommit=if($gnhfResult){$gnhfResult.Commit}else{$null}}
        proof=$runtime
        handoff=[ordered]@{schemaVersion='agentswitchboard-workstation-runtime-handoff/v1';readyForAutomatedAgents=[bool]($runtime.liveRuntime -and $runtime.behaviorObserved);readyForSysAdminSuiteTandem=[bool]($runtime.liveRuntime -and $runtime.behaviorObserved);proofPath=$proofPath;eventLogPath=$eventPath;gnhfLogPath=if($gnhfResult){$gnhfResult.LogPath}else{$null};agent=if($gnhfResult){$gnhfResult.Agent}else{$null};model=if($gnhfResult){$gnhfResult.Model}else{$null};branch=if($gnhfResult){$gnhfResult.Branch}else{$null};commit=if($gnhfResult){$gnhfResult.Commit}else{$null}}
        events=@($events)
    }
    Write-ProofAtomicJson -Value $result -Path $proofPath
    $events | ForEach-Object { $_ | ConvertTo-Json -Depth 12 -Compress } | Set-Content -LiteralPath $eventPath -Encoding utf8NoBOM
    Write-Host "[PASS] Runtime proof artifact: $proofPath" -ForegroundColor Green
    Write-Host "[PASS] Runtime event log:     $eventPath" -ForegroundColor Green
    Write-Host "Proof level reached: $proofLevel" -ForegroundColor Cyan
}
if ($failureReason) { throw $failureReason }
