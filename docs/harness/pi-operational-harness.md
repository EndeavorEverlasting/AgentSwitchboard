# Pi Operational Harness

AgentSwitchboard supports Pi as an optional, pinned execution adapter beneath repository governance, project trust, workflow selection, evidence policy, and branch ownership.

Pi is a free, MIT-licensed modular agent harness. That does **not** make every provider or model free: model access may use an existing subscription, an API key, or a local/custom provider. AgentSwitchboard records that distinction and does not silently configure credentials or choose a paid route.

## Supported upstream

| Property | Verified value |
|---|---|
| Package | `@earendil-works/pi-coding-agent` |
| Exact version | `0.81.1` |
| Source | `earendil-works/pi` |
| Minimum Node.js | `22.19.0` |
| Install policy | `npm install -g --ignore-scripts` with the exact pin |
| Project settings | `.pi/settings.json` |
| Repository skills | `.ai/skills`, loaded through project settings after trust |

The machine-readable record is `tooling/pi/harness/upstream-verification.json`. A version change requires updating that record, the adapter registry, focused tests, and validation before the repository installer may adopt it.

## Install or verify Pi

From the repository root:

```powershell
pwsh -NoLogo -NoProfile -File tooling/pi/Install-AgentSwitchboardPi.ps1 -Mode Install
```

Windows double-click or CMD surface:

```cmd
Install-AgentSwitchboardPi.cmd
```

Read-only verification:

```powershell
pwsh -NoLogo -NoProfile -File tooling/pi/Install-AgentSwitchboardPi.ps1 -Mode Verify
```

The installer:

1. reads the tracked upstream verification record and adapter registry;
2. requires Node.js `22.19.0` or newer and a resolvable npm command;
3. installs only `@earendil-works/pi-coding-agent@0.81.1`;
4. passes `--ignore-scripts`;
5. resolves the installed `pi` executable;
6. requires `pi --version` to read back the exact pinned version;
7. requires npm global-package readback;
8. writes bounded local evidence outside the repository;
9. never edits Pi credentials, providers, models, global settings, Git hooks, or repository trust.

Uninstalling through `-Mode Uninstall` removes only the verified global CLI package. It deliberately leaves settings, credentials, sessions, and project files untouched.

## Start Pi for AgentSwitchboard

```powershell
pwsh -NoLogo -NoProfile -File tooling/pi/Start-AgentSwitchboardPi.ps1
```

Windows surface:

```cmd
Start-AgentSwitchboardPi.cmd
```

Arguments after the script are passed to Pi without being written to the launch summary. Examples:

```powershell
# Continue the most recent Pi session
pwsh -NoLogo -NoProfile -File tooling/pi/Start-AgentSwitchboardPi.ps1 -PiArguments -c

# Run with Pi startup networking disabled; provider access may also be unavailable
pwsh -NoLogo -NoProfile -File tooling/pi/Start-AgentSwitchboardPi.ps1 -Offline
```

The launcher:

- verifies the exact pinned Pi version before invocation;
- starts Pi from the repository root so `AGENTS.md` is loaded;
- uses `.pi/settings.json` to expose `.ai/skills` as modular Pi skills;
- disables install/update telemetry by default with `PI_TELEMETRY=0`;
- disables the Pi version check by default with `PI_SKIP_VERSION_CHECK=1`;
- supports explicit offline startup with `PI_OFFLINE=1`;
- stores Pi sessions and launch evidence outside the repository;
- does not record raw arguments, prompts, or model output;
- never passes `--approve` or changes `defaultProjectTrust`.

## Project trust

Because the repository contains `.pi/settings.json`, Pi may ask whether to trust the project before it loads project-local settings and skills. This is expected.

The launcher prints the repository root, branch, and commit before Pi starts. Review those values and approve trust only when they identify the intended checkout. AgentSwitchboard does not bypass or pre-authorize Pi project trust.

`AGENTS.md` remains available as a context file even before project-local resources are trusted. Project trust controls `.pi/settings.json` and modular project resources; it is not a sandbox.

## Provider access

Pi supports several access classes, but AgentSwitchboard does not select or authenticate one automatically:

- existing subscription login through Pi `/login`;
- API-key providers supplied by the operator;
- local or custom providers configured and proven separately.

The Pi CLI and repository integration are free. Provider/model cost, availability, privacy, rate limits, and terms are separate runtime properties. A local-looking endpoint is not automatically private, and a free-tier route is not guaranteed to remain free.

## Modularity

The tracked `.pi/settings.json` loads the repository's reviewed `.ai/skills` directory and enables `/skill:<name>` commands. It intentionally declares no third-party packages or extensions.

Pi packages and extensions can execute code with the operator's permissions. Additions require a separate reviewed change that records the source, exact version or commit, integrity, permissions, network behavior, update path, rollback, and focused tests. Prefer project-local, pinned resources over global mutable configuration.

## What is working

