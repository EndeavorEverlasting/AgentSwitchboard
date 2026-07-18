function Assert-QueueContract {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Invoke-ChildPwsh {
    param([Parameter(Mandatory)][string[]]$Arguments)
    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source
    $output = @(& $pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1)
    [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Lines = @($output | ForEach-Object { [string]$_ })
        Text = ($output -join [Environment]::NewLine)
    }
}

function Invoke-FixtureGit {
    param(
        [Parameter(Mandatory)][string]$Repository,
        [Parameter(Mandatory)][string[]]$Arguments
    )
    $output = @(& git -C $Repository @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Fixture git $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)"
    }
    ($output -join [Environment]::NewLine).Trim()
}

function New-FixtureRepository {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Remote
    )
    [void](New-Item -ItemType Directory -Path $Path -Force)
    $init = @(& git -C $Path init -b main 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "git init failed: $($init -join [Environment]::NewLine)" }
    [void](Invoke-FixtureGit -Repository $Path -Arguments @("config", "user.name", "AgentSwitchboard Queue Fixture"))
    [void](Invoke-FixtureGit -Repository $Path -Arguments @("config", "user.email", "queue-fixture@example.invalid"))
    "fixture" | Set-Content -LiteralPath (Join-Path $Path "README.md") -Encoding utf8NoBOM
    [void](Invoke-FixtureGit -Repository $Path -Arguments @("add", "README.md"))
    [void](Invoke-FixtureGit -Repository $Path -Arguments @("commit", "-m", "test: initialize queue fixture"))
    [void](Invoke-FixtureGit -Repository $Path -Arguments @("remote", "add", "origin", $Remote))
}

