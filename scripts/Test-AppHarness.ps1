[CmdletBinding()]
param(
    [string]$RootPath,
    [string]$OutputRoot,
    [ValidateRange(5, 120)]
    [int]$ValidatorTimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GitText {
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $output = & git -C $RepositoryPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    [pscustomobject]@{
        ExitCode = $exitCode
        Text = (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
    }
}

function Test-PathInside {
    param(
        [Parameter(Mandatory)][string]$Candidate,
        [Parameter(Mandatory)][string]$Parent
    )

    $candidateFull = [IO.Path]::GetFullPath($Candidate).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($candidateFull -ieq $parentFull) { return $true }
    return $candidateFull.StartsWith($parentFull + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][int]$TimeoutSeconds
    )

    $result = [ordered]@{
        ExitCode = $null
        TimedOut = $false
        Output = ''
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FilePath
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    foreach ($argument in $ArgumentList) {
        [void]$psi.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $result.TimedOut = $true
            try {
                $process.Kill($true)
                $process.WaitForExit()
            }
            catch {}
        }
        else {
            $result.ExitCode = $process.ExitCode
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $result.Output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
    finally {
        $process.Dispose()
    }

    return [pscustomobject]$result
}

function Get-Excerpt {
    param([AllowEmptyString()][string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '<no output>' }
    $normalized = $Text.Trim()
    if ($normalized.Length -le 1200) { return $normalized }
    return $normalized.Substring($normalized.Length - 1200)
}

function Test-GraphReachability {
    param(
        [Parameter(Mandatory)][string]$Start,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][object[]]$Edges
    )

    $visited = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $queue = [System.Collections.Generic.Queue[string]]::new()
    [void]$visited.Add($Start)
    $queue.Enqueue($Start)
    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if ($current -eq $Target) { return $true }
        foreach ($edge in @($Edges | Where-Object { [string]$_.from -eq $current })) {
            $next = [string]$edge.to
            if ($visited.Add($next)) { $queue.Enqueue($next) }
        }
    }
    return $false
}

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $candidateRoot = Split-Path -Parent $PSScriptRoot
    $rootProbe = Invoke-GitText -RepositoryPath $candidateRoot -Arguments @('rev-parse', '--show-toplevel')
    if ($rootProbe.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($rootProbe.Text)) {
        throw "Unable to detect repository root from $candidateRoot."
    }
    $RootPath = $rootProbe.Text
}
$RootPath = (Resolve-Path -LiteralPath $RootPath).Path

$identityProbe = Invoke-GitText -RepositoryPath $RootPath -Arguments @('rev-parse', '--show-toplevel')
if ($identityProbe.ExitCode -ne 0 -or [IO.Path]::GetFullPath($identityProbe.Text) -ne [IO.Path]::GetFullPath($RootPath)) {
    throw "RootPath is not the detected Git repository root: $RootPath"
}

$branchProbe = Invoke-GitText -RepositoryPath $RootPath -Arguments @('branch', '--show-current')
$commitProbe = Invoke-GitText -RepositoryPath $RootPath -Arguments @('rev-parse', 'HEAD')
$branch = if ($branchProbe.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($branchProbe.Text)) { $branchProbe.Text } else { '(detached)' }
$commit = if ($commitProbe.ExitCode -eq 0) { $commitProbe.Text } else { 'unknown' }
$repositoryName = Split-Path -Leaf $RootPath

$runStamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$nonce = ([Guid]::NewGuid().ToString('N')).Substring(0, 8)
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path ([IO.Path]::GetTempPath()) "AgentSwitchboard/app-harness/${runStamp}-${nonce}"
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
if (Test-PathInside -Candidate $OutputRoot -Parent $RootPath) {
    throw "OutputRoot must remain outside the repository: $OutputRoot"
}
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$checks = [System.Collections.Generic.List[object]]::new()
function Add-Check {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('PASS', 'SKIP', 'FAIL')][string]$Status,
        [string]$Reason = '',
        [string[]]$Details = @()
    )
    [void]$checks.Add([pscustomobject][ordered]@{
        id = $Id
        name = $Name
        status = $Status
        reason = $Reason
        details = @($Details)
    })
}

$manifestPath = Join-Path $RootPath '.ai/harness/manifest.json'
$artifactRegistryPath = Join-Path $RootPath '.ai/harness/artifact-registry.json'
$graphPath = Join-Path $RootPath '.ai/harness/app-composition.graph.json'
$reportTemplatePath = Join-Path $RootPath '.ai/harness/app-harness-report.template.md'

