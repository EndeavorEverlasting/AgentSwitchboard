#Requires -Version 7.0

<#
.SYNOPSIS
Neutral event normalizer for P67 OpenCode adapter (ADP-02).

.DESCRIPTION
Maps OpenCode/provider events to Triage capture contract v2 allowed fields only.
Rejects evaluative and forbidden keys per CAPTURE_EVALUATIVE_REJECTED rule.

This module provides functions to:
- Normalize provider events to neutral structural telemetry
- Reject evaluative fields (useful, first_green, after_fixed_point, correct, effectiveness)
- Enforce privacy boundaries (no raw prompts, transcripts, credentials)
- Validate capture contract v2 compliance

.NOTES
ADP-02: Neutral event normalization only.
Forbidden: self-grading, raw transcript persistence, evaluative judgments.
#>

Set-StrictMode -Version Latest

$script:AllowedCaptureFields = @(
    'schema_version',
    'run_status',
    'invalid_reason',
    'provider_identity',
    'task_id',
    'execution_summary',
    'workspace_state',
    'validation_result',
    'neutral_telemetry'
)

$script:ForbiddenEvaluativeFields = @(
    'useful',
    'first_green',
    'after_fixed_point',
    'correct',
    'effectiveness',
    'score',
    'rating',
    'quality',
    'correctness',
    'usefulness'
)

$script:ForbiddenPrivacyFields = @(
    'raw_prompt',
    'raw_response',
    'transcript',
    'clipboard',
    'query',
    'tool_output',
    'model_text',
    'full_conversation',
    'chat_history'
)

$script:ForbiddenCredentialFields = @(
    'api_key',
    'token',
    'secret',
    'password',
    'credential',
    'auth_header',
    'bearer_token'
)

function Test-CaptureFieldAllowed {
    <#
    .SYNOPSIS
    Test if a field name is allowed in capture contract v2.

    .PARAMETER FieldName
    Field name to test.

    .OUTPUTS
    Hashtable with Valid (bool) and Reason (string) keys.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FieldName
    )

    $lowerField = $FieldName.ToLowerInvariant()

    if ($script:ForbiddenEvaluativeFields -contains $lowerField) {
        return @{
            Valid = $false
            Reason = "CAPTURE_EVALUATIVE_REJECTED: Field '$FieldName' is an evaluative judgment"
            Category = 'EVALUATIVE'
        }
    }

    if ($script:ForbiddenPrivacyFields -contains $lowerField) {
        return @{
            Valid = $false
            Reason = "CAPTURE_PRIVACY_REJECTED: Field '$FieldName' violates privacy boundary"
            Category = 'PRIVACY'
        }
    }

    if ($script:ForbiddenCredentialFields -contains $lowerField) {
        return @{
            Valid = $false
            Reason = "CAPTURE_CREDENTIAL_REJECTED: Field '$FieldName' is a credential field"
            Category = 'CREDENTIAL'
        }
    }

    return @{
        Valid = $true
        Reason = $null
        Category = 'ALLOWED'
    }
}

function Test-CaptureObjectValid {
    <#
    .SYNOPSIS
    Recursively test if a capture object contains only allowed fields.

    .PARAMETER CaptureObject
    Hashtable or PSCustomObject to validate.

    .OUTPUTS
    Hashtable with Valid (bool), Reason (string), and ViolatingFields (array) keys.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$CaptureObject
    )

    $violations = [System.Collections.Generic.List[string]]::new()

    function Test-ObjectRecursive {
        param([object]$Obj, [string]$Path = '')

        if ($null -eq $Obj) { return }

        if ($Obj -is [hashtable] -or $Obj -is [System.Collections.Specialized.OrderedDictionary]) {
            foreach ($key in $Obj.Keys) {
                $fullPath = if ($Path) { "$Path.$key" } else { $key }
                $check = Test-CaptureFieldAllowed -FieldName $key

                if (-not $check.Valid) {
                    $violations.Add("$fullPath ($($check.Category)): $($check.Reason)")
                }

                Test-ObjectRecursive -Obj $Obj[$key] -Path $fullPath
            }
        } elseif ($Obj -is [PSCustomObject]) {
            foreach ($prop in $Obj.PSObject.Properties) {
                $fullPath = if ($Path) { "$Path.$($prop.Name)" } else { $prop.Name }
                $check = Test-CaptureFieldAllowed -FieldName $prop.Name

                if (-not $check.Valid) {
                    $violations.Add("$fullPath ($($check.Category)): $($check.Reason)")
                }

                Test-ObjectRecursive -Obj $prop.Value -Path $fullPath
            }
        } elseif ($Obj -is [array]) {
            for ($i = 0; $i -lt $Obj.Count; $i++) {
                Test-ObjectRecursive -Obj $Obj[$i] -Path "$Path[$i]"
            }
        }
    }

    Test-ObjectRecursive -Obj $CaptureObject

    return @{
        Valid = ($violations.Count -eq 0)
        Reason = if ($violations.Count -gt 0) { "Capture contains $($violations.Count) forbidden field(s)" } else { $null }
        ViolatingFields = @($violations)
    }
}

