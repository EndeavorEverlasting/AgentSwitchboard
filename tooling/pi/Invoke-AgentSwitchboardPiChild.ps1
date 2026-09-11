[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PromptPath,
    [Parameter(Mandatory)][string]$RepositoryPath,
    [Parameter(Mandatory)][ValidateSet('architect','builder','validator','adjudicator','scout')][string]$Role,
    [ValidateSet('read-only','writer')][string]$WriteMode = 'read-only',
    [string]$InvocationId,
    [string]$Provider,
    [string]$Model,
    [ValidateRange(30,7200)][int]$TimeoutSeconds = 900,
    [ValidateRange(1000,24000)][int]$MaximumPromptCharacters = 12000,
    [ValidateRange(1000,24000)][int]$MaximumResultCharacters = 12000,
    [string]$OutputDirectory,
    [string]$RootPath = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') { throw 'The managed Pi child adapter is Windows-only in v1.' }
if ([string]::IsNullOrWhiteSpace($env:ProgramFiles)) { throw 'ProgramFiles is required for the managed Pi child runtime.' }

$RootPath = (Resolve-Path -LiteralPath $RootPath -ErrorAction Stop).Path
$PromptPath = (Resolve-Path -LiteralPath $PromptPath -ErrorAction Stop).Path
$RepositoryPath = (Resolve-Path -LiteralPath $RepositoryPath -ErrorAction Stop).Path
if (-not (Test-Path -LiteralPath $PromptPath -PathType Leaf)) { throw "Prompt file is not a regular file: $PromptPath" }
if (-not (Test-Path -LiteralPath $RepositoryPath -PathType Container)) { throw "Repository path is not a directory: $RepositoryPath" }

$verificationPath = Join-Path $RootPath 'tooling\pi\harness\upstream-verification.json'
if (-not (Test-Path -LiteralPath $verificationPath -PathType Leaf)) { throw "Tracked Pi upstream verification is missing: $verificationPath" }
$verification = Get-Content -LiteralPath $verificationPath -Raw | ConvertFrom-Json -ErrorAction Stop
$version = [string]$verification.version
$runtimePath = Join-Path $env:ProgramFiles "AgentSwitchboard\agents\pi\$version\pi.exe"
if ([string]::IsNullOrWhiteSpace($InvocationId)) { $InvocationId = 'pi-child-' + ([guid]::NewGuid().ToString('N').Substring(0,12)) }
if ($InvocationId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$') { throw 'InvocationId must be 1-80 characters using letters, numbers, dot, underscore, or dash.' }

$pathTrimCharacters = [char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
function Normalize-ComparisonPath {
    param([Parameter(Mandatory)][string]$Path)
    return [IO.Path]::GetFullPath($Path).TrimEnd($pathTrimCharacters)
}

$runId = '{0}-{1}' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')), ([guid]::NewGuid().ToString('N').Substring(0,8))
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $stateBase = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [IO.Path]::GetTempPath() }
    $OutputDirectory = Join-Path $stateBase "AgentSwitchboard\PiHarness\child-runs\$runId"
}
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$repoFull = Normalize-ComparisonPath -Path $RepositoryPath
$outputFull = Normalize-ComparisonPath -Path $OutputDirectory
if ($outputFull.StartsWith($repoFull + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $outputFull -ieq $repoFull) {
    throw 'Child-agent evidence must remain outside the repository/worktree.'
}
$null = New-Item -ItemType Directory -Path $OutputDirectory -Force
$rawEventPath = Join-Path $OutputDirectory 'pi-events.jsonl'
$stderrPath = Join-Path $OutputDirectory 'pi-stderr.txt'
$resultPath = Join-Path $OutputDirectory 'child-result.json'
$reportPath = Join-Path $OutputDirectory 'child-result.md'

function Invoke-BoundedProcess {
    param([Parameter(Mandatory)][string]$FilePath,[string[]]$ArgumentList,[string]$WorkingDirectory,[int]$Timeout)
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.CreateNoWindow = $true
    $psi.FileName = $FilePath
    $psi.WorkingDirectory = $WorkingDirectory
    foreach ($argument in @($ArgumentList)) { [void]$psi.ArgumentList.Add([string]$argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    $process.StandardInput.Close()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit($Timeout * 1000)
    if ($timedOut) {
        try { $process.Kill($true) } catch {}
        try { $process.WaitForExit() } catch {}
    }
    return [pscustomobject]@{
        ExitCode = if ($timedOut) { $null } else { $process.ExitCode }
        TimedOut = $timedOut
        Stdout = [string]$stdoutTask.GetAwaiter().GetResult()
        Stderr = [string]$stderrTask.GetAwaiter().GetResult()
    }
}

function Get-Version {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $probe = Invoke-BoundedProcess -FilePath $Path -ArgumentList @('--version') -WorkingDirectory $RepositoryPath -Timeout 30
    if ($probe.TimedOut -or $probe.ExitCode -ne 0) { return $null }
    $match = [regex]::Match((($probe.Stdout,$probe.Stderr) -join "`n"),'(?<!\d)(\d+\.\d+\.\d+)(?!\d)')
    if (-not $match.Success) { return $null }
    return $match.Groups[1].Value
}

$git = Get-Command git.exe -ErrorAction SilentlyContinue
if (-not $git) { $git = Get-Command git -ErrorAction SilentlyContinue }
if (-not $git) { throw 'Git is required to establish child-agent repository identity.' }

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments,[switch]$AllowFailure)
    $result = Invoke-BoundedProcess -FilePath $git.Source -ArgumentList (@('-C',$RepositoryPath) + $Arguments) -WorkingDirectory $RepositoryPath -Timeout 30
    if (-not $AllowFailure -and ($result.TimedOut -or $result.ExitCode -ne 0)) {
        throw "Git command failed: git -C <repo> $($Arguments -join ' ') :: $($result.Stderr)"
    }
    return $result
}

function Get-GitValue {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $result = Invoke-Git -Arguments $Arguments
    return $result.Stdout.Trim()
}

$repoRoot = Get-GitValue -Arguments @('rev-parse','--show-toplevel')
if ((Normalize-ComparisonPath -Path $repoRoot) -ine $repoFull) { throw "RepositoryPath must be the exact Git worktree root. Git reports: $repoRoot" }
$branchBefore = Get-GitValue -Arguments @('branch','--show-current')
$headBefore = Get-GitValue -Arguments @('rev-parse','HEAD')
$statusBefore = (Invoke-Git -Arguments @('status','--porcelain=v1','--untracked-files=normal')).Stdout.Trim()
$gitDir = Get-GitValue -Arguments @('rev-parse','--path-format=absolute','--git-dir')
$gitCommonDir = Get-GitValue -Arguments @('rev-parse','--path-format=absolute','--git-common-dir')
$originHeadProbe = Invoke-Git -Arguments @('symbolic-ref','--quiet','--short','refs/remotes/origin/HEAD') -AllowFailure
$defaultBranch = if ($originHeadProbe.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($originHeadProbe.Stdout)) { ($originHeadProbe.Stdout.Trim() -replace '^origin/','') } else { 'main' }
$isIsolatedLinkedWorktree = (Normalize-ComparisonPath -Path $gitDir) -ine (Normalize-ComparisonPath -Path $gitCommonDir)

if ($WriteMode -eq 'writer') {
    if ([string]::IsNullOrWhiteSpace($branchBefore)) { throw 'Writer child requires an attached branch.' }
    if ($branchBefore -in @('main','master',$defaultBranch)) { throw "Writer child may not run on the default branch: $branchBefore" }
    if (-not [string]::IsNullOrWhiteSpace($statusBefore)) { throw 'Writer child requires a clean worktree before provider invocation.' }
    if (-not $isIsolatedLinkedWorktree) {
        throw 'Writer child requires an isolated linked Git worktree; the primary checkout is not accepted as a writer lane.'
    }
}

$runtimeVersion = Get-Version -Path $runtimePath
if ($runtimeVersion -ne $version) {
    throw "Managed Pi runtime is missing or drifted. Expected $version at $runtimePath; run Bootstrap-Pi-SystemWide.cmd first."
}

$prompt = Get-Content -LiteralPath $PromptPath -Raw -ErrorAction Stop
if ([string]::IsNullOrWhiteSpace($prompt)) { throw 'Prompt packet is empty.' }
if ($prompt.Length -gt $MaximumPromptCharacters) {
    throw "Prompt packet exceeds the bounded child-context limit of $MaximumPromptCharacters characters. Reduce the packet to the evidence and scope the child actually needs."
}
$tools = if ($WriteMode -eq 'writer') { 'read,grep,find,ls,write,edit,bash' } else { 'read,grep,find,ls' }
$name = ($InvocationId -replace '[^A-Za-z0-9._-]','-')
$arguments = [System.Collections.Generic.List[string]]::new()
foreach ($argument in @('--mode','json','--no-session','--no-extensions','--no-skills','--no-prompt-templates','--no-approve','--tools',$tools,'--name',$name)) { [void]$arguments.Add($argument) }
if (-not [string]::IsNullOrWhiteSpace($Provider)) { [void]$arguments.Add('--provider'); [void]$arguments.Add($Provider) }
if (-not [string]::IsNullOrWhiteSpace($Model)) { [void]$arguments.Add('--model'); [void]$arguments.Add($Model) }
[void]$arguments.Add($prompt)

$startedAt = [DateTime]::UtcNow
$run = Invoke-BoundedProcess -FilePath $runtimePath -ArgumentList @($arguments) -WorkingDirectory $RepositoryPath -Timeout $TimeoutSeconds
$completedAt = [DateTime]::UtcNow
[IO.File]::WriteAllText($rawEventPath,$run.Stdout,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($stderrPath,$run.Stderr,[Text.UTF8Encoding]::new($false))

$events = [System.Collections.Generic.List[object]]::new()
foreach ($rawLine in @($run.Stdout -split "`n")) {
    $line = $rawLine.TrimEnd("`r")
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try { [void]$events.Add(($line | ConvertFrom-Json -ErrorAction Stop)) } catch {}
}
$agentEnd = @($events | Where-Object { [string]$_.type -eq 'agent_end' } | Select-Object -Last 1)
$agentEndObserved = $agentEnd.Count -eq 1
$finalText = ''
if ($agentEndObserved) {
    $assistantMessages = @($agentEnd[0].messages | Where-Object { [string]$_.role -eq 'assistant' })
    if ($assistantMessages.Count -gt 0) {
        $message = $assistantMessages[-1]
        if ($message.content -is [string]) { $finalText = [string]$message.content }
        else {
            $parts = [System.Collections.Generic.List[string]]::new()
            foreach ($item in @($message.content)) {
                $textProperty = $item.PSObject.Properties['text']
                if ($textProperty -and -not [string]::IsNullOrWhiteSpace([string]$textProperty.Value)) { [void]$parts.Add([string]$textProperty.Value) }
            }
            $finalText = $parts -join "`n"
        }
    }
}
if ($finalText.Length -gt $MaximumResultCharacters) { $finalText = $finalText.Substring(0,$MaximumResultCharacters) + "`n<bounded result truncated>" }

$branchAfter = Get-GitValue -Arguments @('branch','--show-current')
$headAfter = Get-GitValue -Arguments @('rev-parse','HEAD')
$statusAfter = (Invoke-Git -Arguments @('status','--porcelain=v1','--untracked-files=normal')).Stdout.Trim()
$failureCode = $null
if ($run.TimedOut) { $failureCode = 'PI_CHILD_TIMEOUT' }
elseif ($run.ExitCode -ne 0) { $failureCode = 'PI_CHILD_NONZERO_EXIT' }
elseif (-not $agentEndObserved) { $failureCode = 'PI_CHILD_AGENT_END_MISSING' }
elseif ($branchAfter -ne $branchBefore) { $failureCode = 'PI_CHILD_BRANCH_CHANGED' }
elseif ($WriteMode -eq 'read-only' -and ($headAfter -ne $headBefore -or $statusAfter -ne $statusBefore)) { $failureCode = 'PI_CHILD_READ_ONLY_MUTATION' }
$status = if ($failureCode) { 'failed' } else { 'completed-unvalidated' }

$result = [ordered]@{
    schema = 'agentswitchboard.child-agent-result.v1'
    invocationId = $InvocationId
    status = $status
    failureCode = $failureCode
    role = $Role
    writeMode = $WriteMode
    startedAt = $startedAt.ToString('o')
    completedAt = $completedAt.ToString('o')
    runtimePath = $runtimePath
    runtimeVersion = $runtimeVersion
    providerRequested = if ($Provider) { $Provider } else { $null }
    modelRequested = if ($Model) { $Model } else { $null }
    repositoryPath = $RepositoryPath
    isolatedLinkedWorktree = $isIsolatedLinkedWorktree
    defaultBranchObserved = $defaultBranch
    branchBefore = $branchBefore
    headBefore = $headBefore
    worktreeStatusBefore = $statusBefore
    branchAfter = $branchAfter
    headAfter = $headAfter
    worktreeStatusAfter = $statusAfter
    exitCode = $run.ExitCode
    timedOut = [bool]$run.TimedOut
    agentEndObserved = $agentEndObserved
    boundedFinalText = $finalText
    rawEventPath = $rawEventPath
    stderrPath = $stderrPath
    rawPromptIncluded = $false
    rawEventMayContainPrompt = $true
    coordinatorValidationRequired = $true
    proofCeiling = 'Process/runtime/repository guard and agent_end evidence only. The coordinator must validate task-specific artifacts, tests, diffs, commits, and integration claims independently.'
}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath -Encoding utf8NoBOM
@(
    '# AgentSwitchboard Pi child result','',
    "- Invocation: ``$InvocationId``",
    "- Status: ``$status``",
    "- Failure: ``$failureCode``",
    "- Role: ``$Role``",
    "- Write mode: ``$WriteMode``",
    "- Runtime: ``$runtimePath`` @ ``$runtimeVersion``",
    "- Repository: ``$RepositoryPath``",
    "- Branch/head: ``$branchBefore@$headBefore`` -> ``$branchAfter@$headAfter``",
    "- Timed out: ``$($run.TimedOut)``",
    "- agent_end observed: ``$agentEndObserved``",
    "- Raw events: ``$rawEventPath``",'',
    'The bounded final text is stored in child-result.json. Treat child completion as unvalidated until task-specific repository evidence is checked by the coordinator.'
) | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM

Write-Host "PI_CHILD_STATUS=$status"
Write-Host "PI_CHILD_FAILURE_CODE=$failureCode"
Write-Host "PI_CHILD_RESULT=$resultPath"
Write-Host "PI_CHILD_EVENTS=$rawEventPath"
if ($failureCode) { exit 1 }
exit 0
