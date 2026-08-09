---
id: android-herdr-migration
version: 1.1.0
status: experimental
---

# Android Herdr migration

## Trigger

Use when Herdr is being evaluated, installed, repaired, validated, or considered as a replacement for tmux on AgentSwitchboard Android/Termux, including `KEEP_TMUX_HERDR_NOT_INSTALLED`, a BLOCKED source review, an unhealthy Herdr binary, or a request to prove persistence or agent-aware state.

## Inputs

- repository branch/PR identity;
- current phone readiness evidence when available;
- tracked `tooling/profiles/android/harness/herdr/upstream-installation-source.json`;
- current official Herdr source/release/install documentation when refreshing that tracked source;
- first unproved migration gate;
- owned harness scope and forbidden product/runtime scope.

## Procedure

1. Read `AGENTS.md`, harness doctrine, the parent Android Termux manifest, and the Herdr manifest/codebase map.
2. Preserve tmux as the canonical Android multiplexer until the installation review and every live promotion gate are proven.
3. Run `python tooling/profiles/android/harness/herdr/Get-HerdrHarnessStatus.py` to select the first unproved gate.
4. For `KEEP_TMUX_HERDR_NOT_INSTALLED`, read the tracked `upstream-installation-source.json`, then run `python tooling/profiles/android/harness/herdr/Build-HerdrInstallReview.py --write`.
5. Treat the review builder's `DECISION` as authoritative for this harness snapshot. `BLOCKED` means no installation command is authorized; advance to the reported compatibility/upstream-support gate instead of improvising an installer.
6. Refresh the tracked upstream source from current official install docs plus release/tag metadata before any future transition to `APPROVED`. Linux `aarch64` does not establish Android support.
7. Reject undocumented `cargo install herdr`, curl-pipe-shell as migration proof, automatic Android `device_config`/battery mutation, and tmux removal before rollback.
8. When a reviewed binary installation is separately authorized and a binary is present, require version/help identity before a separately authorized live server test. Binary health does not prove persistence.
9. Promote only same-device live gates: server start, detach/reattach, agent-state detection, Android background survival, bounded AgentSwitchboard sprint, then existing Android validator compatibility.
10. Keep generated evidence under the artifact registry state root and out of Git; never persist credentials/device codes/private keys.
11. Before commit/push, run the focused validators and opt-in hooks; repair correctable harness failures in the same branch.
12. Render the operator report and provide one exact next command that advances the first unproved gate rather than repeating completed proof.

## Outputs

- selected Herdr workflow and gate classification;
- tracked source binding for the installation decision;
- source-bound install-review artifact with an explicit `APPROVED`, `REJECTED`, or `BLOCKED` decision;
- focused harness validation receipt;
- JSON/Markdown operator status artifacts;
- exact next action with honest proof ceiling.

## Deterministic validation

- `python tests/test_android_herdr_migration.py`
- `python tests/test_android_herdr_install_review.py`
- `python tests/test_android_herdr_harness_completeness.py`
- `pwsh -NoLogo -NoProfile -File scripts/Test-AndroidHerdrHarnessCompleteness.ps1`
- `bash tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPreCommit.sh`
- `bash tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPrePush.sh` before push
- existing Android Termux portable contracts
- `git diff --check`

## Forbidden scope

- do not modify `AGENTS.md` or governance policy from this harness skill;
- do not modify the canonical Android product launcher/runtime from a harness-only sprint;
- do not install while the source-bound review is `BLOCKED`;
- do not uninstall tmux or promote Herdr before all live gates pass;
- do not invent an install method from package-name guesses or Linux architecture alone;
- do not mutate Android process/battery policy automatically;
- do not persist secrets, device codes, credentials, private hostnames, customer evidence, or raw machine-local junk;
- do not force-push, destructively clean, or write the default branch.

## Stop and escalate

Stop when the source-bound review is `BLOCKED`, no reviewed install method is available, current official sources do not establish the candidate method/platform, a live runtime gate requires authority not granted by the harness lane, validation fails outside owned scope, evidence contains sensitive material, or another writer owns the necessary paths. Preserve tmux fallback and the smallest safe evidence, then name the owner, dependency, artifact and executable action that advances the gate.
