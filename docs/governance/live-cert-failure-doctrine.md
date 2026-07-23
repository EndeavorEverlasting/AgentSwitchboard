# Live-Cert Failure Doctrine

This doctrine specializes the existing AgentSwitchboard requirements for evidence before action, no completion without proof, exact operator-path validation, and honest proof ceilings. It does not create a second governance authority; `AGENTS.md` remains canonical.

## Failure precedence

Observed live failure outranks static, synthetic, and CI success for the same operator command and environment chain. A parser pass, fixture pass, contract pass, command acknowledgement, or green workflow may prove a lower floor, but it cannot erase a technician-observed failure.

When a live run fails:

1. classify the overall live certificate as `failed` or `blocked`;
2. preserve the first failed boundary and every independently successful stage;
3. add a sanitized report to the active implementation PR and the PR that owns the proof harness when relevant;
4. create or update a public synthetic failure fixture when the failure changes repository validation or doctrine;
5. repair the same evidence chain;
6. rerun the exact remote/operator command before promoting proof.

## Core-path isolation

Optional agent installation or browser authentication may not block a narrower requested core setup. A technician request for WezTerm -> WSL -> tmux -> AGY/OpenCode must not wait on Hermes, another optional provider, or unrelated authentication unless the operator explicitly selected that surface.

Optional surfaces require their own explicit mode, bounded timeout, stage result, and failure report. Their failure may be reported without discarding successful core installation evidence.

## Interactive browser handoffs

A known prompt for Enter, newline, confirmation, or browser launch is a deterministic input boundary, not an operator troubleshooting exercise.

Automation must:

- represent the required input explicitly;
- inject it once at the declared stage;
- bound the wait for browser launch or callback;
- preserve child stdout, stderr, exit code, and timeout identity;
- fail with the exact browser-handoff stage rather than requiring Ctrl+C, `/debug`, or reconstruction by the technician.

## Cross-shell command readiness

Readiness is scoped to the exact operator shell.

- A Windows executable promised in PowerShell must resolve by executable path or repo-owned shim from PowerShell.
- A WSL-only command must resolve inside the named distribution by absolute path.
- When the runbook promises the WSL command directly from PowerShell, the setup must install a repo-owned shim, register its directory in the user PATH, refresh the current process PATH, and verify command resolution.
- Command presence in WSL does not prove PowerShell readiness. Command presence in a prior terminal does not prove a newly installed command is visible in the current process.

## Partial success

A failed live certificate may still record independently proved stages. For the sanitized July 22, 2026 technician run:

- repository pull: observed pass;
- OpenCode installation: observed pass;
- Hermes browser handoff: observed fail;
- AGY installation: observed fail;
- WezTerm resolution from PowerShell: observed fail;
- tmux resolution from PowerShell: observed fail.

Partial success must not be promoted to overall deployment success, and overall failure must not erase useful stage evidence.

## Validation

Changes governed by this doctrine must run:

```powershell
python tests/test_technician_pull_and_run_contract.py
pwsh -NoLogo -NoProfile -File scripts/Test-WindowsProfileLiveCertification.ps1
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
git diff --check
```

The repaired technician path remains unproved until the exact remote command is rerun on an authorized workstation and produces the expected command-resolution, setup, launch, and user-visible results.
