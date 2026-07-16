Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-ProofBoundedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [ValidateRange(1, 7200)][int]$TimeoutSeconds = 30,
        [string]$WorkingDirectory
    )
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    foreach ($argument in $ArgumentList) { [void]$psi.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $psi; [void]$process.Start()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync(); $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
    if ($timedOut) { try { $process.Kill($true); $process.WaitForExit() } catch {} }
    $stdout = $stdoutTask.GetAwaiter().GetResult(); $stderr = $stderrTask.GetAwaiter().GetResult()
    [pscustomobject]@{
        ExitCode = if ($timedOut) { 124 } else { $process.ExitCode }
        TimedOut = $timedOut
        Stdout = $stdout.Trim()
        Stderr = $stderr.Trim()
        Output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
}

function Invoke-ProofWslBash {
    [CmdletBinding()]
    param([string]$WslExe, [string]$Distribution, [string]$Command, [int]$TimeoutSeconds = 30)
    Invoke-ProofBoundedProcess -FilePath $WslExe -ArgumentList @('-d', $Distribution, '-e', 'bash', '-lc', $Command) -TimeoutSeconds $TimeoutSeconds
}

function Wait-ProofCondition {
    [CmdletBinding()]
    param([scriptblock]$Condition, [int]$TimeoutSeconds, [int]$PollMilliseconds = 750)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (& $Condition) { return $true }
        Start-Sleep -Milliseconds $PollMilliseconds
    } while ((Get-Date) -lt $deadline)
    return $false
}

function ConvertTo-ProofBashSingleQuoted {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Value)
    $single = [string][char]39; $double = [string][char]34
    $embedded = $single + $double + $single + $double + $single
    $single + $Value.Replace($single, $embedded) + $single
}

function ConvertTo-ProofWslPath {
    [CmdletBinding()]
    param([string]$WindowsPath)
    $resolved = [IO.Path]::GetFullPath($WindowsPath)
    if ($resolved -notmatch '^(?<drive>[A-Za-z]):\\(?<rest>.*)$') { throw "Only drive-letter paths can be mapped to WSL: $resolved" }
    "/mnt/$($Matches.drive.ToLowerInvariant())/$($Matches.rest -replace '\\','/')"
}

function Find-ProofWezTermCli {
    $command = Get-Command wezterm.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($root in @((Join-Path $env:ProgramFiles 'WezTerm'), (Join-Path $env:LOCALAPPDATA 'Programs\WezTerm'))) {
        if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        $candidate = Get-ChildItem -LiteralPath $root -Filter wezterm.exe -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }
    return $null
}

function Get-ProofTmuxClients {
    param([string]$WslExe, [string]$Distribution, [string]$SessionName)
    $result = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command "tmux list-clients -F '#{session_name}|#{client_tty}' 2>/dev/null || true" -TimeoutSeconds 10
    @($result.Stdout -split '\r?\n' | Where-Object { $_ -and $_ -like "${SessionName}|*" })
}

function Get-ProofTmuxCapture {
    param([string]$WslExe, [string]$Distribution, [string]$Target)
    $quoted = ConvertTo-ProofBashSingleQuoted $Target
    (Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command "tmux capture-pane -p -t $quoted -S -200 2>/dev/null || true" -TimeoutSeconds 15).Stdout
}

function Start-ProofWezTermAttach {
    param([string]$WezTermCli, [string]$WslExe, [string]$Distribution, [string]$SessionName)
    $psi = [Diagnostics.ProcessStartInfo]::new(); $psi.FileName = $WezTermCli; $psi.UseShellExecute = $false
    foreach ($argument in @('start','--always-new-process','--',$WslExe,'-d',$Distribution,'-e','bash','-lc',"exec tmux attach-session -t $(ConvertTo-ProofBashSingleQuoted $SessionName)")) {
        [void]$psi.ArgumentList.Add($argument)
    }
    [Diagnostics.Process]::Start($psi)
}

