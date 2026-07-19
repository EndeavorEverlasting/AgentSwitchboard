---
id: opencode-free-defaults-repair
version: 1.0.0
status: scoped
---

# OpenCode Free-Defaults Repair

## Activation

Use when the managed OpenCode instance used by WezTerm, WSL Ubuntu, or tmux must be installed, repaired, reapplied, inspected, or verified.

Do not activate for a deliberately paid provider-routed sprint. That is a separate AgentSwitchboard route.

## Inputs

- AgentSwitchboard repository path;
- remote name and branch containing the reviewed installer;
- optional validated commit SHA;
- optional isolated worktree path;
- apply or plan-only mode.

## Preconditions

- Windows with PowerShell 7 and WSL Ubuntu;
- Git repository and configured remote;
- the selected remote branch contains the repair workflow;
- no credentials are supplied to the workflow.

## Procedure

1. Read `tooling/wsl/AGENTS.md` and the workflow specification.
2. Run the read-only status probe.
3. Invoke `Repair-OpenCodeFreeDefaults.cmd` or `tooling/wsl/Invoke-OpenCodeFreeDefaultsRepair.ps1`.
4. Let the workflow preserve the source checkout and create an isolated detached worktree.
5. Verify a supplied commit is contained by the selected remote branch.
6. Run the managed installer from the isolated worktree.
7. Independently read back the effective OpenCode configuration.
8. Review the run context, artifact registry, English report, and compressed handoff.
9. Run focused validators before claiming the repository contribution complete.

## Outputs

Each run writes outside Git under:

```text
%LOCALAPPDATA%\AgentSwitchboard\OpenCodeFreeDefaults\runs\<run-id>\
```

Required artifacts:

- `run-context.json`;
- `artifact-registry.json`;
- `effective-opencode-config.json` when apply succeeds;
- `operator-report.md`;
- `final-handoff.json`.

## Guardrails

- No reset, clean, rebase, force-push, branch deletion, or unreviewed worktree removal.
- No provider credential access or mutation.
- No silent paid-model fallback.
- No direct execution of Windows-mounted Bash scripts.
- No completion claim based only on installer exit code.
- No hand-authored replacement for the repository-owned workflow when it is available.
- Local evidence remains untracked.

## Validation

Run in order:

```powershell
pwsh -NoLogo -NoProfile -File .\tooling\wsl\Test-OpenCodeFreeDefaultsHarness.ps1
python .\tooling\wsl\tests\test_opencode_free_defaults_harness.py
python .\tooling\wsl\tests\test_opencode_free_defaults_transport.py
pwsh -NoLogo -NoProfile -File .\tooling\wsl\Test-WindowsWorkstationLiveProofContracts.ps1
git diff --check
```

## Proof ceiling

Static and CI checks prove workflow shape, parsing, artifact contracts, safe Git boundaries, and validator coverage. A local apply run can additionally prove Ubuntu dependency installation and effective configuration. Neither proves OpenCode Zen authentication, free-model availability, or a hosted model response.
