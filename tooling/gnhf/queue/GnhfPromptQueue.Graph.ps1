function Get-DependencyWaves {
    param([Parameter(Mandatory)][object[]]$Lanes)

    $byId = @{}
    foreach ($lane in $Lanes) {
        $laneId = [string]$lane.laneId
        if ($byId.ContainsKey($laneId)) { throw "Duplicate laneId '$laneId'." }
        $byId[$laneId] = $lane
    }
    foreach ($lane in $Lanes) {
        foreach ($dependency in @($lane.dependsOn)) {
            $dependencyId = [string]$dependency
            if (-not $byId.ContainsKey($dependencyId)) {
                throw "Lane '$($lane.laneId)' depends on unknown lane '$dependencyId'."
            }
            if ($dependencyId -ceq [string]$lane.laneId) {
                throw "Lane '$($lane.laneId)' cannot depend on itself."
            }
        }
    }

    $remaining = [Collections.Generic.List[string]]::new()
    foreach ($laneId in @($byId.Keys | Sort-Object)) { [void]$remaining.Add([string]$laneId) }
    $completed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $waves = [Collections.Generic.List[object]]::new()
    $waveIndex = 0

    while ($remaining.Count -gt 0) {
        $ready = @(
            $remaining |
                Where-Object {
                    $candidate = $byId[[string]$_]
                    @($candidate.dependsOn | Where-Object { -not $completed.Contains([string]$_) }).Count -eq 0
                } |
                Sort-Object
        )
        if ($ready.Count -eq 0) {
            throw "The prompt queue dependency graph contains a cycle or cannot make progress."
        }
        [void]$waves.Add([pscustomobject]@{
            wave = $waveIndex
            laneIds = @($ready)
        })
        foreach ($laneId in $ready) {
            [void]$remaining.Remove([string]$laneId)
            [void]$completed.Add([string]$laneId)
        }
        $waveIndex++
    }
    @($waves)
}
