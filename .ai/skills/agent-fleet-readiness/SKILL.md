---
id: agent-fleet-readiness
version: 1.2.0
status: experimental
---

# Agent Fleet Readiness

## Trigger

Use before telling an operator to run an installed AgentSwitchboard fleet command, before selecting an agent for repository work, after a missing installed fleet launcher/state error, after a stale repository-path error, after a shell-command mismatch, after a Windows `Access is denied` / exit 5 result from the installed CMD shim, or whenever Hermes install/repair is delaying core autoconfiguration.

## Inputs

- current AgentSwitchboard repository identity and exact ref;
- verified local repository root and active shell;
- `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet` installed root;
- presence/absence of `state.json`, `Start-AgentSwitchboard.ps1`, and the optional `agent-switchboard.cmd` compatibility shim;
- current startup/readiness output when installed;
- exact command, exit code, stdout/stderr, and shell when a launcher attempt failed;
- target repository path and cleanliness state;
- requested agent or selection criteria;
- bounded sprint prompt, owned scope, forbidden scope, validation, StopWhen, token/iteration bounds, and push intent;
- provider/model route when applicable.

## Procedure

1. **Separate terminal readiness from fleet readiness.** A live WezTerm/WSL/tmux path does not establish that GNHF fleet state or the installed AgentSwitchboard readiness implementation exists.
2. **Resolve the repository root before Git or setup.** Verify the chosen directory exists, contains `.git`, and contains `tooling/gnhf/Setup-AgentSwitchboard.ps1`. Reject stale hard-coded user-profile paths rather than running Git from the wrong directory.
3. **Keep shell boundaries explicit.** irm is a PowerShell alias, not a CMD command. A CMD parser error for a PowerShell-only command is `shell-command-mismatch`, not a Hermes/provider failure.
4. **Treat the PowerShell implementation as the installed readiness authority.** Check `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\state.json` and `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\Start-AgentSwitchboard.ps1` as files. Observe `agent-switchboard.cmd` separately as a compatibility shim; do not make CMD-shim execution a prerequisite for core readiness.
5. **Classify bootstrap state from the authority files.** Neither authority file exists = `not-bootstrapped`; exactly one exists = `partial-or-inconsistent`; both exist = `installed-unclassified`. A missing or blocked CMD shim with both authority files present is `cmd-shim-blocked`, not a partial fleet.
6. **Recover a blocked CMD shim without reinstalling.** If `cmd.exe` or the shim returns `Access is denied` / exit 5 while the authority files exist, preserve that boundary evidence, do not retry the shim, and invoke `pwsh -NoLogo -NoProfile -File "%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\Start-AgentSwitchboard.ps1" -ListAgents`.
7. **Prefer non-blocking core autoconfig when Hermes is not the priority.** Invoke repository-owned `tooling/gnhf/Setup-AgentSwitchboard.ps1 -InstallOpenCodeAndCopilot -SkipHermesInstall`. This uses existing product behavior, records Hermes unavailable/skipped/blocked in setup evidence, and continues the core fleet. Mark Hermes `TBD`/deferred; do not manually install or retry it in this lane.
8. **Preserve setup evidence.** Resolve the fresh `setup-summary.json` and `setup-transcript.txt` from the artifact registry before declaring bootstrap success or diagnosing failure.
9. **Prove installed surfaces after setup.** Require both state and installed `Start-AgentSwitchboard.ps1`. A setup status of `partial` is acceptable only when core setup succeeded and Hermes is the deferred dependency. Setup exit zero without the authority files is incomplete success and must stop.
10. **List readiness through PowerShell before selecting an agent.** Use the `prove-readiness-through-powershell` workflow. Capture exact child command, stdout, stderr, and exit code, then generate/resolve the startup readiness JSON/Markdown. Continue with observed READY adapters; Hermes may remain TBD.
11. **Keep provider proof separate.** `adapter-ready` or `verification-required` is not provider authentication, exact model availability, quota, or hosted response. Preserve launch-time provider probes and interactive authentication boundaries.
12. **Verify target repository safety.** Confirm identity, branch/status, nearest rules, and the GNHF clean-checkout requirement. Preserve unrelated dirty work; do not reset/stash automatically to make a launch possible.
13. **Require an explicit task prompt outside AgentSwitchboard.** Bundled role prompts are AgentSwitchboard-specific. Other repositories must supply `-Prompt` or `-PromptPath` with bounded owned/forbidden scope and validation.
14. **Launch bounded work only after all gates pass.** Use observed READY adapter, explicit prompt, iteration/token limits, observable StopWhen, and no `-PushBranch` unless push is deliberately intended.
15. **Resolve results and hand off.** Report resolved repo root, shell, worktree/branch, commit, validators, setup/readiness artifacts, PowerShell readiness launcher state, optional CMD-shim state, Hermes deferred/TBD state, provider-route proof when applicable, proof ceiling, preserved work, and one exact next executable action.

