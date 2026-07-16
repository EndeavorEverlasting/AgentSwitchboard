function Invoke-WindowsWorkstationGnhfProof {
    [CmdletBinding()]
    param(
        [string]$WslExe, [string]$Distribution, [string]$SessionName,
        [string]$ArtifactRoot, [string]$Nonce, [string]$RequestedModel,
        [int]$MaxIterations, [int]$MaxTokens, [int]$TimeoutSeconds,
        [Collections.Generic.List[object]]$Events
    )
    $toolCheck = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command 'command -v git && command -v gnhf && command -v opencode && git --version && gnhf --version && opencode --version' -TimeoutSeconds 60
    if ($toolCheck.ExitCode -ne 0) { throw "WSL GNHF toolchain is incomplete. $($toolCheck.Output)" }
    Add-ProofEvent -Events $Events -Step 'wsl-toolchain' -State PASS -Message 'git_gnhf_and_opencode_acknowledged'

    $model = Resolve-ProofDeepSeekModel -WslExe $WslExe -Distribution $Distribution -RequestedModel $RequestedModel
    Add-ProofEvent -Events $Events -Step 'model-selection' -State PASS -Message 'exact_wsl_opencode_model_selected' -Data @{model=$model.ModelId;modelCount=$model.ModelCount;deepSeekAuthReported=$true}

    $repoPath = Join-Path $ArtifactRoot 'disposable-repo'; $promptPath = Join-Path $ArtifactRoot 'gnhf-objective.md'
    $runnerPath = Join-Path $ArtifactRoot 'run-gnhf-proof.sh'; $logPath = Join-Path $ArtifactRoot 'gnhf-runtime.log'
    $wslRepo = ConvertTo-ProofWslPath $repoPath; $wslPrompt = ConvertTo-ProofWslPath $promptPath
    $wslRunner = ConvertTo-ProofWslPath $runnerPath; $wslLog = ConvertTo-ProofWslPath $logPath
    $quotedRepo = ConvertTo-ProofBashSingleQuoted $wslRepo
    $initCommand = @(
        'set -euo pipefail', "mkdir -p $quotedRepo", "git init -b main $quotedRepo >/dev/null",
        "git -C $quotedRepo config user.name 'AgentSwitchboard Runtime Proof'",
        "git -C $quotedRepo config user.email 'runtime-proof@invalid.local'",
        "printf '%s\n' '# Disposable AgentSwitchboard runtime proof repository' > $quotedRepo/README.md",
        "git -C $quotedRepo add README.md", "git -C $quotedRepo commit -m 'chore: initialize runtime proof fixture' >/dev/null"
    ) -join '; '
    $init = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command $initCommand -TimeoutSeconds 60
    if ($init.ExitCode -ne 0) { throw "Unable to create disposable WSL Git repository. $($init.Output)" }
    Add-ProofEvent -Events $Events -Step 'disposable-repository' -State PASS -Message 'safe_git_fixture_initialized' -Data @{path=$repoPath}

    @"
Create exactly one file at the repository root named agent-runtime-proof.json.
The file must be valid JSON with exactly these values:
{
  "schemaVersion": 1,
  "nonce": "$Nonce",
  "behavior": "gnhf-agent-created-and-committed",
  "safeState": true
}
Do not modify README.md or any other file.
Commit agent-runtime-proof.json.
Stop only after git status is clean and the file exists in HEAD.
"@ | Set-Content -LiteralPath $promptPath -Encoding utf8NoBOM

    $runtimeConfig = [ordered]@{
        '$schema'='https://opencode.ai/config.json'; model=$model.ModelId; small_model=$model.ModelId; share='disabled'
        provider=[ordered]@{deepseek=[ordered]@{options=[ordered]@{timeout=600000;chunkTimeout=60000}}}
    }
    $config64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($runtimeConfig | ConvertTo-Json -Depth 10 -Compress)))
    $stopWhen = "agent-runtime-proof.json is committed with nonce $Nonce, git status is clean, and no other file changed."
    @"
