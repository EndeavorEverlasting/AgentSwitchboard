# Repository Floor Recovery

## Scope

This document records the bounded recovery decision for `EndeavorEverlasting/AgentSwitchboard`.

The recovery lane owns repository history preservation, branch governance, and proof. It does not own installer redesign, agent adapters, provider configuration, runtime claims, or credential inspection.

## Verified Remote State

As of 2026-07-13, the connected GitHub repository has:

- default branch: `main`
- canonical remote seed: `1c559d6930be3a28321021eea04bcd8f7e323ecb` (`Initial commit`)
- tracked files at that seed: `LICENSE`, `README.md`
- open pull requests before this sprint: none
- recovery branch: `sprint/repository-floor-recovery`

The remote seed remains canonical until the local bootstrap history is inspected and preserved. Remote `main` must not be force-pushed or rewritten.

## Reported Local Seed

Chat evidence reports a separate local repository:

```text
Path: C:\Users\Cheex\Desktop\dev\agents\agent-smoke-test
Branch: main
Commit: 6e91164 Baseline agent bench bootstrap
```

Reported tracked files:

```text
AgentBenchBootstrap.zip
AgentBenchBootstrap/Install-AgentBench.ps1
AgentBenchBootstrap/README-AgentBench.txt
AgentBenchBootstrap/Run-AgentBench-Installer.cmd
```

The local commit is not reachable through the connected GitHub repository, any pull request, or organization commit search. Therefore, the relationship between `6e91164` and the remote seed cannot be proven from GitHub alone.

## Canonical Decision

1. Keep `main@1c559d6930be3a28321021eea04bcd8f7e323ecb` as the canonical remote base.
2. Preserve the local seed as its own remote branch before importing files.
3. Do not merge unrelated roots directly into `main`.
4. Create the eventual implementation branch from `origin/main`.
5. Restore source files from the preserved local branch into that implementation branch and commit them normally.
6. Treat `AgentBenchBootstrap.zip` as generated output unless repository evidence proves it is a required source artifact.

This strategy keeps both original root commits reachable while producing a reviewable, linear implementation diff against remote `main`.

## Read-Only Probe

Run the committed probe in the reported local repository:

```powershell
Set-Location 'C:\Users\Cheex\Desktop\dev\agents\agent-smoke-test'
& .\scripts\Test-RepositoryFloor.ps1 -Fetch
```

The script emits JSON to standard output and does not modify branches, files, or remotes. It records:

- current branch and dirty state
- recent commits
- remotes
- worktrees
- reachability of both known commits
- merge-base result
- the smallest safe next command

If the script is not yet available in the local seed worktree, fetch this recovery branch into a temporary clone or download only the script without changing the local repository history.

## Preservation Sequence

After the probe confirms a clean worktree and the local commit exists:

```powershell
git branch preserve/local-bootstrap-seed 6e91164
git remote -v
git remote add origin https://github.com/EndeavorEverlasting/AgentSwitchboard.git  # only when origin is absent
git fetch --prune origin
git push -u origin preserve/local-bootstrap-seed
```

Then create an isolated integration worktree from the canonical remote base:

```powershell
git worktree add ..\AgentSwitchboard-integration -b integration/import-local-bootstrap origin/main
Set-Location ..\AgentSwitchboard-integration
git restore --source preserve/local-bootstrap-seed -- AgentBenchBootstrap/Install-AgentBench.ps1 AgentBenchBootstrap/README-AgentBench.txt AgentBenchBootstrap/Run-AgentBench-Installer.cmd
git status --short
git diff --check
git add AgentBenchBootstrap/Install-AgentBench.ps1 AgentBenchBootstrap/README-AgentBench.txt AgentBenchBootstrap/Run-AgentBench-Installer.cmd
git commit -m 'feat: import baseline agent bench bootstrap'
git push -u origin integration/import-local-bootstrap
```

Do not import the ZIP in the first pass. Review whether release packaging belongs in GitHub Releases or generated artifacts instead of source control.

## Acceptance Gates

Repository-floor recovery is complete only when all of the following are true:

- `1c559d6930be3a28321021eea04bcd8f7e323ecb` remains reachable.
- `6e91164` is reachable on `preserve/local-bootstrap-seed` or an equivalently explicit preservation ref.
- remote `main` has not been rewritten.
- the integration branch is based on `origin/main`.
- imported source files are reviewable as a normal diff.
- no provider keys or machine-local configuration are committed.
- `git diff --check` passes.
- the integration worktree is clean after commit.

## Current Blocker

The connected GitHub environment cannot read the reported Windows worktree or push the local-only commit. The recovery branch therefore records the decision and enforcement probe, but does not claim that `6e91164` has been preserved remotely or imported.
