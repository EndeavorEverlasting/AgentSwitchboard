[CmdletBinding()]
param(
    [string]$InstallRoot = "$env:LOCALAPPDATA\AgentSwitchboard\GnhfFleet",
    [string]$StatePath,
    [string]$OutputRoot,
    [switch]$NoWrite
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NullableText {
    param($Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $null
    }
    return [string]$Value
}

function New-ReadinessRecord {
    param(
        [Parameter(Mandatory)][string]$AgentId,
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$Adapter,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][bool]$Available,
        [Parameter(Mandatory)][bool]$ConfigurationKnown,
        $CommandPath,
        $Version,
        [Parameter(Mandatory)][string]$Evidence,
        [Parameter(Mandatory)][string[]]$NextSteps,
        [string[]]$Commands = @()
    )

    $normalizedCommandPath = Get-NullableText -Value $CommandPath
    $normalizedVersion = Get-NullableText -Value $Version

    return [pscustomobject][ordered]@{
        agentId = $AgentId
        displayName = $DisplayName
        adapter = $Adapter
        status = $Status
        available = $Available
        configurationKnown = $ConfigurationKnown
        commandPath = $normalizedCommandPath
        version = $normalizedVersion
        evidence = $Evidence
        nextSteps = @($NextSteps)
        commands = @($Commands)
    }
}

$InstallRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($InstallRoot))
if ([string]::IsNullOrWhiteSpace($StatePath)) {
    $StatePath = Join-Path $InstallRoot "state.json"
}
else {
    $StatePath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($StatePath))
}

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $InstallRoot "reports\startup"
}
else {
    $OutputRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($OutputRoot))
}

$stateObserved = Test-Path -LiteralPath $StatePath -PathType Leaf
$state = $null
if ($stateObserved) {
    $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
    if ($state.schemaVersion -ne 1 -or $null -eq $state.agents) {
        throw "Fleet state is malformed or unsupported: $StatePath"
    }
}

$records = [System.Collections.Generic.List[object]]::new()
$setupCommand = "Setup-AgentSwitchboard.cmd"