function ConvertTo-NeutralExecutionSummary {
    <#
    .SYNOPSIS
    Convert provider execution data to neutral summary.

    .PARAMETER StartTime
    Execution start time (DateTime).

    .PARAMETER EndTime
    Execution end time (DateTime).

    .PARAMETER ExitCode
    Process exit code.

    .OUTPUTS
    Ordered hashtable with neutral execution summary.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [datetime]$StartTime,

        [Parameter(Mandatory)]
        [datetime]$EndTime,

        [int]$ExitCode = 0
    )

    $elapsed = ($EndTime - $StartTime).TotalSeconds

    return [ordered]@{
        started_utc = $StartTime.ToUniversalTime().ToString('o')
        ended_utc = $EndTime.ToUniversalTime().ToString('o')
        elapsed_seconds = [math]::Round($elapsed, 2)
        exit_code = $ExitCode
    }
}

function ConvertTo-NeutralProviderIdentity {
    <#
    .SYNOPSIS
    Convert provider metadata to neutral identity object.

    .PARAMETER Provider
    Provider name (e.g., "anthropic", "openai").

    .PARAMETER Model
    Model identifier.

    .PARAMETER Agent
    Agent/system identifier.

    .PARAMETER AdapterVersion
    Adapter version string.

    .OUTPUTS
    Ordered hashtable with neutral provider identity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Provider,

        [Parameter(Mandatory)]
        [string]$Model,

        [string]$Agent = 'opencode-v2',

        [string]$AdapterVersion = 'asb-p67-opencode-adp-02/v1'
    )

    return [ordered]@{
        provider = $Provider
        model = $Model
        agent = $Agent
        adapter_version = $AdapterVersion
    }
}

function New-NeutralValidRunCapture {
    <#
    .SYNOPSIS
    Create neutral capture for VALID run (capture contract v2).

    .PARAMETER ProviderIdentity
    Provider identity hashtable.

    .PARAMETER TaskId
    Task identifier.

    .PARAMETER ExecutionSummary
    Execution summary hashtable.

    .PARAMETER WorkspaceState
    Workspace state ('CLEAN', 'MODIFIED').

    .PARAMETER ValidationResult
    Validation result hashtable.

    .OUTPUTS
    Ordered hashtable matching compute-authority-provider-capture/v2 schema.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ProviderIdentity,

        [Parameter(Mandatory)]
        [string]$TaskId,

        [Parameter(Mandatory)]
        [hashtable]$ExecutionSummary,

        [Parameter(Mandatory)]
        [string]$WorkspaceState,

        [Parameter(Mandatory)]
        [hashtable]$ValidationResult
    )

    $capture = [ordered]@{
        schema_version = 'compute-authority-provider-capture/v2'
        run_status = 'VALID'
        provider_identity = $ProviderIdentity
        task_id = $TaskId
        execution_summary = $ExecutionSummary
        workspace_state = $WorkspaceState
        validation_result = $ValidationResult
        neutral_telemetry = [ordered]@{
            provider_actions_count = 0
            subprocess_spawned = $false
        }
    }

    $validation = Test-CaptureObjectValid -CaptureObject $capture

    if (-not $validation.Valid) {
        throw "Generated capture violates contract: $($validation.Reason)`n$($validation.ViolatingFields -join "`n")"
    }

    return $capture
}

function New-NeutralInvalidRunCapture {
    <#
    .SYNOPSIS
    Create neutral capture for INVALID run (capture contract v2).

    .PARAMETER ProviderIdentity
    Provider identity hashtable.

    .PARAMETER TaskId
    Task identifier.

    .PARAMETER ExecutionSummary
    Execution summary hashtable.

    .PARAMETER InvalidCode
    Invalid run code (e.g., 'RUNTIME_UNAVAILABLE', 'EXECUTION_TIMEOUT').

    .PARAMETER InvalidMessage
    Human-readable invalid reason message.

    .OUTPUTS
    Ordered hashtable matching compute-authority-provider-capture/v2 schema.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ProviderIdentity,

        [Parameter(Mandatory)]
        [string]$TaskId,

        [Parameter(Mandatory)]
        [hashtable]$ExecutionSummary,

        [Parameter(Mandatory)]
        [string]$InvalidCode,

        [Parameter(Mandatory)]
        [string]$InvalidMessage
    )

    $capture = [ordered]@{
        schema_version = 'compute-authority-provider-capture/v2'
        run_status = 'INVALID'
        invalid_reason = [ordered]@{
            code = $InvalidCode
            message = $InvalidMessage
        }
        provider_identity = $ProviderIdentity
        task_id = $TaskId
        execution_summary = $ExecutionSummary
    }

    $validation = Test-CaptureObjectValid -CaptureObject $capture

    if (-not $validation.Valid) {
        throw "Generated capture violates contract: $($validation.Reason)`n$($validation.ViolatingFields -join "`n")"
    }

    return $capture
}

Export-ModuleMember -Function @(
    'Test-CaptureFieldAllowed',
    'Test-CaptureObjectValid',
    'ConvertTo-NeutralExecutionSummary',
    'ConvertTo-NeutralProviderIdentity',
    'New-NeutralValidRunCapture',
    'New-NeutralInvalidRunCapture'
)