$bootstrapRequiredFiles = @(
    'AGENTS.md',
    'CODEBASE_MAP.md',
    'TRIGGERS.md',
    '.ai/skills/evidence-validation/SKILL.md',
    '.ai/harness/manifest.json',
    '.ai/harness/artifact-registry.json',
    '.ai/harness/workflows/repository-family-intake.workflow.json',
    '.ai/harness/schemas/run-context.schema.json',
    '.ai/harness/app-composition.graph.json',
    '.ai/harness/schemas/app-composition-graph.schema.json',
    '.ai/harness/schemas/app-harness-validation.schema.json',
    '.ai/harness/app-harness-report.template.md',
    'scripts/Test-AppHarness.ps1',
    'scripts/Test-HarnessDoctrineContract.ps1',
    'scripts/Test-AgentDocumentationContract.ps1',
    'scripts/Test-RepositoryFamilyHarness.ps1',
    'scripts/Test-PublicPlanContracts.ps1',
    'Test-AppHarness.cmd'
)
$missingRequiredFiles = @($bootstrapRequiredFiles | Where-Object { -not (Test-Path -LiteralPath (Join-Path $RootPath $_) -PathType Leaf) })
if ($missingRequiredFiles.Count -eq 0) {
    Add-Check -Id 'required-files' -Name 'required files' -Status PASS -Details $bootstrapRequiredFiles
}
else {
    Add-Check -Id 'required-files' -Name 'required files' -Status FAIL -Reason 'required_harness_files_missing' -Details $missingRequiredFiles
}

$runContext = [ordered]@{
    networkAllowed = $false
    runtimeAllowed = $false
    mutationAllowed = $false
    outputRootInsideRepository = $false
}
$runContextPassed = $commit -match '^[a-f0-9]{40}$' -and -not [string]::IsNullOrWhiteSpace($branch)
if ($runContextPassed) {
    Add-Check -Id 'run-context' -Name 'run context' -Status PASS -Details @("branch=$branch", "commit=$commit", 'networkAllowed=false', 'runtimeAllowed=false', 'mutationAllowed=false')
}
else {
    Add-Check -Id 'run-context' -Name 'run context' -Status FAIL -Reason 'git_identity_unavailable' -Details @("branch=$branch", "commit=$commit")
}

$manifest = $null
$artifactRegistry = $null
try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json }
catch { Add-Check -Id 'manifest-parse' -Name 'harness manifest' -Status FAIL -Reason 'manifest_invalid' -Details @($_.Exception.Message) }
try { $artifactRegistry = Get-Content -LiteralPath $artifactRegistryPath -Raw | ConvertFrom-Json }
catch { Add-Check -Id 'artifact-registry' -Name 'artifact registry' -Status FAIL -Reason 'artifact_registry_invalid' -Details @($_.Exception.Message) }

if ($null -ne $artifactRegistry) {
    $artifactIds = @($artifactRegistry.artifacts | ForEach-Object { [string]$_.artifactId })
    $requiredArtifactIds = @('app-harness-validation-json', 'app-harness-validation-report')
    $missingArtifactIds = @($requiredArtifactIds | Where-Object { $artifactIds -notcontains $_ })
    $unsafeArtifacts = @($artifactRegistry.artifacts | Where-Object { $_.artifactId -in $requiredArtifactIds -and [bool]$_.tracked })
    if ($missingArtifactIds.Count -eq 0 -and $unsafeArtifacts.Count -eq 0) {
        Add-Check -Id 'artifact-registry' -Name 'artifact registry' -Status PASS -Details $requiredArtifactIds
    }
    else {
        Add-Check -Id 'artifact-registry' -Name 'artifact registry' -Status FAIL -Reason 'artifact_contract_broken' -Details @($missingArtifactIds + @($unsafeArtifacts | ForEach-Object { "tracked:$($_.artifactId)" }))
    }
}

