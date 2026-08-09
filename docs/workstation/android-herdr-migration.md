# Android Herdr migration

## Status

Herdr is an **experimental candidate** for the AgentSwitchboard Android orchestration layer. The canonical Android runtime remains Pi + tmux until the installation review and live Android/Termux proof clear the migration gates.

Upstream currently documents stable Linux and macOS binaries, including Linux `aarch64`, plus preview Windows builds. Upstream installation documentation does **not** currently claim Android/Termux support, so this repository does not treat Linux `aarch64` availability as Android compatibility proof. The current tracked source-bound installation decision is therefore **BLOCKED**.

The repository also does not use `cargo install herdr` as an installation contract unless the pinned upstream source documents that path.

## Source-bound installation gate

The current upstream facts used by the harness are pinned in:

```text
tooling/profiles/android/harness/herdr/upstream-installation-source.json
```

The snapshot records the exact official release/tag/commit, candidate Linux ARM64 asset identity, GitHub-provided digest, documented platforms/install methods, and whether Android/Termux support is explicitly stated.

Generate the review with:

```sh
python tooling/profiles/android/harness/herdr/Build-HerdrInstallReview.py --write
```

For the current snapshot the builder must print:

```text
DECISION=BLOCKED
NEXT_GATE=prove-android-runtime-compatibility-or-obtain-explicit-upstream-support
```

A `BLOCKED` review deliberately contains **no installation command**. Refresh the tracked source from current official upstream evidence before any future attempt to change that decision.

## Why evaluate Herdr

Herdr adds agent-aware pane state, persistent background sessions, tmux-style `Ctrl+B` prefix behavior, detach/reattach, workspaces/tabs/panes, and a CLI/socket control surface. These capabilities match the AgentSwitchboard workload if they remain reliable under Android/Termux constraints.

## Safety rule

Do **not** install Herdr while the tracked review is `BLOCKED`. Do **not** uninstall tmux, rewrite the canonical Android launcher, or mutate Android `device_config` / battery policy as part of a compatibility probe. Background-process survival must be observed on the actual phone rather than assumed or forced by an undocumented workaround.

## Phone readiness command

From the AgentSwitchboard repository in Termux:

```sh
bash Test-AgentSwitchboard-Android-Herdr.sh evidence
```

Expected outcomes:

- `KEEP_TMUX_HERDR_NOT_INSTALLED` — current normal state; tmux remains authoritative and the source-bound installation review owns the next decision.
- `KEEP_TMUX_HERDR_BINARY_NOT_HEALTHY` — a `herdr` executable exists but basic version/help readback failed.
- `HERDR_BINARY_CANDIDATE_ONLY` — binary identity is healthy enough to begin a separately authorized live server test; this is **not** migration approval.

The probe writes only bounded environment/version evidence under:

```text
~/.local/state/agentswitchboard/android-herdr-migration/
```

It does not record credentials, device codes, prompts, or model output.

## Promotion gates

Herdr becomes eligible to replace tmux only after:

1. Termux environment and architecture are observed.
2. A source-bound installation method is reviewed and no longer blocked.
3. Herdr executable identity/version is observed on the same device.
4. Background Herdr server starts successfully.
5. Detach and reattach restore the same session.
6. A supported coding agent is correctly classified as working / blocked / idle or done.
7. The session survives the Android background/app-switch condition relevant to the operator workflow.
8. A bounded AgentSwitchboard sprint completes with durable evidence, commit, push, and PR behavior at least as strong as the current tmux path.
9. Existing Android runtime and harness validators remain green.

Failure at any gate means **keep tmux** and preserve the bounded evidence for the next repair sprint.

## Validation

Repository-side validation:

```sh
bash -n tooling/profiles/android/harness/herdr/Probe-Herdr-Migration.sh
bash Test-AgentSwitchboard-Android-Herdr.sh contract
python tests/test_android_herdr_migration.py
python tests/test_android_herdr_install_review.py
python tests/test_android_herdr_harness_completeness.py
python tests/test_android_termux_harness.py
git diff --check
```

## Proof ceiling

These tracked files prove the migration contract, upstream source binding, deterministic installation decision, safe probe behavior, and CI validation. They do not prove Herdr runs, persists, or reports agent state correctly on Android/Termux.
