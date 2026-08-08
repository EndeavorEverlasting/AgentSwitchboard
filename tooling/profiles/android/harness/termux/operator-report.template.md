# Android Termux Operator Report

- Repository: `<owner/repo>`
- Branch: `<branch>`
- Base SHA: `<sha>`
- tmux session: `<name>`
- Evidence root: `<local-path>`
- Proof level: `<contract|environment|auth|clone|runtime>`

## Working

- `<verified item + evidence>`

## Broken

- `<failed boundary + exact error identity>`

## Missing / unproved

- `<next unproved gate>`

## Validation

- `python tests/test_android_termux_harness.py`: `<PASS|FAIL|SKIPPED + reason>`
- `pwsh -NoLogo -NoProfile -File scripts/Test-AndroidTermuxHarnessCompleteness.ps1`: `<PASS|FAIL|SKIPPED + reason>`
- `git diff --check`: `<PASS|FAIL>`

## Security / redaction

No OAuth device codes, access tokens, passwords, private SSH keys, recovery codes, customer data or private hostnames are included.

## Next command

`<one exact executable command that advances the first unproved gate>`

## Proof ceiling

`<state exactly what this report does not prove>`
