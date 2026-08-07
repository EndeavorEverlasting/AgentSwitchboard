---
id: agent-fleet-readiness
version: 1.0.0
status: scoped
---

# Agent Fleet Readiness

## Trigger

Use before telling an operator to run `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd`, before selecting an agent for repository work, after a missing installed fleet launcher/state error, or when tmux/terminal readiness has been proved but agent-fleet bootstrap/readiness is still unknown.

## Inputs

- current AgentSwitchboard repository identity and exact ref;
- `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet` installed root;
- presence/absence of `state.json` and `agent-switchboard.cmd`;
- current startup/readiness output when installed;
- target repository path and cleanliness state;
- requested agent or selection criteria;
- bounded sprint prompt, owned scope, forbidden scope, validation, StopWhen, token/iteration bounds, and push intent;
- provider/model route when applicable.

## Procedure

1. **Separate terminal readiness from fleet readiness.** A live WezTerm/WSL/tmux path does not establish that GNHF fleet state or the installed AgentSwitchboard launcher exists.
2. **Inspect both installed-state surfaces before post-setup commands.** Check `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\state.json` and `%LOCALAPPDATA%\AgentSwitchboard\GnhfFleet\agent-switchboard.cmd` as files. Never hand off `-ListAgents` before this classification.
3. **Classify deterministically.** Neither exists = `not-bootstrapped`; exactly one exists = `partial-or-inconsistent`; both exist = `installed-unclassified`.
4. **Bootstrap/repair when required.** For `not-bootstrapped` or `partial-or-inconsistent`, use repository-owned `Setup-AgentSwitchboard.cmd` / `tooling/gnhf/Setup-AgentSwitchboard.ps1` from a safe exact repo state. Reuse healthy dependencies. Do not manually synthesize `state.json` or copy the installed launcher as a substitute for setup.
5. **Preserve setup evidence.** Resolve the fresh `setup-summary.json` and `setup-transcript.txt` from the artifact registry before declaring bootstrap success or diagnosing failure.
6. **Prove installed surfaces after setup.** Require both state and installed launcher. Setup exit zero without the expected installed surfaces is incomplete success and must stop.
7. **List readiness before selecting an agent.** Run installed `agent-switchboard.cmd -ListAgents` or the repository startup report. Select only from current observed status.
8. **Keep provider proof separate.** `adapter-ready` or `verification-required` is not provider authentication, exact model availability, quota, or hosted response. Preserve launch-time provider probes and interactive authentication boundaries.
9. **Verify target repository safety.** Confirm identity, branch/status, nearest rules, and the GNHF clean-checkout requirement. Preserve unrelated dirty work; do not reset/stash automatically to make a launch possible.
10. **Require an explicit task prompt outside AgentSwitchboard.** Bundled role prompts are AgentSwitchboard-specific. Other repositories must supply `-Prompt` or `-PromptPath` with bounded owned/forbidden scope and validation.
11. **Launch bounded work only after all gates pass.** Use observed READY adapter, explicit prompt, iteration/token limits, observable StopWhen, and no `-PushBranch` unless push is deliberately intended.
12. **Resolve results and hand off.** Report worktree/branch, commit, validators, provider-route proof when applicable, proof ceiling, preserved work, and one exact next executable action.

## Outputs

- bootstrap classification;
- canonical next workflow (`bootstrap-or-repair`, `list-readiness`, `provider-verification`, or `launch-bounded-sprint`);
- setup/readiness artifact paths and statuses;
- selected agent plus observed readiness evidence;
- target repository safety state;
- bounded sprint inputs when launch is allowed;
- English operator handoff with proof ceiling and exact next action.

## Deterministic validation

The skill is valid only when:

- a missing installed launcher is classified as fleet bootstrap/readiness state, not as an agent or tmux failure;
- `state.json` and installed launcher are checked before any post-setup invocation is recommended;
- an inconsistent one-file installation routes to setup/repair;
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
- No post-setup launcher command before installed-state classification.

## Stop and escalate

Stop when repository identity is unknown, setup surfaces are missing from the source repo, installed state is inconsistent and setup cannot run safely, setup evidence is unavailable, requested adapter is blocked, provider verification requires unavailable credentials/interaction, target repository dirty work cannot be safely isolated, or launch would cross forbidden scope. Preserve the current artifacts and name the exact first blocked gate.
