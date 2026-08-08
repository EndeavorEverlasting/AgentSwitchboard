---
id: android-termux-repo-bootstrap
version: 1.0.0
status: experimental
---

# Android Termux repository bootstrap

## Trigger

Use when an operator wants to turn a Termux session into a bounded, durable AgentSwitchboard repository workspace, or when Android command delivery fails before authentication or clone.

## Inputs

- repository owner/name and intended base branch;
- bounded sprint lane, owned scope and forbidden scope;
- current tmux session identity;
- installed command evidence for `git`, `tmux`, `gh`, `ssh`, `curl`, and `jq`;
- the first unproved gate: environment, GitHub authentication, clone, branch isolation, validation, or runtime.

## Procedure

1. Read `AGENTS.md`, `CODEBASE_MAP.md`, `.ai/harness/device-profile-registry.json`, and `tooling/profiles/android/harness/termux/manifest.json`.
2. Keep repository work inside a named tmux session. Prove detach/list/reattach before credentials or mutations if persistence has not already been proved.
3. Keep the Git checkout under Termux `$HOME` rather than Android shared storage unless a repository-specific contract explicitly requires otherwise.
4. Before installing or reinstalling a missing-looking executable, run a short manually typed `command -v <name>` and version probe. If the shell displays literal `[200~`, route to `validate-terminal-boundary.workflow.json` and `handle-input-boundary-failure.workflow.json`.
5. Authenticate GitHub only after the input boundary is clean. Never record OAuth device codes, access tokens, passwords, recovery codes, or private SSH key material.
6. Fetch the live remote base, preserve default-branch state, and create or use one isolated feature branch with one writer. Never force-push or destructively clean unrelated work.
7. Run `python tests/test_android_termux_harness.py` on the phone. Run repository-native broader validators where the required runtime exists or rely on the hosted PR gate without inflating proof.
8. Produce the local evidence named by the Android Termux artifact registry and render an operator report with one exact next command.

## Outputs

- local bootstrap / persistence / command-boundary evidence under `$HOME/agentswitchboard-evidence`;
- verified GitHub auth state when that gate is actually completed;
- clone and branch synchronization proof when that gate is actually completed;
- Android Termux harness validation output;
- operator report and next-command handoff.

## Deterministic validation

- `python tests/test_android_termux_harness.py`
- `bash tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPreCommit.sh` when staged Android harness changes need a local pre-commit gate
- `pwsh -NoLogo -NoProfile -File scripts/Test-AndroidTermuxHarnessCompleteness.ps1` on a PowerShell-capable repo/CI environment
- `pwsh -NoLogo -NoProfile -File scripts/Test-AppHarness.ps1` for the aggregate repository harness
- `git diff --check`

## Forbidden scope

- do not edit `AGENTS.md` or governance policy to make an Android path pass;
- do not claim the reserved Android profile launcher is implemented by virtue of Termux being installed;
- do not install hooks implicitly or mutate global shell configuration without an explicit bounded lane;
- do not expose credentials, OAuth device codes, tokens, passwords, recovery codes, private SSH keys, customer data, or private hostnames;
- do not use force, destructive cleanup, default-branch writes, merge, release, deployment, or live-target mutation without separate authority.

## Stop and escalate

Stop at the exact boundary when command framing remains ambiguous, authentication cannot be proved, the remote base moves incompatibly, branch ownership collides with another writer, required validation cannot run, or proceeding would cross forbidden scope. Preserve evidence and provide the smallest exact command or operator action that advances that gate.