#!/usr/bin/env bash
set -uo pipefail
repo=$(ConvertTo-ProofBashSingleQuoted $wslRepo)
prompt=$(ConvertTo-ProofBashSingleQuoted $wslPrompt)
log=$(ConvertTo-ProofBashSingleQuoted $wslLog)
export GNHF_TELEMETRY=0
export OPENCODE_CONFIG_CONTENT="`$(printf '%s' $(ConvertTo-ProofBashSingleQuoted $config64) | base64 -d)"
printf 'AGENTSWITCHBOARD_GNHF_STARTED:%s\n' $(ConvertTo-ProofBashSingleQuoted $Nonce) | tee "`$log"
cd "`$repo" || exit 90
set +e
cat "`$prompt" | gnhf --agent opencode --worktree --max-iterations $MaxIterations --max-tokens $MaxTokens --stop-when $(ConvertTo-ProofBashSingleQuoted $stopWhen) --prevent-sleep on >>"`$log" 2>&1
code=`$?
set -e
printf 'AGENTSWITCHBOARD_GNHF_EXIT:%s\n' "`$code" | tee -a "`$log"
printf 'AGENTSWITCHBOARD_GNHF_FINISHED:%s\n' $(ConvertTo-ProofBashSingleQuoted $Nonce) | tee -a "`$log"
exec bash --noprofile --norc
"@ | Set-Content -LiteralPath $runnerPath -Encoding utf8NoBOM

    $target = ConvertTo-ProofBashSingleQuoted "${SessionName}:"
    $window = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command "tmux new-window -d -P -F '#{window_id}' -t $target -n gnhf-proof $(ConvertTo-ProofBashSingleQuoted "bash $(ConvertTo-ProofBashSingleQuoted $wslRunner)")" -TimeoutSeconds 30
    if ($window.ExitCode -ne 0 -or -not $window.Stdout) { throw "Unable to launch GNHF proof window. $($window.Output)" }
    Add-ProofEvent -Events $Events -Step 'gnhf-trigger' -State PASS -Message 'bounded_gnhf_command_issued' -Data @{windowId=$window.Stdout.Trim();model=$model.ModelId}

    if (-not (Wait-ProofCondition -TimeoutSeconds 60 -Condition { (Test-Path -LiteralPath $logPath) -and ((Get-Content -LiteralPath $logPath -Raw) -match "AGENTSWITCHBOARD_GNHF_STARTED:$Nonce") })) {
        throw 'The GNHF command was issued but its start ACK was not observed.'
    }
    Add-ProofEvent -Events $Events -Step 'gnhf-command-ack' -State PASS -Message 'exact_gnhf_start_nonce_observed'
    if (-not (Wait-ProofCondition -TimeoutSeconds $TimeoutSeconds -PollMilliseconds 2000 -Condition { (Test-Path -LiteralPath $logPath) -and ((Get-Content -LiteralPath $logPath -Raw) -match "AGENTSWITCHBOARD_GNHF_FINISHED:$Nonce") })) {
        throw "GNHF proof did not finish within $TimeoutSeconds seconds."
    }
    $log = Get-Content -LiteralPath $logPath -Raw
    $exitMatch = [regex]::Match($log,'AGENTSWITCHBOARD_GNHF_EXIT:(\d+)')
    if (-not $exitMatch.Success -or [int]$exitMatch.Groups[1].Value -ne 0) { throw "GNHF did not return a successful exit. Review $logPath." }

    $branches = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command "git -C $quotedRepo for-each-ref --format='%(refname:short)|%(objectname)' refs/heads/gnhf" -TimeoutSeconds 30
    $proofBranch=$null; $proofCommit=$null
    foreach ($line in @($branches.Stdout -split '\r?\n' | Where-Object { $_ })) {
        if ($line -notmatch '^([^|]+)\|([0-9a-f]{40})$') { continue }
        $branch=$Matches[1]; $commit=$Matches[2]
        $show = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command "git -C $quotedRepo show $(ConvertTo-ProofBashSingleQuoted "${branch}:agent-runtime-proof.json") 2>/dev/null || true" -TimeoutSeconds 30
        if (-not $show.Stdout) { continue }
        try { $payload=$show.Stdout | ConvertFrom-Json } catch { continue }
        $propertyNames = @($payload.PSObject.Properties.Name | Sort-Object)
        $expectedPropertyNames = @('behavior','nonce','safeState','schemaVersion')
        $hasExactProperties = ($propertyNames.Count -eq $expectedPropertyNames.Count -and @(Compare-Object -ReferenceObject $expectedPropertyNames -DifferenceObject $propertyNames).Count -eq 0)
        $diff = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command "git -C $quotedRepo diff --name-only main...$(ConvertTo-ProofBashSingleQuoted $branch)" -TimeoutSeconds 30
        $changed=@($diff.Stdout -split '\r?\n' | Where-Object { $_ })
        if ($hasExactProperties -and $payload.schemaVersion -eq 1 -and $payload.nonce -eq $Nonce -and $payload.behavior -eq 'gnhf-agent-created-and-committed' -and $payload.safeState -eq $true -and $changed.Count -eq 1 -and $changed[0] -eq 'agent-runtime-proof.json') {
            $proofBranch=$branch; $proofCommit=$commit; break
        }
    }
    if (-not $proofBranch) { throw 'No GNHF branch contained the exact four-property committed proof payload with an isolated one-file diff.' }

    $worktreeList = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command "git -C $quotedRepo worktree list --porcelain" -TimeoutSeconds 30
    if ($worktreeList.ExitCode -ne 0) { throw "Unable to enumerate GNHF worktrees. $($worktreeList.Output)" }
    $proofWorktreePath = $null
    $currentWorktreePath = $null
    foreach ($worktreeLine in @($worktreeList.Stdout -split '\r?\n')) {
        if ($worktreeLine.StartsWith('worktree ')) { $currentWorktreePath = $worktreeLine.Substring(9) }
        elseif ($worktreeLine -eq "branch refs/heads/$proofBranch") { $proofWorktreePath = $currentWorktreePath; break }
        elseif ([string]::IsNullOrWhiteSpace($worktreeLine)) { $currentWorktreePath = $null }
    }
    if (-not $proofWorktreePath) { throw "The worktree backing proof branch '$proofBranch' was not found." }
    $quotedProofWorktree = ConvertTo-ProofBashSingleQuoted $proofWorktreePath
    $proofWorktreeStatus = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command "git -C $quotedProofWorktree status --porcelain=v1" -TimeoutSeconds 30
    $proofWorktreeDiff = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command "git -C $quotedProofWorktree diff --check" -TimeoutSeconds 30
    if ($proofWorktreeStatus.ExitCode -ne 0 -or $proofWorktreeStatus.Stdout -or $proofWorktreeDiff.ExitCode -ne 0) {
        throw "The GNHF proof worktree is not clean: $proofWorktreePath"
    }

    $baseStatus = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command "git -C $quotedRepo status --porcelain=v1" -TimeoutSeconds 30
    if ($baseStatus.ExitCode -ne 0 -or $baseStatus.Stdout) { throw 'Disposable base repository was mutated by the GNHF proof.' }
    Add-ProofEvent -Events $Events -Step 'behavior-observed' -State PASS -Message 'gnhf_agent_created_and_committed_exact_proof_artifact' -Data @{agent='opencode';model=$model.ModelId;branch=$proofBranch;commit=$proofCommit;proofFile='agent-runtime-proof.json';proofNonce=$Nonce;proofWorktreePath=$proofWorktreePath;proofWorktreeClean=$true}
    [pscustomobject]@{ Agent='opencode';Model=$model.ModelId;Branch=$proofBranch;Commit=$proofCommit;LogPath=$logPath;RepositoryPath=$repoPath;WorktreePath=$proofWorktreePath }
}
