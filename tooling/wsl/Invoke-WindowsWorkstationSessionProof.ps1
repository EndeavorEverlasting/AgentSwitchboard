function Invoke-WindowsWorkstationSessionProof {
    [CmdletBinding()]
    param(
        [string]$WslExe, [string]$Distribution, [string]$WezTermCli,
        [string]$SessionName, [string]$Nonce, [int]$WaitSeconds,
        [Collections.Generic.List[object]]$Events
    )
    $processIds = [Collections.Generic.List[int]]::new()
    $windowId = $null
    $create = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command "tmux new-session -d -s $(ConvertTo-ProofBashSingleQuoted $SessionName) -n runtime-proof 'bash --noprofile --norc'" -TimeoutSeconds 30
    if ($create.ExitCode -ne 0) { throw "Unable to create disposable tmux proof session. $($create.Output)" }
    Add-ProofEvent -Events $Events -Step 'proof-session' -State PASS -Message 'disposable_tmux_session_created' -Data @{sessionName=$SessionName}

    $first = Start-ProofWezTermAttach -WezTermCli $WezTermCli -WslExe $WslExe -Distribution $Distribution -SessionName $SessionName
    [void]$processIds.Add($first.Id)
    if (-not (Wait-ProofCondition -TimeoutSeconds $WaitSeconds -Condition { (Get-ProofTmuxClients -WslExe $WslExe -Distribution $Distribution -SessionName $SessionName).Count -gt 0 })) {
        throw "WezTerm did not attach to the disposable tmux session within $WaitSeconds seconds."
    }
    Add-ProofEvent -Events $Events -Step 'launcher-session-attach' -State PASS -Message 'wezterm_process_and_tmux_client_observed' -Data @{wezTermPid=$first.Id}

    $window = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command "tmux list-windows -t $(ConvertTo-ProofBashSingleQuoted $SessionName) -F '#{window_id}' | head -n 1" -TimeoutSeconds 15
    if ($window.ExitCode -ne 0 -or -not $window.Stdout) { throw 'Unable to resolve the disposable tmux proof window.' }
    $windowId = $window.Stdout.Trim()
    $marker = "AGENTSWITCHBOARD_TMUX_ACK:$Nonce"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($marker))
    $command = "printf '%s' '$encoded' | base64 -d; printf '\n'"
    $send = "tmux send-keys -t $(ConvertTo-ProofBashSingleQuoted $windowId) -l -- $(ConvertTo-ProofBashSingleQuoted $command) && tmux send-keys -t $(ConvertTo-ProofBashSingleQuoted $windowId) C-m"
    $issued = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command $send -TimeoutSeconds 15
    if ($issued.ExitCode -ne 0) { throw "Unable to issue focus-independent tmux command. $($issued.Output)" }
    if (-not (Wait-ProofCondition -TimeoutSeconds 30 -Condition { (Get-ProofTmuxCapture -WslExe $WslExe -Distribution $Distribution -Target $windowId) -match [regex]::Escape($marker) })) {
        throw 'The tmux command was issued but its nonce output was not captured.'
    }
    Add-ProofEvent -Events $Events -Step 'surface-and-command-ack' -State PASS -Message 'tmux_capture_contains_exact_nonce' -Data @{marker=$marker;windowId=$windowId}

    $detach = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command "tmux detach-client -s $(ConvertTo-ProofBashSingleQuoted $SessionName)" -TimeoutSeconds 15
    if ($detach.ExitCode -ne 0 -or -not (Wait-ProofCondition -TimeoutSeconds $WaitSeconds -Condition { (Get-ProofTmuxClients -WslExe $WslExe -Distribution $Distribution -SessionName $SessionName).Count -eq 0 })) {
        throw 'The disposable tmux client did not detach cleanly.'
    }
    Add-ProofEvent -Events $Events -Step detach -State PASS -Message 'no_clients_attached_to_disposable_session'

    $exists = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command "tmux has-session -t $(ConvertTo-ProofBashSingleQuoted $SessionName)" -TimeoutSeconds 15
    if ($exists.ExitCode -ne 0 -or (Get-ProofTmuxCapture -WslExe $WslExe -Distribution $Distribution -Target $windowId) -notmatch [regex]::Escape($marker)) {
        throw 'The disposable tmux session or marker did not survive detach.'
    }
    Add-ProofEvent -Events $Events -Step 'detached-persistence' -State PASS -Message 'session_window_and_marker_survived_detach'

    $second = Start-ProofWezTermAttach -WezTermCli $WezTermCli -WslExe $WslExe -Distribution $Distribution -SessionName $SessionName
    [void]$processIds.Add($second.Id)
    if (-not (Wait-ProofCondition -TimeoutSeconds $WaitSeconds -Condition { (Get-ProofTmuxClients -WslExe $WslExe -Distribution $Distribution -SessionName $SessionName).Count -gt 0 })) {
        throw 'WezTerm did not reattach to the disposable tmux session.'
    }
    if ((Get-ProofTmuxCapture -WslExe $WslExe -Distribution $Distribution -Target $windowId) -notmatch [regex]::Escape($marker)) { throw 'The original marker was absent after reattach.' }
    Add-ProofEvent -Events $Events -Step reattach -State PASS -Message 'same_session_window_and_marker_reattached' -Data @{wezTermPid=$second.Id}

    [pscustomobject]@{ SessionName=$SessionName; WindowId=$windowId; Marker=$marker; ProcessIds=@($processIds) }
}
