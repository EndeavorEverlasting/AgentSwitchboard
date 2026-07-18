function Get-QueueStringSha256 {
    param([Parameter(Mandatory)][string]$Value)

    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '')
    }
    finally {
        $algorithm.Dispose()
    }
}

function Test-QueueRelativePath {
    param([Parameter(Mandatory)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if ([IO.Path]::IsPathRooted($Path)) { return $false }
    if ($Path -match '(^|[\\/])\.\.([\\/]|$)' -or $Path.Contains('*') -or $Path.Contains('?')) { return $false }
    return $true
}

function Test-QueueLiteralContains {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][bool]$CaseSensitive
    )

    $comparison = if ($CaseSensitive) { [StringComparison]::Ordinal } else { [StringComparison]::OrdinalIgnoreCase }
    return $Text.IndexOf($Value, $comparison) -ge 0
}

function Get-QueueTriggerRegistryHash {
    param([Parameter(Mandatory)]$Application)

    return Get-QueueStringSha256 -Value ($Application | ConvertTo-Json -Depth 30 -Compress)
}

function Get-QueueTriggerFlags {
    param(
        [Parameter(Mandatory)][string]$QueueId,
        [Parameter(Mandatory)][string]$LaneId,
        [Parameter(Mandatory)]$Application,
        [Parameter(Mandatory)]$Repository,
        [Parameter(Mandatory)][string]$PromptText,
        [Parameter(Mandatory)][string]$PromptHash
    )

    $enabledTriggers = @($Application.triggers | Where-Object { $_.enabled -eq $true })
    if ($enabledTriggers.Count -eq 0) {
        throw "Application '$($Application.id)' has no enabled triggers."
    }
    $triggerIds = @($enabledTriggers | ForEach-Object { [string]$_.id })
    if ($triggerIds.Count -ne @($triggerIds | Sort-Object -Unique).Count) {
        throw "Application '$($Application.id)' contains duplicate enabled trigger IDs."
    }

    $flags = [Collections.Generic.List[object]]::new()
    foreach ($trigger in $enabledTriggers) {
        $triggerId = [string]$trigger.id
        $kind = [string]$trigger.kind
        $caseSensitive = [bool]$trigger.caseSensitive
        $sourcePath = $null
        $active = $false
        $evidence = $null

        switch ($kind) {
            'always' {
                $active = $true
                $evidence = 'The application registry declares this trigger always active.'
            }
            'repository-path-exists' {
                $relativePath = [string]$trigger.path
                if (-not (Test-QueueRelativePath -Path $relativePath)) {
                    throw "Trigger '$triggerId' requires an exact repository-relative path."
                }
                $sourcePath = $relativePath.Replace('\\', '/')
                $candidate = [IO.Path]::GetFullPath((Join-Path ([string]$Repository.path) $relativePath))
                if (-not (Test-PathWithin -Child $candidate -Parent ([string]$Repository.path))) {
                    throw "Trigger '$triggerId' resolved outside its repository."
                }
                $active = Test-Path -LiteralPath $candidate
                $evidence = if ($active) { "Repository path exists: $sourcePath" } else { "Repository path is absent: $sourcePath" }
            }
            'repository-text-contains' {
                $relativePath = [string]$trigger.path
                $value = [string]$trigger.value
                if (-not (Test-QueueRelativePath -Path $relativePath)) {
                    throw "Trigger '$triggerId' requires an exact repository-relative file."
                }
                if ([string]::IsNullOrWhiteSpace($value)) {
                    throw "Trigger '$triggerId' requires a nonempty literal value."
                }
                $sourcePath = $relativePath.Replace('\\', '/')
                $candidate = [IO.Path]::GetFullPath((Join-Path ([string]$Repository.path) $relativePath))
                if (-not (Test-PathWithin -Child $candidate -Parent ([string]$Repository.path))) {
                    throw "Trigger '$triggerId' resolved outside its repository."
                }
                if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                    $active = $false
                    $evidence = "Repository text source is absent: $sourcePath"
                }
                else {
                    $file = Get-Item -LiteralPath $candidate
                    if ($file.Length -gt 1MB) {
                        throw "Trigger '$triggerId' source exceeds the 1 MiB bounded-read limit: $sourcePath"
                    }
                    $text = Get-Content -LiteralPath $candidate -Raw
                    $active = Test-QueueLiteralContains -Text $text -Value $value -CaseSensitive $caseSensitive
                    $evidence = if ($active) { "Literal text was found in $sourcePath." } else { "Literal text was not found in $sourcePath." }
                }
            }
            'prompt-text-contains' {
                $value = [string]$trigger.value
                if ([string]::IsNullOrWhiteSpace($value)) {
                    throw "Trigger '$triggerId' requires a nonempty literal value."
                }
                $active = Test-QueueLiteralContains -Text $PromptText -Value $value -CaseSensitive $caseSensitive
                $evidence = if ($active) { 'Literal text was found in the source prompt.' } else { 'Literal text was not found in the source prompt.' }
            }
            default {
                throw "Application '$($Application.id)' uses unsupported trigger kind '$kind'."
            }
        }

        [void]$flags.Add([pscustomobject][ordered]@{
            id = $triggerId
            description = [string]$trigger.description
            severity = [string]$trigger.severity
            kind = $kind
            active = [bool]$active
            evidence = $evidence
            sourcePath = $sourcePath
        })
    }

    $activeFlags = @($flags | Where-Object active)
    $criticalFlags = @($activeFlags | Where-Object severity -eq 'critical')
    [pscustomobject][ordered]@{
        schemaVersion = 'agentswitchboard-awareness-trigger-flags/v1'
        queueId = $QueueId
        laneId = $LaneId
        application = [pscustomobject][ordered]@{
            id = [string]$Application.id
            displayName = [string]$Application.displayName
            repositoryName = if ([string]::IsNullOrWhiteSpace([string]$Application.repositoryName)) { $null } else { [string]$Application.repositoryName }
        }
        flaggedAt = (Get-Date).ToString('o')
        flaggingPhase = 'pre-agent-launch'
        repositoryHead = [string]$Repository.head
        promptHash = $PromptHash
        registryHash = Get-QueueTriggerRegistryHash -Application $Application
        registeredTriggerCount = $flags.Count
        activeTriggerCount = $activeFlags.Count
        criticalTriggerCount = $criticalFlags.Count
        flags = @($flags)
        awarenessGate = [pscustomobject][ordered]@{
            required = $true
            satisfied = $true
            instruction = 'Read and reconcile every active trigger before completing analysis or producing an awareness assessment.'
        }
        automaticMutation = $false
    }
}

