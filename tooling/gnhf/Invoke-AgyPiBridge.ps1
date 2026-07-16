[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$IgnoredPiArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-BridgeStatus {
    param(
        [Parameter(Mandatory)][string]$Classification,
        [Parameter(Mandatory)][int]$ExitCode,
        [string]$Summary,
        [string]$Model
    )

    $statusPath = $env:AGENTSWITCHBOARD_AGY_STATUS_PATH
    if ([string]::IsNullOrWhiteSpace($statusPath)) {
        return
    }

    $parent = Split-Path -Parent $statusPath
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    [ordered]@{
        schemaVersion = 1
        completedAt = (Get-Date).ToString("o")
        classification = $Classification
        exitCode = $ExitCode
        modelMode = if ($Model) { "explicit" } else { "agy-default" }
        model = $Model
        summary = $Summary
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusPath -Encoding utf8NoBOM
}

function Get-Classification {
    param(
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][string]$Text
    )

    if ($ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($Text)) {
        return "success"
    }

    if ($Text -match '(?i)(individual\s+quota\s+(has\s+been\s+)?reached|quota\s*(is\s*)?(reached|exhausted|exceeded)|usage\s+limit\s+(reached|exceeded)|free\s+(token|credit)s?\s+(are\s+)?(exhausted|used\s+up)|no\s+(free\s+)?tokens?\s+remaining|insufficient\s+(credit|balance)|credit\s+balance\s+(is\s+)?(empty|exhausted)|token\s+allowance\s+(is\s+)?exhausted)') {
        return "quota-exhausted"
    }

    if ($Text -match '(?i)(429|too many requests|rate.?limit)') {
        return "rate-limited"
    }

    if ($Text -match '(?i)(unauthorized|forbidden|authentication|login required|sign in)') {
        return "authentication-required"
    }

    return "agent-error"
}

function Get-JsonCandidate {
    param([Parameter(Mandatory)][string]$Text)

    $trimmed = $Text.Trim()
    if (-not $trimmed) {
        return $null
    }

    try {
        $null = $trimmed | ConvertFrom-Json -ErrorAction Stop
        return $trimmed
    }
    catch {}

    $lines = @($trimmed -split "\r?\n")
    for ($index = $lines.Count - 1; $index -ge 0; $index--) {
        $candidate = $lines[$index].Trim()
        if (-not $candidate.StartsWith("{")) {
            continue
        }
        try {
            $null = $candidate | ConvertFrom-Json -ErrorAction Stop
            return $candidate
        }
        catch {}
    }

    $firstBrace = $trimmed.IndexOf("{")
    $lastBrace = $trimmed.LastIndexOf("}")
    if ($firstBrace -ge 0 -and $lastBrace -gt $firstBrace) {
        $candidate = $trimmed.Substring($firstBrace, $lastBrace - $firstBrace + 1)
        try {
            $null = $candidate | ConvertFrom-Json -ErrorAction Stop
            return $candidate
        }
        catch {}
    }

    return $trimmed
}

function Write-PiEvent {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][int]$InputTokens,
        [Parameter(Mandatory)][int]$OutputTokens,
        [string]$StopReason,
        [string]$ErrorMessage
    )

    $message = [ordered]@{
        role = "assistant"
        content = $Content
        usage = [ordered]@{
            input = $InputTokens
            output = $OutputTokens
            cacheRead = 0
            cacheWrite = 0
        }
    }

    if ($StopReason) {
        $message.stopReason = $StopReason
    }
    if ($ErrorMessage) {
        $message.errorMessage = $ErrorMessage
    }

    [ordered]@{
        type = "agent_end"
        messages = @($message)
    } | ConvertTo-Json -Depth 10 -Compress | Write-Output
}

$agy = Get-Command agy -ErrorAction SilentlyContinue
if (-not $agy) {
    $message = "AGY command was not found on PATH."
    Write-BridgeStatus -Classification "agent-error" -ExitCode 127 -Summary $message
    Write-PiEvent -Content $message -InputTokens 0 -OutputTokens 0 -StopReason "error" -ErrorMessage $message
    exit 0
}

$prompt = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($prompt)) {
    $message = "AGY bridge received an empty prompt from GNHF."
    Write-BridgeStatus -Classification "agent-error" -ExitCode 2 -Summary $message
    Write-PiEvent -Content $message -InputTokens 0 -OutputTokens 0 -StopReason "error" -ErrorMessage $message
    exit 0
}

$model = $env:AGENTSWITCHBOARD_AGY_MODEL
$arguments = [System.Collections.Generic.List[string]]::new()
[void]$arguments.Add("--mode")
[void]$arguments.Add("accept-edits")
[void]$arguments.Add("--dangerously-skip-permissions")
if (-not [string]::IsNullOrWhiteSpace($model)) {
    [void]$arguments.Add("--model")
    [void]$arguments.Add($model)
}
[void]$arguments.Add("--print")
[void]$arguments.Add($prompt)

$psi = [Diagnostics.ProcessStartInfo]::new()
$psi.FileName = $agy.Source
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
foreach ($argument in $arguments) {
    [void]$psi.ArgumentList.Add($argument)
}

$process = [Diagnostics.Process]::new()
$process.StartInfo = $psi
[void]$process.Start()
$stdoutTask = $process.StandardOutput.ReadToEndAsync()
$stderrTask = $process.StandardError.ReadToEndAsync()
$process.WaitForExit()

$stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
$stderr = $stderrTask.GetAwaiter().GetResult().Trim()
$combined = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
$classification = Get-Classification -ExitCode $process.ExitCode -Text $combined
$summary = if ($combined.Length -gt 600) { $combined.Substring(0, 600) } else { $combined }
$summary = $summary -replace '(?i)(sk-[A-Za-z0-9_-]+)', '[redacted]'

Write-BridgeStatus -Classification $classification -ExitCode $process.ExitCode -Summary $summary -Model $model

$inputTokens = [Math]::Max(1, [Math]::Ceiling($prompt.Length / 4.0))
if ($classification -eq "success") {
    $finalText = Get-JsonCandidate -Text $stdout
    $outputTokens = [Math]::Max(1, [Math]::Ceiling($finalText.Length / 4.0))
    Write-PiEvent -Content $finalText -InputTokens $inputTokens -OutputTokens $outputTokens
    exit 0
}

$errorText = if ($combined) { $combined } else { "AGY exited without a usable response." }
Write-PiEvent -Content $errorText -InputTokens $inputTokens -OutputTokens 0 -StopReason "error" -ErrorMessage $errorText
exit 0
