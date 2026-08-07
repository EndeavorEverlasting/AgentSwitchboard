# Tmux live-proof field acceptance — 2026-08-07

## Status

**Accepted on the affected Windows workstation.** The exact launcher merged to `main` at `392f2f352219d3211ed1aa74eb4a90a51dfbc4b8` completed the repository-owned tmux live-proof path and emitted `status=success`, `proofLevel=tmux-client-attached`, and `tmuxClientAttachedObserved=true`.

This document is a minimized public milestone. Raw runtime evidence remains local-operational under `%LOCALAPPDATA%\AgentSwitchboard\...` and is not committed.

## Repository identity

- Repository: `EndeavorEverlasting/AgentSwitchboard`
- Harness merge: `72e6e60b0319cfd5085232b77721067f75f3773a`
- Tmux PowerShell launch-selection repair merge: `392f2f352219d3211ed1aa74eb4a90a51dfbc4b8`
- Operator path: merged `Open-AgentSwitchboard-Tmux.cmd` -> merged `Open-AgentSwitchboard-Tmux.ps1`
- Distribution: `Ubuntu`
- Session: `dev`

## Preserved pre-existing state

The operator's normal checkout was dirty before field acceptance. A modified `tooling/profiles/windows/technician-live-cert/stages/Repair-Technician-WSL-Ubuntu.ps1` was not touched. The field command fetched without force, validated an exact merged commit in a detached temporary worktree, executed from that isolated worktree, and removed the worktree afterward with cleanup exit `0`.

This is part of the acceptance result: live proof did not require overwriting or stashing separately owned work.

## Prerequisite state observed

The field workflow proved or reused these concrete prerequisites:

- PowerShell 7: `7.6.3`, concrete executable launch already proved before runtime.
- Git: `2.47.1.windows.1`, concrete executable launch already proved before runtime acquisition.
- WezTerm: `wezterm 20240203-110809-5046fc22`, reused.
- WSL: present; `Ubuntu` initialized and reused.
- tmux: `3.6` at `/usr/bin/tmux`, reused.

The exact-path PowerShell proof was important because the earlier launcher failure had shown that path discovery alone was not executable proof.

## Attempt 1 — durable failure, no proof inflation

The first live attempt reached all of these stages:

- exact merged commit verified;
- command-delivery harness passed `14/14`;
- WezTerm reused;
- Ubuntu reused;
- tmux 3.6 reused;
- tmux session `dev` created;
- WezTerm returned a process acknowledgement;
- launcher waited up to 45 seconds for a real tmux client.

During this attempt the operator observed a first-launch GUI/OS prompt. The prompt text and causal relationship were not captured as deterministic evidence. The operator made a choice, but the repository must **not** infer from this single observation that one particular choice was a required prerequisite.

The attempt timed out with:

`WezTerm launched, but tmux did not report an attached client for session 'dev' within 45s.`

The corresponding local artifact recorded:

- `status=failed`;
- `proofLevel=not-proven`;
- `launch.status=process-acknowledged`;
- `tmuxClientAttachedObserved=false`;
- empty `tmuxClientEvidence`;
- the original failure text.

This was correctly preserved as a failed live gate rather than being overridden by healthy prerequisite checks.

## Attempt 2 — field acceptance

The next declared attempt did not present the same GUI/OS prompt. A WSL warning about failing to start the root systemd user session was printed during preflight, but downstream behavior continued and proved the required runtime path, so that warning was non-blocking for this acceptance.

The launcher then observed:

- WezTerm reused;
- Ubuntu reused;
- tmux 3.6 reused;
- session `dev` created;
- WezTerm process acknowledgement;
- attached tmux client: `683|/dev/pts/0|dev`.

The durable artifact recorded:

- `status=success`;
- `proofLevel=tmux-client-attached`;
- `tmuxClientAttachedObserved=true`;
- `launch.status=tmux-client-attached`;
- workspace `agentswitchboard-dev`;
- window class `org.agentswitchboard.dev`;
- attach command `exec tmux attach-session -t 'dev'`.

The operator command completed with:

`DEPLOYMENT_GATE=PASS_TMUX_CLIENT_ATTACHED`

A contemporaneous operator screenshot also showed the WezTerm/tmux window with the `dev` status bar. The machine-readable certificate remains the authoritative runtime proof and retains its narrower proof ceiling.

## Proof earned

This milestone proves that the merged repository-owned launcher, on the affected Windows workstation, can:

1. preserve a dirty normal checkout through isolated exact-head execution;
2. reuse healthy PowerShell, WezTerm, WSL Ubuntu, and tmux prerequisites;
3. establish the requested `dev` tmux session;
4. receive WezTerm process acknowledgement;
5. observe a real attached tmux client;
6. emit a durable success artifact;
7. clean up the temporary worktree without destroying operator evidence.

## Proof ceiling

This milestone does **not** prove:

- that any particular first-launch prompt choice is required;
- deterministic cold-start handling of future OS or application consent prompts;
- visual focus or foreground activation solely from the JSON certificate;
- provider authentication, hosted-model response, or agent task quality;
- arbitrary Windows machines or WSL distributions beyond this observed field environment.

## Reusable best practice

### 1. Separate discovery from executable proof

A path returned by `where`, `Get-Command`, a package manager, or file existence is a candidate only. Concretely start the exact executable with bounded, side-effect-free arguments before downstream runtime depends on it.

### 2. Preserve exact-head isolation when the operator checkout is dirty

Fetch without force, verify the required merged commit, use a detached temporary worktree, run the owning validator and launcher there, preserve the operator's normal worktree, and clean up only the temporary worktree.

### 3. Treat first-launch GUI prompts as their own runtime boundary

An OS/application consent, firewall, location, URI-handler, or first-run prompt is not merely noise. Record whether it appeared, the operator choice, and the elapsed delay separately from downstream child state. Do not claim a particular answer was required unless that causality is actually proved.

If a prompted cold-start attempt times out and a later prompt-free attempt succeeds, retain both results. Classify the first as an observed interactive gate and the latter as warm-start success; do not retroactively convert the first failure into success or the second success into cold-start proof.

### 4. A live failure outranks healthy prerequisites

WezTerm process acknowledgement, installed tmux, a created session, and passing CI do not prove attachment. `tmux-client-attached` is earned only after `tmux list-clients` reports a real client.

### 5. Preserve evidence before any retry

A second run is acceptable only after the first run emitted durable evidence and the partial state is known safe. The retry must be labeled as a distinct attempt, not silently substituted for the failed run.

### 6. Classify warnings by observed effect

A warning is not automatically fatal. Preserve it, but use downstream effective-state proof to decide whether it blocked the requested behavior. Do not suppress it merely because the final gate passed.

## Remaining gap

Cold-start prompt handling remains a distinct proof gap. The successful second attempt is sufficient for the current `tmux-client-attached` field acceptance, but it does not prove that a future clean first launch will be prompt-free or that any prompt will be handled deterministically. The canonical end-to-end runtime skill now requires this cold-start/warm-start distinction.
