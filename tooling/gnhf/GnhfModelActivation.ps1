Set-StrictMode -Version Latest

function Get-GnhfModelActivationResult {
    [CmdletBinding()]
    param(
        [string]$AcknowledgementPath,
        [string]$ExpectedProfileId,
        [string]$ExpectedAgent,
        [string]$ExpectedModel,
        [string]$ExpectedRoutingDecisionHash
    )

    $result = [ordered]@{
        state = if ([string]::IsNullOrWhiteSpace($ExpectedModel)) { "not-requested" } else { "requested-only" }
        requestedModel = if ([string]::IsNullOrWhiteSpace($ExpectedModel)) { $null } else { $ExpectedModel }
        acknowledgedModel = $null
        acknowledgementPath = if ([string]::IsNullOrWhiteSpace($AcknowledgementPath)) { $null } else { $AcknowledgementPath }
        evidenceKind = $null
        evidence = $null
        recordedAt = $null
        validationError = $null
    }

    if ([string]::IsNullOrWhiteSpace($ExpectedModel) -or [string]::IsNullOrWhiteSpace($AcknowledgementPath)) {
        return [pscustomobject]$result
    }
    if (-not (Test-Path -LiteralPath $AcknowledgementPath -PathType Leaf)) {
        return [pscustomobject]$result
    }

    try {
        $record = Get-Content -LiteralPath $AcknowledgementPath -Raw | ConvertFrom-Json -Depth 20
        if ([string]$record.schemaVersion -ne "agentswitchboard-model-activation/v1") {
            throw "unsupported schemaVersion '$($record.schemaVersion)'"
        }
        if ([string]$record.profileId -ne $ExpectedProfileId) {
            throw "profileId mismatch"
        }
        if ([string]$record.agent -ne $ExpectedAgent) {
            throw "agent mismatch"
        }
        if ([string]$record.requestedModel -ne $ExpectedModel) {
            throw "requestedModel mismatch"
        }

        $recordHash = if ($record.PSObject.Properties["routingDecisionHash"] -and $null -ne $record.routingDecisionHash) { [string]$record.routingDecisionHash } else { $null }
        $expectedHash = if ([string]::IsNullOrWhiteSpace($ExpectedRoutingDecisionHash)) { $null } else { $ExpectedRoutingDecisionHash }
        if ($recordHash -ne $expectedHash) {
            throw "routingDecisionHash mismatch"
        }

        $allowedStates = @("acknowledged", "observed-response", "rejected")
        $activationState = [string]$record.activationState
        if ($activationState -notin $allowedStates) {
            throw "unsupported activationState '$activationState'"
        }

        $acknowledgedModel = if ($record.PSObject.Properties["acknowledgedModel"] -and $null -ne $record.acknowledgedModel) { [string]$record.acknowledgedModel } else { $null }
        if ($activationState -in @("acknowledged", "observed-response")) {
            if ([string]::IsNullOrWhiteSpace($acknowledgedModel)) {
                throw "acknowledgedModel is required for '$activationState'"
            }
            if ($acknowledgedModel -ne $ExpectedModel) {
                throw "acknowledgedModel mismatch"
            }
        }

        $result.state = $activationState
        $result.acknowledgedModel = $acknowledgedModel
        $result.evidenceKind = [string]$record.evidenceKind
        $result.evidence = [string]$record.evidence
        $result.recordedAt = [string]$record.recordedAt
        return [pscustomobject]$result
    }
    catch {
        $result.state = "invalid-acknowledgement"
        $result.validationError = $_.Exception.Message
        return [pscustomobject]$result
    }
}
