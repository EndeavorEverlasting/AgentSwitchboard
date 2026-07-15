Set-StrictMode -Version Latest

function Get-GnhfNumericProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        [double]$Default = 0
    )

    $property = $Object.PSObject.Properties[$Name]
    if (-not $property -or $null -eq $property.Value -or [string]::IsNullOrWhiteSpace([string]$property.Value)) {
        return $Default
    }
    return [double]$property.Value
}

function Get-GnhfBooleanProperty {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string]$Name,
        [bool]$Default = $false
    )

    $property = $Object.PSObject.Properties[$Name]
    if (-not $property -or $null -eq $property.Value) {
        return $Default
    }
    return [bool]$property.Value
}

function Get-GnhfSnapshotRecord {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][string]$ProfileId
    )

    foreach ($record in @($Snapshot.profiles)) {
        if ([string]$record.profileId -eq $ProfileId) {
            return $record
        }
    }
    return $null
}

function Get-GnhfSnapshotFreshness {
    param(
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)]$Policy,
        [datetimeoffset]$Now = [DateTimeOffset]::UtcNow
    )

    $capturedAtProperty = $Snapshot.PSObject.Properties["capturedAt"]
    if (-not $capturedAtProperty -or [string]::IsNullOrWhiteSpace([string]$capturedAtProperty.Value)) {
        return [pscustomobject]@{
            acceptable = $false
            reason = "usage-snapshot-captured-at-missing"
            capturedAt = $null
            ageSeconds = $null
        }
    }

    $capturedAt = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$capturedAtProperty.Value, [ref]$capturedAt)) {
        return [pscustomobject]@{
            acceptable = $false
            reason = "usage-snapshot-captured-at-invalid"
            capturedAt = $null
            ageSeconds = $null
        }
    }

    $maxAgeMinutes = Get-GnhfNumericProperty -Object $Policy -Name "maxUsageSnapshotAgeMinutes" -Default 30
    $futureSkewMinutes = Get-GnhfNumericProperty -Object $Policy -Name "maxUsageSnapshotFutureSkewMinutes" -Default 5
    $ageSeconds = [long][Math]::Floor(($Now.ToUniversalTime() - $capturedAt.ToUniversalTime()).TotalSeconds)

    if ($ageSeconds -lt (-60 * $futureSkewMinutes)) {
        return [pscustomobject]@{
            acceptable = $false
            reason = "usage-snapshot-from-future"
            capturedAt = $capturedAt.ToString("o")
            ageSeconds = $ageSeconds
        }
    }

    if ($maxAgeMinutes -gt 0 -and $ageSeconds -gt (60 * $maxAgeMinutes)) {
        return [pscustomobject]@{
            acceptable = $false
            reason = "usage-snapshot-stale"
            capturedAt = $capturedAt.ToString("o")
            ageSeconds = $ageSeconds
        }
    }

    return [pscustomobject]@{
        acceptable = $true
        reason = "usage-snapshot-fresh"
        capturedAt = $capturedAt.ToString("o")
        ageSeconds = [Math]::Max(0, $ageSeconds)
    }
}