if (Test-Path -LiteralPath $reportTemplatePath -PathType Leaf) {
    $reportTemplate = Get-Content -LiteralPath $reportTemplatePath -Raw
    $requiredPlaceholders = @('{{repository}}', '{{branch}}', '{{commit}}', '{{matrix}}', '{{summary}}', '{{jsonPath}}', '{{reportPath}}', '{{proofCeiling}}')
    $missingPlaceholders = @($requiredPlaceholders | Where-Object { -not $reportTemplate.Contains($_) })
    if ($missingPlaceholders.Count -eq 0) {
        Add-Check -Id 'report-renderer' -Name 'report renderer' -Status PASS -Details $requiredPlaceholders
    }
    else {
        Add-Check -Id 'report-renderer' -Name 'report renderer' -Status FAIL -Reason 'renderer_placeholders_missing' -Details $missingPlaceholders
    }
}
else {
    Add-Check -Id 'report-renderer' -Name 'report renderer' -Status FAIL -Reason 'renderer_missing'
    $reportTemplate = ''
}

$graph = $null
try { $graph = Get-Content -LiteralPath $graphPath -Raw | ConvertFrom-Json }
catch { Add-Check -Id 'event-topology' -Name 'event topology' -Status FAIL -Reason 'composition_graph_invalid' -Details @($_.Exception.Message) }

if ($null -ne $graph) {
    $topologyFailures = [System.Collections.Generic.List[string]]::new()
    $nodes = @($graph.nodes)
    $edges = @($graph.edges)
    $nodeIds = @($nodes | ForEach-Object { [string]$_.id })
    $edgeIds = @($edges | ForEach-Object { [string]$_.id })
    if (@($nodeIds | Select-Object -Unique).Count -ne $nodeIds.Count) { [void]$topologyFailures.Add('duplicate node IDs') }
    if (@($edgeIds | Select-Object -Unique).Count -ne $edgeIds.Count) { [void]$topologyFailures.Add('duplicate edge IDs') }
    if ($nodeIds -notcontains [string]$graph.observerNodeId) { [void]$topologyFailures.Add('observer node is not registered') }

    foreach ($edge in $edges) {
        if ($nodeIds -notcontains [string]$edge.from) { [void]$topologyFailures.Add("dangling edge source: $($edge.id) -> $($edge.from)") }
        if ($nodeIds -notcontains [string]$edge.to) { [void]$topologyFailures.Add("dangling edge target: $($edge.id) -> $($edge.to)") }
    }

    foreach ($node in $nodes) {
        if ([bool]$node.required) {
            foreach ($relativePath in @($node.paths)) {
                if (-not (Test-Path -LiteralPath (Join-Path $RootPath $relativePath) -PathType Leaf)) {
                    [void]$topologyFailures.Add("missing required node path: $($node.id) -> $relativePath")
                }
            }
            $incidentRequiredEdges = @($edges | Where-Object { [bool]$_.required -and ([string]$_.from -eq [string]$node.id -or [string]$_.to -eq [string]$node.id) })
            if ($incidentRequiredEdges.Count -eq 0) { [void]$topologyFailures.Add("required node has no required edge: $($node.id)") }
            if ([string]$node.kind -eq 'validator' -and -not [bool]$node.safeOffline) { [void]$topologyFailures.Add("required validator is not marked safeOffline: $($node.id)") }
            if ([string]$node.topologyRole -in @('observed', 'output')) {
                if (-not (Test-GraphReachability -Start ([string]$graph.observerNodeId) -Target ([string]$node.id) -Edges $edges)) {
                    [void]$topologyFailures.Add("required node is disconnected from observer: $($node.id)")
                }
            }
            elseif ([string]$node.topologyRole -eq 'ingress') {
                if (-not (Test-GraphReachability -Start ([string]$node.id) -Target ([string]$graph.observerNodeId) -Edges $edges)) {
                    [void]$topologyFailures.Add("required ingress cannot reach observer: $($node.id)")
                }
            }
        }
    }

    if ($topologyFailures.Count -eq 0) {
        Add-Check -Id 'event-topology' -Name 'event topology' -Status PASS -Details @("nodes=$($nodes.Count)", "edges=$($edges.Count)", "observer=$($graph.observerNodeId)")
    }
    else {
        Add-Check -Id 'event-topology' -Name 'event topology' -Status FAIL -Reason 'composition_graph_broken' -Details @($topologyFailures)
    }

    $optionalNode = @($nodes | Where-Object { $_.id -eq 'optional.mcp-lsp' }) | Select-Object -First 1
    $readinessPath = if ($null -ne $optionalNode -and @($optionalNode.paths).Count -gt 0) { Join-Path $RootPath ([string]@($optionalNode.paths)[0]) } else { $null }
    if ([string]::IsNullOrWhiteSpace([string]$readinessPath) -or -not (Test-Path -LiteralPath $readinessPath -PathType Leaf)) {
        Add-Check -Id 'optional-mcp-symbol-smoke' -Name 'optional MCP symbol smoke' -Status SKIP -Reason 'lsp_project_not_loaded'
    }
    else {
        try {
            $readiness = Get-Content -LiteralPath $readinessPath -Raw | ConvertFrom-Json
            if (-not [bool]$readiness.projectLoaded) {
                Add-Check -Id 'optional-mcp-symbol-smoke' -Name 'optional MCP symbol smoke' -Status SKIP -Reason 'lsp_project_not_loaded'
            }
            elseif ([string]::IsNullOrWhiteSpace([string]$readiness.offlineSymbolIndex) -or -not (Test-Path -LiteralPath (Join-Path $RootPath ([string]$readiness.offlineSymbolIndex)) -PathType Leaf)) {
                Add-Check -Id 'optional-mcp-symbol-smoke' -Name 'optional MCP symbol smoke' -Status SKIP -Reason 'offline_symbol_index_missing'
            }
            else {
                Add-Check -Id 'optional-mcp-symbol-smoke' -Name 'optional MCP symbol smoke' -Status PASS -Details @([string]$readiness.offlineSymbolIndex)
            }
        }
        catch {
            Add-Check -Id 'optional-mcp-symbol-smoke' -Name 'optional MCP symbol smoke' -Status FAIL -Reason 'mcp_lsp_readiness_invalid' -Details @($_.Exception.Message)
        }
    }
}
else {
    Add-Check -Id 'optional-mcp-symbol-smoke' -Name 'optional MCP symbol smoke' -Status SKIP -Reason 'lsp_project_not_loaded'
}