function Add-QueueTriggerAwarenessToContracts {
    param(
        [Parameter(Mandatory)]$Conversion,
        [Parameter(Mandatory)]$Snapshot,
        [Parameter(Mandatory)][string]$SnapshotPath,
        [Parameter(Mandatory)][string]$SnapshotHash
    )

    $instruction = @"
PRE-AWARENESS TRIGGER FLAGS (generated before agent launch)
- Application: $($Snapshot.application.displayName) [$($Snapshot.application.id)]
- Exact snapshot: $SnapshotPath
- Snapshot SHA256: $SnapshotHash
- Registered triggers: $($Snapshot.registeredTriggerCount)
- Active triggers: $($Snapshot.activeTriggerCount)
- Active critical triggers: $($Snapshot.criticalTriggerCount)
Before completing repository analysis or producing any awareness assessment, read the exact snapshot and explicitly reconcile every active trigger. The snapshot is evidence, not authorization. Do not modify or delete it.
"@

    $Conversion.compiledPrompt.prompt = ($instruction.Trim() + [Environment]::NewLine + [Environment]::NewLine + [string]$Conversion.compiledPrompt.prompt)
    $Conversion.regularRequest.readFirst = @($SnapshotPath) + @($Conversion.regularRequest.readFirst | Where-Object { [string]$_ -cne $SnapshotPath })
    $Conversion.compiledPrompt.readFirst = @($SnapshotPath) + @($Conversion.compiledPrompt.readFirst | Where-Object { [string]$_ -cne $SnapshotPath })
    $safety = 'Pre-awareness trigger flags must remain available and unchanged until the lane finishes.'
    $Conversion.regularRequest.safetyConstraints = @(@($Conversion.regularRequest.safetyConstraints) + @($safety) | Select-Object -Unique)
    return $Conversion
}

function Test-QueueTriggerGate {
    param(
        [Parameter(Mandatory)]$Lane,
        [Parameter(Mandatory)][string]$QueueId
    )

    if (-not ($Lane.PSObject.Properties.Name -contains 'triggerFlags')) {
        throw "Lane '$($Lane.laneId)' has no pre-awareness trigger flags."
    }
    $path = [string]$Lane.triggerFlags.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Lane '$($Lane.laneId)' trigger snapshot is missing: $path"
    }
    $actualHash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($actualHash -cne [string]$Lane.triggerFlags.sha256) {
        throw "Lane '$($Lane.laneId)' trigger snapshot hash mismatch; the pre-awareness evidence was altered."
    }
    $snapshot = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 40
    if ([string]$snapshot.schemaVersion -cne 'agentswitchboard-awareness-trigger-flags/v1' -or
        [string]$snapshot.queueId -cne $QueueId -or
        [string]$snapshot.laneId -cne [string]$Lane.laneId -or
        [string]$snapshot.application.id -cne [string]$Lane.application.id -or
        [string]$snapshot.flaggingPhase -cne 'pre-agent-launch' -or
        $snapshot.awarenessGate.required -ne $true -or
        $snapshot.awarenessGate.satisfied -ne $true) {
        throw "Lane '$($Lane.laneId)' trigger snapshot does not satisfy the pre-awareness gate."
    }
    $flags = @($snapshot.flags)
    if ([int]$snapshot.registeredTriggerCount -ne $flags.Count -or
        [int]$snapshot.activeTriggerCount -ne @($flags | Where-Object active).Count -or
        [int]$snapshot.criticalTriggerCount -ne @($flags | Where-Object { $_.active -eq $true -and $_.severity -eq 'critical' }).Count) {
        throw "Lane '$($Lane.laneId)' trigger snapshot counts are inconsistent."
    }
    $compiled = Get-Content -LiteralPath ([string]$Lane.contracts.compiledPromptPath) -Raw | ConvertFrom-Json -Depth 50
    if (-not ([string]$compiled.prompt).Contains($path) -or
        -not ([string]$compiled.prompt).Contains($actualHash) -or
        -not ([string]$compiled.prompt).Contains('Before completing repository analysis or producing any awareness assessment') -or
        -not (@($compiled.readFirst) -contains $path)) {
        throw "Lane '$($Lane.laneId)' compiled prompt is missing its pre-awareness trigger contract."
    }
    return $snapshot
}