- Verified current upstream package identity and exact version pin.
- Cross-platform PowerShell installer, verifier, and uninstaller.
- Windows CMD installer and launcher surfaces.
- Exact Node/npm/Pi readiness reporting.
- Project-local Pi settings and repository skill discovery.
- Low-noise telemetry and version-check defaults.
- External session and evidence storage.
- Single-agent Pi launch surface with one-writer governance.
- Existing task-intake, opinion-fusion, and autovalidation contracts.
- Cross-platform offline contract validation.

## What remains unproved

- A successful installation on a specific workstation.
- Project trust acceptance by a specific operator.
- Provider login, exact model identity, or free-tier availability.
- Endpoint privacy, telemetry readback, or observed outbound connections.
- Third-party Pi package or extension compatibility.
- Model response quality or code-delivery correctness.
- Opinion-fusion and autovalidation execution; those routes remain contract-only.
- Deployment or operator acceptance.

## Repository surfaces

| Surface | Path |
|---|---|
| Upstream verification | `tooling/pi/harness/upstream-verification.json` |
| Project settings | `.pi/settings.json` |
| Installer | `tooling/pi/Install-AgentSwitchboardPi.ps1` |
| Windows installer | `Install-AgentSwitchboardPi.cmd` |
| Launcher | `tooling/pi/Start-AgentSwitchboardPi.ps1` |
| Windows launcher | `Start-AgentSwitchboardPi.cmd` |
| Pi codebase map | `tooling/pi/harness/codebase-map.json` |
| Adapter registry | `tooling/pi/harness/pi-adapter.registry.json` |
| Task intake | `tooling/pi/harness/workflows/task-intake.workflow.json` |
| Opinion fusion | `tooling/pi/harness/workflows/opinion-fusion.workflow.json` |
| Autovalidation | `tooling/pi/harness/workflows/autovalidate.workflow.json` |
| Artifact registry | `tooling/pi/harness/artifact-registry.json` |
| Artifact schemas | `tooling/pi/harness/schemas/pi-harness-contracts.schema.json` |
| Scoped skill | `.ai/skills/pi-fusion-orchestration/SKILL.md` |
| Status report | `tooling/pi/Get-PiHarnessStatus.ps1` |
| Completeness validator | `scripts/Test-PiHarnessCompleteness.ps1` |
| Runtime support test | `tests/test_pi_runtime_support.py` |
| Existing harness test | `tests/test_pi_harness_contracts.py` |
| Optional hook | `tooling/pi/hooks/Invoke-PiHarnessPreCommit.ps1` |
| CI | `.github/workflows/pi-harness-contract.yml` |

## Workflow selection

Use **single-agent** for one bounded implementation lane. The repository now supports this as a pinned Pi launch surface, but the resulting provider, model, response, and delivery must still be observed.

Use **opinion-fusion** when two genuinely independent perspectives materially reduce architecture or routing risk. Both receive the same hashed minimized input. Their outputs remain separate and attributed. The adjudicator preserves consensus, divergence, unresolved risks, rejected alternatives, and provenance before a designated writer begins. This route remains contract-only.

Use **autovalidate** when deterministic acceptance criteria can be written independently before implementation. The architect owns the frozen gate; the builder owns scoped implementation; the validator owns execution evidence. Stop after five attempts, 45 minutes, two no-progress attempts, cancellation, changed assumptions, or contradictory evidence—whichever occurs first. This route remains contract-only.

Use **blocked** when repository state, authority, upstream identity, provider/model identity, privacy evidence, limits, artifact location, or branch ownership is missing.

## Validation

```powershell
python tests/test_pi_harness_contracts.py
python tests/test_pi_runtime_support.py
pwsh -NoLogo -NoProfile -File scripts/Test-PiHarnessCompleteness.ps1
pwsh -NoLogo -NoProfile -File tooling/pi/Get-PiHarnessStatus.ps1 -NoWrite
pwsh -NoLogo -NoProfile -File tooling/pi/Install-AgentSwitchboardPi.ps1 -Mode Verify
Test-AppHarness.cmd
git diff --check
```

The installer verification is a workstation check and may report that Pi is installable rather than installed. CI does not install Pi or call a provider.

## Artifact policy

Installation evidence, launch summaries, and sessions belong outside the repository under an operator-controlled local state root such as:

```text
%LOCALAPPDATA%\AgentSwitchboard\PiHarness\
```

Do not track credentials, raw prompts, raw model transcripts, customer data, private hostnames, local usernames, provider state, endpoint observations, sessions, or generated run evidence.

## Proof ceiling

This implementation proves verified upstream identity, exact-version installation and launch contracts, project-local skill wiring, low-noise defaults, external session storage, route contracts, validators, and cross-platform static checks. It does not prove a workstation installation, project trust, provider/model availability, endpoint privacy, extension safety, model response, opinion-fusion execution, autovalidation execution, repository delivery, deployment, or operator acceptance.
