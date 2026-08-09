---
id: android-herdr-migration
version: 1.0.0
status: experimental
---

# Android Herdr migration

## Trigger

Use when Herdr is being evaluated, installed, repaired, validated, or considered as a replacement for tmux on AgentSwitchboard Android/Termux, including `KEEP_TMUX_HERDR_NOT_INSTALLED`, an unhealthy Herdr binary, or a request to prove persistence or agent-aware state.

## Inputs

- repository branch/PR identity;
- current phone readiness evidence when available;
- current official Herdr source/release/install documentation for installation review;
- first unproved migration gate;
- owned harness scope and forbidden product/runtime scope.

## Procedure

1. Read `AGENTS.md`, harness doctrine, the parent Android Termux manifest, and the Herdr manifest/codebase map.
2. Preserve tmux as the canonical Android multiplexer until every promotion gate has same-device evidence.
3. Run `python tooling/profiles/android/harness/herdr/Get-HerdrHarnessStatus.py` to select the first unproved gate.
4. For `KEEP_TMUX_HERDR_NOT_INSTALLED`, run `python tooling/profiles/android/harness/herdr/Build-HerdrInstallReview.py --write`; review current official upstream sources before any install. Linux `aarch64` does not establish Android support.
5. Reject undocumented `cargo install herdr`, curl-pipe-shell as proof, automatic Android `device_config`/battery mutation, and tmux removal before rollback.
6. When a binary is present, require version/help identity before a separately authorized live server test. Binary health does not prove persistence.
7. Promote only same-device gates: server start, detach/reattach, agent-state detection, Android background survival, bounded AgentSwitchboard sprint, then existing Android validator compatibility.
8. Keep generated evidence under the artifact registry state root and out of Git; never persist credentials/device codes/private keys.
9. Before commit/push, run the focused validators and opt-in hooks; repair correctable harness failures in the same branch.
10. Render the operator report and provide one exact next command that advances the first unproved gate rather than repeating completed proof.

## Outputs

- selected Herdr workflow and gate classification;
- source-bound install-review artifact when installation is next;
- focused harness validation receipt;
- JSON/Markdown operator status artifacts;
- exact next action with honest proof ceiling.

## Deterministic validation

- `python tests/test_android_herdr_migration.py`
- `python tests/test_android_herdr_harness_completeness.py`
- `pwsh -NoLogo -NoProfile -File scripts/Test-AndroidHerdrHarnessCompleteness.ps1`
- `bash tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPreCommit.sh`
- `bash tooling/profiles/android/harness/herdr/hooks/Invoke-HerdrHarnessPrePush.sh` before push
- existing Android Termux portable contracts
- `git diff --check`

## Forbidden scope

- do not modify `AGENTS.md` or governance policy from this harness skill;
- do not modify the canonical Android product launcher/runtime from a harness-only sprint;
- do not uninstall tmux or promote Herdr before all live gates pass;
- do not invent an install method from package-name guesses or Linux architecture alone;
- do not mutate Android process/battery policy automatically;
- do not persist secrets, device codes, credentials, private hostnames, customer evidence, or raw machine-local junk;
- do not force-push, destructively clean, or write the default branch.

## Stop and escalate

Stop when no reviewed install method is available, current official sources do not establish the candidate method/platform, a live runtime gate requires authority not granted by the harness lane, validation fails outside owned scope, evidence contains sensitive material, or another writer owns the necessary paths. Preserve tmux fallback and the smallest safe evidence, then name the owner, dependency, artifact and executable action that advances the gate.