## Outputs

- repository-root and shell classification;
- bootstrap classification;
- canonical next workflow (`resolve-repository-root`, `core-autoconfig-defer-hermes`, `bootstrap-or-repair`, `prove-readiness-through-powershell`, `provider-verification`, or `launch-bounded-sprint`);
- setup/readiness artifact paths and statuses;
- installed PowerShell readiness launcher and optional CMD-shim state;
- Hermes state (`ready` or `TBD/deferred`);
- selected agent plus observed readiness evidence;
- target repository safety state;
- bounded sprint inputs when launch is allowed;
- English operator handoff with proof ceiling and exact next action.

## Deterministic validation

The skill is valid only when:

- a stale repository path is classified before Git/setup;
- PowerShell-only syntax used in CMD is classified as a shell mismatch, not a Hermes failure;
- `state.json` and installed `Start-AgentSwitchboard.ps1` are checked before post-setup readiness is recommended;
- `agent-switchboard.cmd` is treated as a compatibility shim rather than the installed readiness authority;
- `Access is denied` / exit 5 from the CMD shim is classified as `cmd-shim-blocked` when the authority files exist;
- `cmd-shim-blocked` routes to `prove-readiness-through-powershell` without rerunning setup or retrying the blocked shim;
- Hermes can be deferred through the existing `-SkipHermesInstall` product flag without blocking core autoconfig;
- Hermes deferred state is recorded as `TBD` and is not retried before core readiness;
- readiness is observed before agent selection;
- adapter readiness never claims provider/hosted response proof;
- non-AgentSwitchboard target work requires an explicit prompt;
- dirty target work is preserved rather than destructively cleaned;
- setup and readiness artifacts are resolved from the tracked artifact registry;
- the next action advances the first unproved gate.

Run:

`pwsh -NoLogo -NoProfile -File scripts/Test-AgentFleetReadinessHarnessCompleteness.ps1`

and:

`python -m unittest tests.test_agent_fleet_readiness_harness`

## Forbidden scope

- No P00/governance contract mutation from this scoped skill.
- No product setup/launcher behavior changes solely to satisfy this harness.
- No credentials, provider secrets, machine-local raw evidence, or personal paths in tracked files.
- No destructive Git, automatic stash/reset, force-push, merge, release, deployment, or live-target mutation.
- No claim that tmux readiness proves fleet installation.
- No claim that fleet installation proves agent readiness.
- No claim that agent readiness proves provider authentication or hosted response.
- No post-setup readiness command before installed authority-state classification.
- No repeated CMD-shim retry after an observed policy/permission block.
- No setup reinstall solely to repair a blocked optional CMD shim when the PowerShell readiness authority is healthy.
- No manual Hermes installation or repeated Hermes retry in the core-autoconfig workflow.

## Stop and escalate

Stop when repository identity cannot be resolved, setup surfaces are missing from the source repo, installed state is inconsistent and setup cannot run safely, setup evidence is unavailable, the installed PowerShell readiness launcher itself is blocked or missing, every requested non-Hermes adapter is blocked, provider verification requires unavailable credentials/interaction, target repository dirty work cannot be safely isolated, or launch would cross forbidden scope. A blocked CMD shim alone does not stop readiness proof; preserve it as `cmd-shim-blocked` and continue through the PowerShell implementation. A Hermes-only failure does not stop core autoconfig; record it as TBD/deferred and continue with the core fleet.