$hygieneFailures = [System.Collections.Generic.List[string]]::new()
if ($null -eq $manifest) {
    [void]$hygieneFailures.Add('manifest unavailable')
}
else {
    if ([bool]$manifest.generatedEvidence.tracked) { [void]$hygieneFailures.Add('generated evidence is marked tracked') }
    if ([bool]$manifest.localHooks.enabled) { [void]$hygieneFailures.Add('implicit local hooks are enabled') }
}
if (Test-PathInside -Candidate $OutputRoot -Parent $RootPath) { [void]$hygieneFailures.Add('output root is inside repository') }
$hooksProbe = Invoke-GitText -RepositoryPath $RootPath -Arguments @('config', '--get', 'core.hooksPath')
$hookDetail = if ($hooksProbe.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($hooksProbe.Text)) { "custom hooksPath observed but not executed: $($hooksProbe.Text)" } else { 'no custom hooksPath configured' }
if ($hygieneFailures.Count -eq 0) {
    Add-Check -Id 'hook-hygiene' -Name 'hook hygiene' -Status PASS -Details @($hookDetail, "outputRoot=$OutputRoot", 'generated evidence remains untracked')
}
else {
    Add-Check -Id 'hook-hygiene' -Name 'hook hygiene' -Status FAIL -Reason 'hook_or_artifact_hygiene_broken' -Details @($hygieneFailures)
}

if ($null -ne $graph) {
    $validatorFailures = [System.Collections.Generic.List[string]]::new()
    $validatorDetails = [System.Collections.Generic.List[string]]::new()
    $pwshPath = (Get-Process -Id $PID).Path
    $validatorNodes = @($graph.nodes | Where-Object { $_.kind -eq 'validator' -and [bool]$_.required -and [bool]$_.safeOffline })
    foreach ($validatorNode in $validatorNodes) {
        foreach ($relativePath in @($validatorNode.paths)) {
            $validatorPath = Join-Path $RootPath $relativePath
            if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) {
                [void]$validatorFailures.Add("missing validator: $relativePath")
                continue
            }
            $processResult = Invoke-BoundedProcess -FilePath $pwshPath -ArgumentList @('-NoLogo', '-NoProfile', '-File', $validatorPath, '-RootPath', $RootPath) -WorkingDirectory $RootPath -TimeoutSeconds $ValidatorTimeoutSeconds
            if ($processResult.TimedOut) {
                [void]$validatorFailures.Add("timeout after ${ValidatorTimeoutSeconds}s: $relativePath")
            }
            elseif ($processResult.ExitCode -ne 0) {
                [void]$validatorFailures.Add("exit $($processResult.ExitCode): $relativePath :: $(Get-Excerpt -Text $processResult.Output)")
            }
            else {
                [void]$validatorDetails.Add("PASS $relativePath")
            }
        }
    }
    if ($validatorFailures.Count -eq 0) {
        Add-Check -Id 'offline-validators' -Name 'offline validators' -Status PASS -Details @($validatorDetails)
    }
    else {
        Add-Check -Id 'offline-validators' -Name 'offline validators' -Status FAIL -Reason 'required_validator_broken' -Details @($validatorFailures)
    }
}
else {
    Add-Check -Id 'offline-validators' -Name 'offline validators' -Status FAIL -Reason 'validator_graph_unavailable'
}