if (-not $stateObserved) {
    foreach ($definition in @(
        @("opencode", "OpenCode", "native GNHF"),
        @("deepseek", "DeepSeek", "OpenCode provider route"),
        @("goose", "Goose", "ACP"),
        @("agy", "Anti-Gravity", "ACP capability-gated"),
        @("copilot", "GitHub Copilot CLI", "native GNHF"),
        @("hermes", "Hermes", "ACP")
    )) {
        [void]$records.Add((New-ReadinessRecord `
            -AgentId $definition[0] `
            -DisplayName $definition[1] `
            -Adapter $definition[2] `
            -Status "not-configured" `
            -Available $false `
            -ConfigurationKnown $false `
            -Evidence "AgentSwitchboard fleet state has not been created on this workstation." `
            -NextSteps @("Run the repository setup launcher. It reuses healthy tools and records blocked agents without collecting credentials.") `
            -Commands @($setupCommand)))
    }
    $overallStatus = "not-configured"
}
else {
    $definitions = @(
        [pscustomobject]@{ Id = "opencode"; Name = "OpenCode"; Key = "opencode"; Adapter = "native GNHF" },
        [pscustomobject]@{ Id = "deepseek"; Name = "DeepSeek"; Key = "opencode"; Adapter = "OpenCode provider route" },
        [pscustomobject]@{ Id = "goose"; Name = "Goose"; Key = "goose"; Adapter = "ACP" },
        [pscustomobject]@{ Id = "agy"; Name = "Anti-Gravity"; Key = "agy"; Adapter = "ACP capability-gated" },
        [pscustomobject]@{ Id = "copilot"; Name = "GitHub Copilot CLI"; Key = "copilot"; Adapter = "native GNHF" },
        [pscustomobject]@{ Id = "hermes"; Name = "Hermes"; Key = "hermes"; Adapter = "ACP" }
    )

    foreach ($definition in $definitions) {
        $property = $state.agents.PSObject.Properties[$definition.Key]
        if ($null -eq $property) {
            [void]$records.Add((New-ReadinessRecord `
                -AgentId $definition.Id `
                -DisplayName $definition.Name `
                -Adapter $definition.Adapter `
                -Status "unknown" `
                -Available $false `
                -ConfigurationKnown $false `
                -Evidence "No fleet state record exists for '$($definition.Key)'." `
                -NextSteps @("Rerun setup to refresh local command and adapter discovery.") `
                -Commands @($setupCommand)))
            continue
        }

        $record = $property.Value
        if ($definition.Id -eq "deepseek") {
            if ([bool]$record.available) {
                [void]$records.Add((New-ReadinessRecord `
                    -AgentId "deepseek" `
                    -DisplayName "DeepSeek" `
                    -Adapter $definition.Adapter `
                    -Status "verification-required" `
                    -Available $true `
                    -ConfigurationKnown $false `
                    -CommandPath $record.commandPath `
                    -Version $record.version `
                    -Evidence "The OpenCode adapter is locally ready. Authentication, exact model availability, quota, and response are intentionally verified only by the bounded launch preflight." `
                    -NextSteps @(
                        "Use an exact deepseek/provider-model ID when launching.",
                        "Complete provider authentication interactively in OpenCode when the bounded launch preflight reports it is required."
                    ) `
                    -Commands @(
                        "opencode models deepseek",
                        "AgentSwitchboard.cmd -ListAgents"
                    )))
            }
            else {
                [void]$records.Add((New-ReadinessRecord `
                    -AgentId "deepseek" `
                    -DisplayName "DeepSeek" `
                    -Adapter $definition.Adapter `
                    -Status "blocked" `
                    -Available $false `
                    -ConfigurationKnown $false `
                    -CommandPath $record.commandPath `
                    -Version $record.version `
                    -Evidence "DeepSeek is blocked because its truthful OpenCode adapter is unavailable. $($record.evidence)" `
                    -NextSteps @("Repair OpenCode through AgentSwitchboard setup, then allow the bounded launch preflight to verify the provider route.") `
                    -Commands @($setupCommand)))
            }
            continue
        }

        if ([bool]$record.available) {
            [void]$records.Add((New-ReadinessRecord `
                -AgentId $definition.Id `
                -DisplayName $definition.Name `
                -Adapter $definition.Adapter `
                -Status "adapter-ready" `
                -Available $true `
                -ConfigurationKnown $false `
                -CommandPath $record.commandPath `
                -Version $record.version `
                -Evidence ([string]$record.evidence) `
                -NextSteps @("The local command and adapter contract are ready. Provider authentication and hosted response remain launch-time proof.") `
                -Commands @("AgentSwitchboard.cmd -Agent $($definition.Id) -PromptPath <path>")))
        }
        else {
            $nextSteps = switch ($definition.Id) {
                "goose" { @("Install or repair Goose, then require 'goose acp --help' to pass.", "Configure its provider interactively; do not put credentials in AgentSwitchboard state.") }
                "agy" { @("Install or repair Anti-Gravity.", "Supply an exact ACP launch command only after the installed CLI exposes and passes that interface.") }
                "copilot" { @("Rerun AgentSwitchboard setup to install or repair GitHub Copilot CLI.", "Authenticate interactively with the provider after installation.") }
                "hermes" { @("Rerun AgentSwitchboard setup to install or repair Hermes.", "Require both version and 'hermes acp --help' probes to pass.") }
                default { @("Rerun setup and inspect the recorded evidence.") }
            }
            [void]$records.Add((New-ReadinessRecord `
                -AgentId $definition.Id `
                -DisplayName $definition.Name `
                -Adapter $definition.Adapter `
                -Status "blocked" `
                -Available $false `
                -ConfigurationKnown $false `
                -CommandPath $record.commandPath `
                -Version $record.version `
                -Evidence ([string]$record.evidence) `
                -NextSteps $nextSteps `
                -Commands @($setupCommand)))
        }
    }

    $readyCount = @($records | Where-Object { $_.status -eq "adapter-ready" }).Count
    $blockedCount = @($records | Where-Object { $_.status -in @("blocked", "unknown") }).Count
    if ($readyCount -gt 0 -and $blockedCount -eq 0) {
        $overallStatus = "ready"
    }
    elseif ($readyCount -gt 0 -or @($records | Where-Object { $_.status -eq "verification-required" }).Count -gt 0) {
        $overallStatus = "partial"
    }
    else {
        $overallStatus = "blocked"
    }
}