function Get-GnhfProfileRoutingState {
    param(
        [Parameter(Mandatory)]$Profile,
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][ValidateSet("maximize-sprint-completion", "maximize-token-efficiency")][string]$Mode,
        [Parameter(Mandatory)]$Policy
    )

    $snapshotRecord = Get-GnhfSnapshotRecord -Snapshot $Snapshot -ProfileId ([string]$Profile.id)
    $enabled = Get-GnhfBooleanProperty -Object $Profile -Name "enabled" -Default $true
    $ready = $false
    $authenticated = $false
    $tokensKnown = $false
    $tokensRemaining = 0.0
    $tokenCapacity = 0.0
    $blockedReason = $null

    if ($snapshotRecord) {
        $ready = Get-GnhfBooleanProperty -Object $snapshotRecord -Name "ready" -Default $false
        $authenticated = Get-GnhfBooleanProperty -Object $snapshotRecord -Name "authenticated" -Default $false
        if ($snapshotRecord.PSObject.Properties["tokensRemaining"] -and $null -ne $snapshotRecord.tokensRemaining) {
            $tokensKnown = $true
            $tokensRemaining = [double]$snapshotRecord.tokensRemaining
        }
        if ($snapshotRecord.PSObject.Properties["tokenCapacity"] -and $null -ne $snapshotRecord.tokenCapacity) {
            $tokenCapacity = [double]$snapshotRecord.tokenCapacity
        }
        if ($snapshotRecord.PSObject.Properties["blockedReason"]) {
            $blockedReason = [string]$snapshotRecord.blockedReason
        }
    }

    $profileReserve = Get-GnhfNumericProperty -Object $Profile -Name "reserveTokens" -Default 0
    $reservePercent = Get-GnhfNumericProperty -Object $Policy -Name "reservePercent" -Default 30
    if ($Profile.PSObject.Properties["reservePercent"] -and $null -ne $Profile.reservePercent) {
        $reservePercent = [double]$Profile.reservePercent
    }

    $reserveTokens = if ($Mode -eq "maximize-sprint-completion") {
        0.0
    }
    else {
        [Math]::Max($profileReserve, [Math]::Floor($tokenCapacity * ($reservePercent / 100.0)))
    }

    $usableTokens = if ($tokensKnown) {
        [Math]::Max(0.0, $tokensRemaining - $reserveTokens)
    }
    else {
        $null
    }

    $minimumSegmentTokens = Get-GnhfNumericProperty -Object $Profile -Name "minimumSegmentTokens" -Default 10000
    $eligible = $enabled -and $ready -and $authenticated
    $reason = "eligible"

    if (-not $enabled) {
        $eligible = $false
        $reason = "profile-disabled"
    }
    elseif (-not $snapshotRecord) {
        $eligible = $false
        $reason = "snapshot-missing"
    }
    elseif (-not $ready) {
        $eligible = $false
        $reason = if ($blockedReason) { $blockedReason } else { "profile-not-ready" }
    }
    elseif (-not $authenticated) {
        $eligible = $false
        $reason = "authentication-required"
    }
    elseif ($Mode -eq "maximize-token-efficiency" -and -not $tokensKnown) {
        $eligible = $false
        $reason = "token-availability-unknown"
    }
    elseif ($tokensKnown -and $Mode -eq "maximize-sprint-completion" -and $tokensRemaining -le 0) {
        $eligible = $false
        $reason = "tokens-exhausted"
    }
    elseif ($tokensKnown -and $Mode -eq "maximize-token-efficiency" -and $usableTokens -lt $minimumSegmentTokens) {
        $eligible = $false
        $reason = "reserve-floor-reached"
    }

    return [pscustomobject]@{
        profileId = [string]$Profile.id
        agent = [string]$Profile.agent
        agentSpec = if ($Profile.PSObject.Properties["agentSpec"]) { [string]$Profile.agentSpec } else { [string]$Profile.agent }
        model = if ($Profile.PSObject.Properties["model"]) { [string]$Profile.model } else { $null }
        enabled = $enabled
        ready = $ready
        authenticated = $authenticated
        eligible = $eligible
        eligibilityReason = $reason
        tokensKnown = $tokensKnown
        tokensRemaining = if ($tokensKnown) { [long][Math]::Floor($tokensRemaining) } else { $null }
        tokenCapacity = if ($tokenCapacity -gt 0) { [long][Math]::Floor($tokenCapacity) } else { $null }
        reserveTokens = [long][Math]::Floor($reserveTokens)
        usableTokens = if ($null -ne $usableTokens) { [long][Math]::Floor($usableTokens) } else { $null }
        minimumSegmentTokens = [long][Math]::Floor($minimumSegmentTokens)
        completionPriority = [int](Get-GnhfNumericProperty -Object $Profile -Name "completionPriority" -Default 100)
        efficiencyPriority = [int](Get-GnhfNumericProperty -Object $Profile -Name "efficiencyPriority" -Default 100)
        segmentMaxTokens = [long](Get-GnhfNumericProperty -Object $Profile -Name "segmentMaxTokens" -Default 250000)
    }
}