$passed = @($checks | Where-Object status -eq 'PASS').Count
$skipped = @($checks | Where-Object status -eq 'SKIP').Count
$failed = @($checks | Where-Object status -eq 'FAIL').Count
$jsonPath = Join-Path $OutputRoot 'app-harness-validation.json'
$reportPath = Join-Path $OutputRoot 'app-harness-validation.md'
$proofCeiling = 'Offline repository structure, registered event topology, safe validator execution, generated-artifact policy, and optional readiness detection only. No application, game, browser, launcher, provider, network, account, save, target, deployment, hosted response, or live event-delivery proof is claimed.'

$resultDocument = [ordered]@{
    schema = 'agentswitchboard.app-harness-validation.v1'
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    repository = [ordered]@{
        name = $repositoryName
        branch = $branch
        commit = $commit
    }
    runContext = $runContext
    checks = @($checks)
    summary = [ordered]@{
        passed = $passed
        skipped = $skipped
        failed = $failed
    }
    artifacts = @(
        [ordered]@{ artifactId = 'app-harness-validation-json'; path = $jsonPath; tracked = $false },
        [ordered]@{ artifactId = 'app-harness-validation-report'; path = $reportPath; tracked = $false }
    )
    proofLevel = 'offline-synthetic-harness'
    proofCeiling = $proofCeiling
}
$resultDocument | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $jsonPath -Encoding utf8NoBOM

$matrixLines = @($checks | ForEach-Object {
    $suffix = if ([string]::IsNullOrWhiteSpace([string]$_.reason)) { '' } else { ": $($_.reason)" }
    "[$($_.status)] $($_.name)$suffix"
})
$summaryLine = "Result: $passed passed / $skipped skipped / $failed failed"
if (-not [string]::IsNullOrWhiteSpace($reportTemplate)) {
    $renderedReport = $reportTemplate
    $renderedReport = $renderedReport.Replace('{{repository}}', $repositoryName)
    $renderedReport = $renderedReport.Replace('{{branch}}', $branch)
    $renderedReport = $renderedReport.Replace('{{commit}}', $commit)
    $renderedReport = $renderedReport.Replace('{{generatedUtc}}', [string]$resultDocument.generatedUtc)
    $renderedReport = $renderedReport.Replace('{{matrix}}', ($matrixLines -join "`n"))
    $renderedReport = $renderedReport.Replace('{{summary}}', $summaryLine)
    $renderedReport = $renderedReport.Replace('{{jsonPath}}', $jsonPath)
    $renderedReport = $renderedReport.Replace('{{reportPath}}', $reportPath)
    $renderedReport = $renderedReport.Replace('{{proofCeiling}}', $proofCeiling)
    Set-Content -LiteralPath $reportPath -Value $renderedReport -Encoding utf8NoBOM
}
else {
    @('# APP HARNESS VALIDATION', '', $matrixLines, '', $summaryLine, '', $proofCeiling) | Set-Content -LiteralPath $reportPath -Encoding utf8NoBOM
}

Write-Host 'APP HARNESS VALIDATION' -ForegroundColor Cyan
Write-Host "Repository: $repositoryName"
Write-Host "Branch:     $branch"
Write-Host "Commit:     $commit"
foreach ($check in $checks) {
    $color = switch ($check.status) { 'PASS' { 'Green' } 'SKIP' { 'Yellow' } default { 'Red' } }
    $suffix = if ([string]::IsNullOrWhiteSpace([string]$check.reason)) { '' } else { ": $($check.reason)" }
    Write-Host "[$($check.status)] $($check.name)$suffix" -ForegroundColor $color
}
Write-Host $summaryLine
Write-Host "JSON:   $jsonPath" -ForegroundColor Cyan
Write-Host "Report: $reportPath" -ForegroundColor Cyan
Write-Host 'Proof ceiling: offline synthetic harness only; no runtime proof.' -ForegroundColor Yellow

if ($failed -gt 0) { exit 1 }
exit 0
