# Android Herdr migration

## Status

Herdr is an **experimental candidate** for the AgentSwitchboard Android orchestration layer. The canonical Android runtime remains Pi + tmux until live Android/Termux proof clears the migration gates.

Upstream currently documents stable Linux and macOS binaries, including Linux `aarch64`, plus a preview Windows build. Upstream installation documentation does **not** currently claim Android/Termux support and this repository therefore does not treat Linux `aarch64` availability as Android compatibility proof.

The repository also does not use `cargo install herdr` as an installation contract unless upstream documents that path.

## Why evaluate Herdr

Herdr adds agent-aware pane state, persistent background sessions, tmux-style `Ctrl+B` prefix behavior, detach/reattach, workspaces/tabs/panes, and a CLI/socket control surface. These capabilities match the AgentSwitchboard workload better than a generic multiplexer if they remain reliable under Android/Termux constraints.

## Safety rule

Do **not** uninstall tmux, rewrite the canonical Android launcher, or mutate Android `device_config` / battery policy as part of the first probe. Background-process survival must be observed on the actual phone rather than assumed or forced by an undocumented workaround.

## First phone command

From the AgentSwitchboard repository in Termux:

```sh
bash Test-AgentSwitchboard-Android-Herdr.sh evidence
```

Expected outcomes:

- `KEEP_TMUX_HERDR_NOT_INSTALLED` — normal first state; tmux remains authoritative.
- `KEEP_TMUX_HERDR_BINARY_NOT_HEALTHY` — a `herdr` executable exists but basic version/help readback failed.
- `HERDR_BINARY_CANDIDATE_ONLY` — binary identity is healthy enough to begin a separate live server test; this is **not** migration approval.

The probe writes only bounded environment/version evidence under:

```text
~/.local/state/agentswitchboard/android-herdr-migration/
```

It does not record credentials, device codes, prompts, or model output.

## Promotion gates

Herdr becomes eligible to replace tmux only after same-device evidence proves, in order:

1. Termux environment and architecture observed.
2. Herdr executable identity/version observed.
3. Background Herdr server starts successfully.
4. Detach and reattach restore the same session.
5. A supported coding agent is correctly classified as working / blocked / idle or done.
6. The session survives the Android background/app-switch condition relevant to the operator workflow.
7. A bounded AgentSwitchboard sprint completes with durable evidence, commit, push, and PR behavior at least as strong as the current tmux path.
8. Existing Android runtime and harness validators remain green.

Failure at any gate means **keep tmux** and preserve the evidence for the next repair sprint.

## Validation

Repository-side validation:

```sh
bash -n tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh
bash Test-AgentSwitchboard-Android-Herdr.sh contract
python tests/test_android_herdr_migration.py
python tests/test_android_termux_harness.py
git diff --check
```

## Proof ceiling

These tracked files prove only the migration contract, safe probe behavior, and CI validation. They do not prove Herdr installs, runs, persists, or reports agent state correctly on a particular Android device.