function Select-GnhfRoutingProfile {
    param(
        [Parameter(Mandatory)][ValidateSet("maximize-sprint-completion", "maximize-token-efficiency")][string]$Mode,
        [Parameter(Mandatory)][object[]]$Profiles,
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)]$Policy,
        [string]$PreviousProfileId,
        [string]$PreviousOutcome,
        [hashtable]$SegmentCounts = @{},
        [datetimeoffset]$Now = [DateTimeOffset]::UtcNow
    )

    $states = @(
        foreach ($profile in $Profiles) {
            Get-GnhfProfileRoutingState -Profile $profile -Snapshot $Snapshot -Mode $Mode -Policy $Policy
        }
    )

    $freshness = Get-GnhfSnapshotFreshness -Snapshot $Snapshot -Policy $Policy -Now $Now
    if (-not $freshness.acceptable) {
        foreach ($state in $states) {
            $state.eligible = $false
            $state.eligibilityReason = $freshness.reason
        }
        return [pscustomobject]@{
            selected = $null
            states = $states
            reason = $freshness.reason
            usageSnapshot = $freshness
        }
    }

    $eligible = @($states | Where-Object { $_.eligible })
    if ($eligible.Count -eq 0) {
        return [pscustomobject]@{
            selected = $null
            states = $states
            reason = if ($Mode -eq "maximize-token-efficiency") { "all-profiles-at-reserve-or-unavailable" } else { "all-profiles-exhausted-or-unavailable" }
            usageSnapshot = $freshness
        }
    }

    $switchOutcomes = @("quota-exhausted", "authentication-blocked", "permanent-error", "timed-out", "profile-unavailable", "failed")
    if ($Mode -eq "maximize-sprint-completion" -and $PreviousProfileId -and $PreviousOutcome -notin $switchOutcomes) {
        $current = $eligible | Where-Object { $_.profileId -eq $PreviousProfileId } | Select-Object -First 1
        if ($current) {
            return [pscustomobject]@{
                selected = $current
                states = $states
                reason = "continue-current-profile-until-exhausted"
                usageSnapshot = $freshness
            }
        }
    }

    if ($Mode -eq "maximize-sprint-completion") {
        $candidatePool = $eligible
        if ($PreviousProfileId -and $PreviousOutcome -in $switchOutcomes) {
            $alternatives = @($eligible | Where-Object { $_.profileId -ne $PreviousProfileId })
            if ($alternatives.Count -gt 0) {
                $candidatePool = $alternatives
            }
        }
        $selected = $candidatePool |
            Sort-Object completionPriority, @{ Expression = { if ($_.tokensKnown) { -1 * $_.tokensRemaining } else { 0 } } }, profileId |
            Select-Object -First 1
        return [pscustomobject]@{
            selected = $selected
            states = $states
            reason = if ($PreviousProfileId) { "switch-after-exhaustion-or-block" } else { "highest-completion-priority" }
            usageSnapshot = $freshness
        }
    }

    $alternatives = @($eligible | Where-Object { $_.profileId -ne $PreviousProfileId })
    $candidatePool = if ($alternatives.Count -gt 0) { $alternatives } else { $eligible }
    $selected = $candidatePool |
        Sort-Object `
            efficiencyPriority,
            @{ Expression = { if ($SegmentCounts.ContainsKey($_.profileId)) { [int]$SegmentCounts[$_.profileId] } else { 0 } } },
            @{ Expression = { -1 * [long]$_.usableTokens } },
            profileId |
        Select-Object -First 1

    return [pscustomobject]@{
        selected = $selected
        states = $states
        reason = if ($PreviousProfileId -and $selected.profileId -ne $PreviousProfileId) { "rotate-to-preserve-usage" } else { "most-efficient-eligible-profile" }
        usageSnapshot = $freshness
    }
}

function Get-GnhfSegmentTokenCap {
    param(
        [Parameter(Mandatory)]$SelectedState,
        [Parameter(Mandatory)][ValidateSet("maximize-sprint-completion", "maximize-token-efficiency")][string]$Mode,
        [Parameter(Mandatory)]$Policy,
        [Parameter(Mandatory)][long]$DefaultSegmentMaxTokens
    )

    $cap = [Math]::Min($DefaultSegmentMaxTokens, [long]$SelectedState.segmentMaxTokens)
    if ($SelectedState.tokensKnown) {
        if ($Mode -eq "maximize-sprint-completion") {
            $cap = [Math]::Min($cap, [long]$SelectedState.tokensRemaining)
        }
        else {
            $sharePercent = Get-GnhfNumericProperty -Object $Policy -Name "maxUsableSharePerSegmentPercent" -Default 25
            $shareCap = [long][Math]::Floor([long]$SelectedState.usableTokens * ($sharePercent / 100.0))
            $shareCap = [Math]::Max([long]$SelectedState.minimumSegmentTokens, $shareCap)
            $cap = [Math]::Min($cap, $shareCap)
            $cap = [Math]::Min($cap, [long]$SelectedState.usableTokens)
        }
    }
    return [long][Math]::Max(1, $cap)
}

function Get-GnhfSegmentOutcome {
    param(
        [Parameter(Mandatory)][int]$ExitCode,
        [Parameter(Mandatory)][AllowEmptyString()][string]$LogText,
        [Parameter(Mandatory)][int]$CommitDelta,
        [switch]$TimedOut
    )

    $normalized = $LogText.ToLowerInvariant()
    if ($TimedOut) {
        return [pscustomobject]@{ status = "timed-out"; switchProfile = $true; objectiveComplete = $false }
    }
    $negativeStopEvidence = $normalized -match '(?:stop[_ -]?when|stop condition|condition)[^\r\n]{0,80}\b(?:not|never|failed to)\b[^\r\n]{0,40}\b(?:reached|met|satisfied)\b'
    $positiveStopEvidence = $normalized -match 'stop[_ -]?when[_ -]?(?:reached|satisfied)|stop condition[^\r\n]{0,80}(?:met|satisfied)|condition[^\r\n]{0,80}satisfied'
    if ($positiveStopEvidence -and -not $negativeStopEvidence) {
        return [pscustomobject]@{ status = "objective-complete"; switchProfile = $false; objectiveComplete = $true }
    }
    if ($normalized -match 'low credit|insufficient credit|quota|usage limit|rate limit|tokens? exhausted|out of tokens|(?:max tokens|token cap)[^\r\n]{0,40}(?:reached|exceeded|exhausted)') {
        return [pscustomobject]@{ status = "quota-exhausted"; switchProfile = $true; objectiveComplete = $false }
    }
    if ($normalized -match 'not authenticated|authentication required|login required|unauthorized|forbidden|invalid api key') {
        return [pscustomobject]@{ status = "authentication-blocked"; switchProfile = $true; objectiveComplete = $false }
    }
    if ($normalized -match "agent '[^']+' is not ready|unknown agent|resolved gnhf agent specification is empty|readiness probe failed") {
        return [pscustomobject]@{ status = "permanent-error"; switchProfile = $true; objectiveComplete = $false }
    }
    if ($normalized -match 'permanent error|unsupported model|model not found|provider unavailable') {
        return [pscustomobject]@{ status = "permanent-error"; switchProfile = $true; objectiveComplete = $false }
    }
    if ($ExitCode -eq 0 -and $CommitDelta -gt 0) {
        return [pscustomobject]@{ status = "progressed"; switchProfile = $false; objectiveComplete = $false }
    }
    if ($ExitCode -eq 0) {
        return [pscustomobject]@{ status = "no-progress"; switchProfile = $false; objectiveComplete = $false }
    }
    return [pscustomobject]@{ status = "failed"; switchProfile = $true; objectiveComplete = $false }
}

Export-ModuleMember -Function @(
    "Get-GnhfSnapshotFreshness",
    "Get-GnhfProfileRoutingState",
    "Select-GnhfRoutingProfile",
    "Get-GnhfSegmentTokenCap",
    "Get-GnhfSegmentOutcome"
)
