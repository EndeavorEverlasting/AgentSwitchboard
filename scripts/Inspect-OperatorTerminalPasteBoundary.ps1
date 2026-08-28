[CmdletBinding(DefaultParameterSetName = 'Clipboard')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Text')]
    [AllowEmptyString()]
    [string]$Text,

    [Parameter(Mandatory, ParameterSetName = 'InputPath')]
    [string]$InputPath,

    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EncodingName {
    param([AllowNull()][object]$Encoding)

    if ($null -eq $Encoding) { return $null }
    try { return [string]$Encoding.WebName } catch { return [string]$Encoding }
}

$captureSource = $PSCmdlet.ParameterSetName
$inputIdentity = $null
switch ($PSCmdlet.ParameterSetName) {
    'Text' {
        $captured = [string]$Text
        $inputIdentity = 'provided-text'
    }
    'InputPath' {
        $resolvedInput = (Resolve-Path -LiteralPath $InputPath -ErrorAction Stop).Path
        $captured = Get-Content -LiteralPath $resolvedInput -Raw
        if ($null -eq $captured) { $captured = '' }
        $inputIdentity = Split-Path -Leaf $resolvedInput
    }
    default {
        $clipboardCommand = Get-Command Get-Clipboard -ErrorAction SilentlyContinue
        if (-not $clipboardCommand) {
            throw 'Get-Clipboard is unavailable. Supply -Text or -InputPath for a read-only capture.'
        }
        $captured = Get-Clipboard -Raw
        if ($null -eq $captured) { $captured = '' }
        $inputIdentity = 'clipboard'
    }
}

$questionMarkCount = 0
$replacementCharacterCount = 0
foreach ($character in $captured.ToCharArray()) {
    $codeUnit = [int][char]$character
    if ($codeUnit -eq 0x003F) { $questionMarkCount++ }
    if ($codeUnit -eq 0xFFFD) { $replacementCharacterCount++ }
}

$classification = if ($replacementCharacterCount -gt 0) {
    'captured-input-contains-replacement-character'
}
elseif ($questionMarkCount -gt 0) {
    'captured-input-contains-question-mark'
}
else {
    'captured-input-clean-presentation-unproven'
}

$utf8 = [System.Text.UTF8Encoding]::new($false)
$bytes = $utf8.GetBytes($captured)
$sha256 = [Convert]::ToHexString(
    [System.Security.Cryptography.SHA256]::HashData($bytes)
).ToLowerInvariant()

$runId = '{0}-{1}' -f (
    (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
), ([guid]::NewGuid().ToString('N').Substring(0, 8))

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $base = if ($env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\operator-command-delivery\runs'
    }
    else {
        Join-Path ([IO.Path]::GetTempPath()) 'AgentSwitchboard/operator-command-delivery/runs'
    }
    $OutputPath = Join-Path (Join-Path $base $runId) 'terminal-paste-boundary-result.json'
}

$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $OutputPath
$null = New-Item -ItemType Directory -Path $outputDirectory -Force

$result = [ordered]@{
    schema = 'agentswitchboard.terminal-paste-boundary-result.v1'
    runId = $runId
    status = 'observed'
    classification = $classification
    captureSource = $captureSource.ToLowerInvariant()
    inputIdentity = $inputIdentity
    utf16CodeUnitCount = $captured.Length
    utf8ByteCount = $bytes.Length
    utf8Sha256 = $sha256
    literalQuestionMarkCount = $questionMarkCount
    replacementCharacterCount = $replacementCharacterCount
    shell = [ordered]@{
        hostName = $Host.Name
        psVersion = $PSVersionTable.PSVersion.ToString()
        consoleInputEncoding = Get-EncodingName -Encoding ([Console]::InputEncoding)
        consoleOutputEncoding = Get-EncodingName -Encoding ([Console]::OutputEncoding)
        outputEncoding = Get-EncodingName -Encoding $OutputEncoding
    }
    terminalHints = [ordered]@{
        wtSessionPresent = -not [string]::IsNullOrWhiteSpace($env:WT_SESSION)
        termProgram = $env:TERM_PROGRAM
        term = $env:TERM
    }
    rawTextPersisted = $false
    proofLevel = 'input-capture'
    proofCeiling = 'Proves only the captured text observed by this read-only probe plus shell encoding metadata. Clean captured text does not prove correct terminal glyph rendering, font coverage, PSReadLine behavior, WezTerm configuration, tmux presentation, or operator acceptance.'
    evidencePath = $OutputPath
}

$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM

Write-Host "CLASSIFICATION=$classification"
Write-Host "CAPTURE_SOURCE=$($result.captureSource)"
Write-Host "QUESTION_MARK_COUNT=$questionMarkCount"
Write-Host "REPLACEMENT_CHARACTER_COUNT=$replacementCharacterCount"
Write-Host "ARTIFACT=$OutputPath"
Write-Host "PROOF_CEILING=$($result.proofCeiling)"
