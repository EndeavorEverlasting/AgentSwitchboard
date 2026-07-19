# OpenCode Free-Defaults Repair Codebase Map

## Entrypoints

- `Repair-OpenCodeFreeDefaults.cmd`: one-click Windows entrypoint.
- `tooling/wsl/Invoke-OpenCodeFreeDefaultsRepair.ps1`: reusable orchestration.
- `tooling/wsl/Get-OpenCodeFreeDefaultsHarnessStatus.ps1`: read-only inspection.

## Implementation

- `tooling/wsl/Set-OpenCodeFreeDefaults.ps1`: Windows-to-WSL installer and verifier.
- `tooling/wsl/scripts/configure-opencode-free-defaults.sh`: WSL configuration merge.
- `tooling/wsl/tmux-gnhf-workstation.example.json`: reviewed models, paths, and dependency policy.

## Harness

- `tooling/wsl/AGENTS.md`: subtree rules and known traps.
- `.ai/skills/opencode-free-defaults-repair/SKILL.md`: workflow guidance.
- `tooling/wsl/harness/opencode-free-defaults/workflow.json`: workflow routing and proof boundary.
- `tooling/wsl/harness/opencode-free-defaults/artifact-catalog.json`: artifact roles.
- `tooling/wsl/schemas/opencode-free-defaults-run-context.schema.json`: run context.
- `tooling/wsl/schemas/opencode-free-defaults-artifact-registry.schema.json`: artifact registry.
- `tooling/wsl/schemas/opencode-free-defaults-handoff.schema.json`: final handoff.

## Validation

- `tooling/wsl/Test-OpenCodeFreeDefaultsHarness.ps1`
- `tooling/wsl/tests/test_opencode_free_defaults_harness.py`
- `tooling/wsl/tests/test_opencode_free_defaults_transport.py`
- `tooling/wsl/Test-WindowsWorkstationLiveProofContracts.ps1`
- `.github/workflows/windows-workstation-live-proof-contracts.yml`

## Local evidence

Runs write to `%LOCALAPPDATA%\AgentSwitchboard\OpenCodeFreeDefaults\runs\<run-id>\` and remain outside Git.

The workflow may update the managed WSL OpenCode config and create an isolated worktree. It may not clean unrelated work, push, merge, deploy, or claim hosted-model runtime proof.