function New-QueueFixture {
    $fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ("AgentSwitchboardQueue-" + [guid]::NewGuid().ToString("N"))
    [void](New-Item -ItemType Directory -Path $fixtureRoot -Force)
    $promptsRoot = Join-Path $fixtureRoot "prompts"
    [void](New-Item -ItemType Directory -Path $promptsRoot -Force)

    $repoA = Join-Path $fixtureRoot "repo-a"
    $repoB = Join-Path $fixtureRoot "repo-b"
    $repoC = Join-Path $fixtureRoot "repo-c"
    New-FixtureRepository -Path $repoA -Remote "https://github.com/FixtureOrg/QueueRepoA"
    New-FixtureRepository -Path $repoB -Remote "https://github.com/FixtureOrg/QueueRepoB"
    New-FixtureRepository -Path $repoC -Remote "https://github.com/FixtureOrg/QueueRepoC"

    $promptA = Join-Path $promptsRoot "lane-a.txt"
    @"
Objective:
Create and commit proof/a.txt with deterministic fixture content.

Owned scope:
- proof/a.txt

Forbidden scope:
- Every path outside proof/a.txt
- Push, merge, deployment, authentication, and credentials

Expected artifacts:
- proof/a.txt

Read first:
- README.md

Validation:
- git diff --check
- git status --short
"@ | Set-Content -LiteralPath $promptA -Encoding utf8NoBOM

    $promptC = Join-Path $promptsRoot "lane-c.txt"
    @"
Sprint:
Create and commit proof/c.txt without touching unrelated files.

Owned scope:
- proof/c.txt

Forbidden scope:
- Every path outside proof/c.txt
- Push, merge, deployment, authentication, and credentials

Required deliverable:
- proof/c.txt

Inspect first:
- README.md

Validation order:
- git diff --check
- git status --short
"@ | Set-Content -LiteralPath $promptC -Encoding utf8NoBOM

    $promptB = Join-Path $promptsRoot "lane-b.txt"
    @'
gnhf `
  --agent "goose" `
  --worktree `
  --max-iterations 2 `
  --max-tokens 20000 `
  --prevent-sleep on `
  --stop-when "The proof/b.txt artifact is committed, validation passes, and the worktree is clean." `
  "Repo: __TARGET_REPO__

Sprint: Create the dependent queue proof.

Owned scope:
- proof/b.txt

Forbidden scope:
- Every path outside proof/b.txt
- Push, merge, deployment, authentication, and credentials

Expected artifacts:
- proof/b.txt

Read first:
- README.md

Validation:
- git diff --check
- git status --short

Process exit alone is failure; success requires artifact and commit proof."
'@ | Set-Content -LiteralPath $promptB -Encoding utf8NoBOM

    $queuePath = Join-Path $fixtureRoot "queue.json"
    $queue = [pscustomobject][ordered]@{
        schemaVersion = "agentswitchboard-gnhf-prompt-queue/v1"
        queueId = "fixture-queue"
        maxParallel = 2
        agents = @(
            [pscustomobject][ordered]@{
                id = "cursor-opencode"
                runtimeFamily = "Cursor"
                gnhfAgent = "opencode"
                provider = $null
                enabled = $true
            },
            [pscustomobject][ordered]@{
                id = "cursor-goose"
                runtimeFamily = "Cursor"
                gnhfAgent = "goose"
                provider = $null
                enabled = $true
            }
        )
        applications = @(
            [pscustomobject][ordered]@{
                id = "fixture-app-a"
                displayName = "Fixture App A"
                repositoryName = "FixtureOrg/QueueRepoA"
                enabled = $true
                triggers = @(
                    [pscustomobject][ordered]@{
                        id = "readme-present"
                        description = "The application repository has its primary readme."
                        severity = "info"
                        kind = "repository-path-exists"
                        path = "README.md"
                        value = $null
                        caseSensitive = $false
                        enabled = $true
                    },
                    [pscustomobject][ordered]@{
                        id = "deterministic-request"
                        description = "The sprint requests deterministic fixture behavior."
                        severity = "warning"
                        kind = "prompt-text-contains"
                        path = $null
                        value = "deterministic fixture"
                        caseSensitive = $false
                        enabled = $true
                    },
                    [pscustomobject][ordered]@{
                        id = "risk-register-present"
                        description = "An explicit risk register exists and requires awareness."
                        severity = "critical"
                        kind = "repository-path-exists"
                        path = "RISK.md"
                        value = $null
                        caseSensitive = $false
                        enabled = $true
                    }
                )
            },
            [pscustomobject][ordered]@{
                id = "fixture-app-b"
                displayName = "Fixture App B"
                repositoryName = "FixtureOrg/QueueRepoB"
                enabled = $true
                triggers = @(
                    [pscustomobject][ordered]@{
                        id = "dependency-awareness"
                        description = "Dependent work must reconcile its upstream lane result."
                        severity = "warning"
                        kind = "always"
                        path = $null
                        value = $null
                        caseSensitive = $false
                        enabled = $true
                    }
                )
            },
            [pscustomobject][ordered]@{
                id = "fixture-app-c"
                displayName = "Fixture App C"
                repositoryName = "FixtureOrg/QueueRepoC"
                enabled = $true
                triggers = @(
                    [pscustomobject][ordered]@{
                        id = "fixture-marker"
                        description = "The repository contains its fixture marker."
                        severity = "info"
                        kind = "repository-text-contains"
                        path = "README.md"
                        value = "fixture"
                        caseSensitive = $true
                        enabled = $true
                    }
                )
            }
        )
        lanes = @(
            [pscustomobject][ordered]@{
                laneId = "lane-a"
                applicationId = "fixture-app-a"
                promptPath = $promptA
                repositoryPath = $repoA
                repositoryName = "FixtureOrg/QueueRepoA"
                repositoryRemote = "https://github.com/FixtureOrg/QueueRepoA"
                baseBranch = "main"
                pullRequestNumber = $null
                dependsOn = @()
                expectedArtifactPaths = @("proof/a.txt")
                executionIntent = "local_execute"
                desiredProofLevel = "committed-repository-work"
                timeoutSeconds = 120
            },
            [pscustomobject][ordered]@{
                laneId = "lane-c"
                applicationId = "fixture-app-c"
                promptPath = $promptC
                repositoryPath = $repoC
                repositoryName = "FixtureOrg/QueueRepoC"
                repositoryRemote = "https://github.com/FixtureOrg/QueueRepoC"
                baseBranch = "main"
                pullRequestNumber = $null
                dependsOn = @()
                expectedArtifactPaths = @("proof/c.txt")
                executionIntent = "local_execute"
                desiredProofLevel = "committed-repository-work"
                timeoutSeconds = 120
            },
            [pscustomobject][ordered]@{
                laneId = "lane-b"
                applicationId = "fixture-app-b"
                promptPath = $promptB
                repositoryPath = $repoB
                repositoryName = "FixtureOrg/QueueRepoB"
                repositoryRemote = "https://github.com/FixtureOrg/QueueRepoB"
                baseBranch = "main"
                pullRequestNumber = $null
                dependsOn = @("lane-a")
                expectedArtifactPaths = @("proof/b.txt")
                executionIntent = "local_execute"
                desiredProofLevel = "committed-repository-work"
                timeoutSeconds = 120
            }
        )
    }
    $queue | ConvertTo-Json -Depth 40 | Set-Content -LiteralPath $queuePath -Encoding utf8NoBOM

    [pscustomobject][ordered]@{
        Root = $fixtureRoot
        QueuePath = $queuePath
        OutputRoot = Join-Path $fixtureRoot "output"
        Repositories = @($repoA, $repoB, $repoC)
        Heads = @(
            (Invoke-FixtureGit -Repository $repoA -Arguments @("rev-parse", "HEAD")),
            (Invoke-FixtureGit -Repository $repoB -Arguments @("rev-parse", "HEAD")),
            (Invoke-FixtureGit -Repository $repoC -Arguments @("rev-parse", "HEAD"))
        )
    }
}

function Assert-RepositoriesUnchanged {
    param([Parameter(Mandatory)]$Fixture)
    for ($index = 0; $index -lt $Fixture.Repositories.Count; $index++) {
        $repo = [string]$Fixture.Repositories[$index]
        $status = Invoke-FixtureGit -Repository $repo -Arguments @("status", "--porcelain=v1")
        Assert-QueueContract ([string]::IsNullOrWhiteSpace($status)) "Fixture repository must remain clean: $repo"
        $head = Invoke-FixtureGit -Repository $repo -Arguments @("rev-parse", "HEAD")
        Assert-QueueContract ($head -ceq [string]$Fixture.Heads[$index]) "Fixture repository HEAD changed: $repo"
    }
}
