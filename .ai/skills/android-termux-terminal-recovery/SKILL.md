---
id: android-termux-terminal-recovery
version: 1.0.0
status: experimental
---

# Android Termux terminal recovery

## Trigger

Use when Android text selection spans multiple tmux panes, touch scrolling is unclear or unreliable, clipboard paste/selection is suspect, prior terminal output must be recovered, or the operator would otherwise need a screenshot to preserve evidence.

## Inputs

- current tmux session and pane inventory;
- the output or decision that must be recovered;
- whether any visible pane contains authentication/device-code or credential material;
- maximum history required (default 200 lines);
- the next bounded operator/agent action.

## Procedure

1. Read `AGENTS.md` and `tooling/profiles/android/harness/termux/manifest.json`.
2. Do not treat Android long-press selection as a pane boundary. List exact pane identities with `tmux list-panes -a -F '#S:#I.#P active=#{pane_active} cmd=#{pane_current_command}'`.
3. Classify sensitivity before persistence. Never capture a pane that shows OAuth/device codes, tokens, passwords, private keys, credential files, or other forbidden evidence.
4. Target one safe pane explicitly and capture only bounded history, normally `tmux capture-pane -p -S -200 -t <session:window.pane>`.
5. When durable proof is needed, redirect that capture to a timestamped file under `$HOME/agentswitchboard-evidence`; do not require selecting terminal text.
6. Inspect the file with `tail`, `sed`, `grep`, `less`, or `cat`. Share only the smallest non-sensitive excerpt or artifact path needed for the next decision.
7. For human browsing only, tmux copy mode is the fallback: `Ctrl+B`, then `[`, navigate with Page Up/Page Down or arrows, and press `q` to leave copy mode. Copy mode is not required for evidence when `capture-pane` works.
8. If clipboard transport remains awkward, use the repository's canonical plain-text command through careful manual entry, QR, monitored live document, or file transport as appropriate. Transport does not grant new execution authority.
9. Preserve the exact target, capture range, artifact path, redaction/sensitivity decision, and next command in the operator report.

## Outputs

- bounded tmux pane inventory;
- one safe pane-capture artifact or a documented sensitivity block;
- terminal interaction report;
- exact next command that does not depend on Android native text selection.

## Deterministic validation

- `python tests/test_android_termux_harness.py`
- `bash tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPreCommit.sh`
- `bash tooling/profiles/android/hooks/Invoke-AndroidTermuxHarnessPrePush.sh` before pushing Android harness changes
- `pwsh -NoLogo -NoProfile -File scripts/Test-AndroidTermuxHarnessCompleteness.ps1` where PowerShell is available
- `git diff --check`

## Forbidden scope

- do not persist or share authentication/device codes, tokens, passwords, recovery codes, credential-file contents, or private SSH keys;
- do not use an unbounded pane capture merely because touch scrolling is inconvenient;
- do not capture every pane when only one pane is relevant;
- do not claim that `capture-pane` proves the command represented in the text succeeded;
- do not modify Android runtime/product code from this harness recovery procedure;
- do not install hooks implicitly.

## Stop and escalate

Stop the capture if exact pane identity cannot be established or the only relevant pane contains sensitive material. Generate a fresh sanitized read-only command in a known pane, or name the physical/authentication action required. Never solve a secrecy problem by taking a broader screenshot.