function Add-ProofEvent {
    param([Collections.Generic.List[object]]$Events, [string]$Step, [ValidateSet('PASS','FAIL','SKIP','INFO')][string]$State, [string]$Message, [hashtable]$Data = @{})
    $event = [pscustomobject][ordered]@{ at=(Get-Date).ToString('o'); step=$Step; state=$State; message=$Message; data=$Data }
    $Events.Add($event)
    $color = switch ($State) { 'PASS' {'Green'} 'FAIL' {'Red'} 'SKIP' {'Yellow'} default {'Cyan'} }
    Write-Host "[$State] $Step - $Message" -ForegroundColor $color
}

function Write-ProofAtomicJson {
    param($Value, [string]$Path, [int]$Depth = 30)
    $parent = Split-Path -Parent $Path; if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $temp = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $temp -Encoding utf8NoBOM
    Move-Item -LiteralPath $temp -Destination $Path -Force
}

function Get-ProofSourceRepository {
    param([string]$RequestedPath, [string]$ConfigRoot)
    if ($RequestedPath) { $candidate = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($RequestedPath)) }
    else {
        $configPath = Join-Path $ConfigRoot 'windows-workstation-live-proof.config.json'
        if (Test-Path -LiteralPath $configPath -PathType Leaf) {
            $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            $candidate = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$config.sourceRepoPath))
        } else { $candidate = $ConfigRoot }
    }
    $git = Get-Command git.exe -ErrorAction SilentlyContinue; if (-not $git) { $git = Get-Command git -ErrorAction Stop }
    $root = Invoke-ProofBoundedProcess -FilePath $git.Source -ArgumentList @('-C',$candidate,'rev-parse','--show-toplevel') -TimeoutSeconds 20
    if ($root.ExitCode -ne 0 -or -not $root.Stdout) { throw "Unable to resolve source repository from '$candidate'." }
    [pscustomobject]@{ Root=$root.Stdout.Trim(); Git=$git.Source }
}

function Resolve-ProofDeepSeekModel {
    param([string]$WslExe, [string]$Distribution, [string]$RequestedModel)
    $auth = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command 'opencode auth list' -TimeoutSeconds 45
    $modelsResult = Invoke-ProofWslBash -WslExe $WslExe -Distribution $Distribution -Command 'opencode models --refresh' -TimeoutSeconds 120
    if ($modelsResult.ExitCode -ne 0) { throw "WSL OpenCode model discovery failed. $($modelsResult.Output)" }
    $ansi = [regex]'\x1B\[[0-?]*[ -/]*[@-~]'
    $models = @($modelsResult.Stdout -split '\r?\n' | ForEach-Object { $ansi.Replace($_,'').Trim() } | Where-Object { $_ -match '^[A-Za-z0-9._-]+/[A-Za-z0-9][A-Za-z0-9._:/-]*$' } | Sort-Object -Unique)
    if ($auth.ExitCode -ne 0 -or $auth.Output -notmatch '(?i)deepseek') { throw 'WSL OpenCode did not report authenticated DeepSeek credentials. Authenticate inside Ubuntu, then rerun.' }
    if ($RequestedModel) {
        if ($models -notcontains $RequestedModel) { throw "Requested model '$RequestedModel' was not reported by WSL OpenCode." }
        $selected = $RequestedModel
    } else {
        $selected = @('deepseek/deepseek-v4-pro','deepseek/deepseek-chat','deepseek/deepseek-reasoner') | Where-Object { $models -contains $_ } | Select-Object -First 1
        if (-not $selected) { $selected = $models | Where-Object { $_ -like 'deepseek/*' } | Select-Object -First 1 }
    }
    if (-not $selected) { throw 'No DeepSeek provider/model identifier was reported by WSL OpenCode.' }
    [pscustomobject]@{ ModelId=$selected; ModelCount=$models.Count; DeepSeekAuthReported=$true }
}

Export-ModuleMember -Function *-Proof*
