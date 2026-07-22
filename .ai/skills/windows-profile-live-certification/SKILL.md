---
id: windows-profile-live-certification
version: 1.0.0
status: canonical
---

# Windows Profile Live Certification

## Trigger

`profile.workstation-certification-request` or explicit live-certification invocation.

## Inputs

- Exact AgentSwitchboard commit SHA
- Exact installed launcher path and manifest hash
- Requested mode: open-or-activate or new-instance
- Exact operator command
- WSL distribution name
- Expected tmux identity
- Evidence root path
- Timeout seconds

## Procedure

1. Freeze the run context: repo, commit, launcher path, manifest hash, mode, operator command, distribution, tmux identity, evidence root, timeout, rollback boundary, proof ceiling.
2. Capture before snapshot: desktop shortcut target and arguments, WezTerm frontend processes and top-level windows, tmux sessions, tmux clients, installed launcher and manifest hashes.
3. Execute the exact operator command in the requested mode.
4. Capture after snapshot: same fields as before.
5. Compare before and after: new windows, new tmux sessions, new tmux clients.
6. Classify result: opened, activated, new-instance-opened, duplicate-detected, blocked, or failed.
7. Emit stage ledger, mode result, duplicate report, English operator report, and final handoff.
8. When Live mode: require user-visible observation fields. Process handles and tmux session existence alone are insufficient.

## Outputs

- Run context (untracked)
- Before and after snapshots (untracked)
- Stage ledger (untracked)
- Mode result (untracked)
- Duplicate report (untracked)
- English operator report (untracked)
- Final handoff (untracked)

## Deterministic validation

- Run context schema validates
- All required stages completed
- Proof ceiling declared
- No tracked runtime evidence
- No private hostnames, usernames, or unredacted command lines in fixtures

## Forbidden scope

- Runtime execution in CI
- Storing private hostnames, usernames, or unredacted command lines in committed fixtures
- Claiming live proof from static tests or command acknowledgement
- Installing hooks implicitly
- Mutating launcher product code
- Process handles as visible-window proof
- tmux session existence as client-attachment proof

## Stop and escalate

- Launcher path or hash differs from the pinned contract
- WezTerm, WSL, or tmux prerequisites are missing
- The operator command was not acknowledged
- Duplicate detection finds more than one new window per request
- Rollback fails