$report = [pscustomobject][ordered]@{
    schema = "agentswitchboard.agent-startup-readiness.v1"
    generatedAt = (Get-Date).ToString("o")
    installRoot = $InstallRoot
    statePath = $StatePath
    stateObserved = $stateObserved
    overallStatus = $overallStatus
    agents = @($records)
    proofLevel = "local-adapter-readiness"
    proofCeiling = "This report proves only local fleet-state and adapter readiness. It does not prove provider authentication, exact model availability, quota, hosted response, repository delivery, deployment, or operator acceptance."
}

$jsonPath = $null
$markdownPath = $null
if (-not $NoWrite) {
    [void](New-Item -ItemType Directory -Path $OutputRoot -Force)
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
    $jsonPath = Join-Path $OutputRoot "agent-startup-readiness-$stamp.json"
    $markdownPath = Join-Path $OutputRoot "agent-startup-readiness-$stamp.md"
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM

    $markdown = [System.Collections.Generic.List[string]]::new()
    [void]$markdown.Add("# AgentSwitchboard Startup Readiness")
    [void]$markdown.Add("")
    [void]$markdown.Add("- Overall status: **$overallStatus**")
    [void]$markdown.Add("- State observed: **$stateObserved**")
    [void]$markdown.Add('- Proof level: `local-adapter-readiness`')
    [void]$markdown.Add("")
    [void]$markdown.Add("| Agent | Adapter | Status | Evidence |")
    [void]$markdown.Add("|---|---|---|---|")
    foreach ($item in $records) {
        $safeEvidence = ([string]$item.evidence).Replace("|", "\|").Replace("`r", " ").Replace("`n", " ")
        [void]$markdown.Add("| $($item.displayName) | $($item.adapter) | $($item.status) | $safeEvidence |")
    }
    [void]$markdown.Add("")
    [void]$markdown.Add("## Configuration guidance")
    foreach ($item in $records) {
        [void]$markdown.Add("")
        [void]$markdown.Add("### $($item.displayName)")
        foreach ($step in $item.nextSteps) {
            [void]$markdown.Add("- $step")
        }
        foreach ($command in $item.commands) {
            [void]$markdown.Add("- Command: ``$command``")
        }
    }
    [void]$markdown.Add("")
    [void]$markdown.Add("## Proof ceiling")
    [void]$markdown.Add("")
    [void]$markdown.Add($report.proofCeiling)
    $markdown -join [Environment]::NewLine | Set-Content -LiteralPath $markdownPath -Encoding utf8NoBOM
}

Write-Host ""
Write-Host "AgentSwitchboard startup readiness" -ForegroundColor Cyan
$overallColor = if ($overallStatus -eq "ready") { "Green" } else { "Yellow" }
Write-Host ("Overall: {0}" -f $overallStatus) -ForegroundColor $overallColor
$records | Select-Object displayName, adapter, status, evidence | Format-Table -AutoSize -Wrap

Write-Host "Guidance:" -ForegroundColor Cyan
foreach ($item in $records | Where-Object { $_.status -ne "adapter-ready" }) {
    Write-Host ("  {0}: {1}" -f $item.displayName, ($item.nextSteps -join " ")) -ForegroundColor Yellow
}
if ($jsonPath) {
    Write-Host "JSON report: $jsonPath" -ForegroundColor DarkCyan
    Write-Host "English report: $markdownPath" -ForegroundColor DarkCyan
}
Write-Host "Proof ceiling: $($report.proofCeiling)" -ForegroundColor DarkGray

$report
