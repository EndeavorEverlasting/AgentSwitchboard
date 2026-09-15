# ASB-2026-09 FirstMate→ASB observation adapter

Phase map for translating FirstMate `fm-fleet-snapshot.v1` into `asb.agent-observation/v1` without a second watcher.

## Completed floor

| Phase | Result | Evidence |
|---|---|---|
| Protocol contract freeze | **INTEGRATED** | PR #184 / merge `6c80be9c…` |
| Observation adapter v1 | **INTEGRATED** | PR #204 / merge `5187195382584787bf30c7043660d74327549cd7` |
| Admin Box adoption of Phase-2 head | **PROVEN** | Live `AgentSwitchBoard-Live`; adapter 13/13; protocol 90/90 |
| Disposable-home live emitter→adapter | **OBSERVED** | Receipt `%LOCALAPPDATA%\AgentSwitchboard\runtime-proof\fm-asb-observation\20260914T204242Z\` |
| WSL distro-probe timeout false ceiling | **INTEGRATED** | PR #278 / merge `fa5b9be7d4253b4791565454ed7a9cebe4f3b6c5` — honor `-PrerequisiteTimeoutSeconds` up to 300s |
| ASQ-017 advance past distro probe | **PROVEN** | Live attempt `operator-crew-20260914T215535Z`: contract PASS → physical-floor-continue reaches tool/auth gates |
| Protected controls after live attempt | **PROVEN** | Disposable observation + synthetic adapter tests PASS on `main@fa5b9be` |

## Successor phases

1. **Operator/crew live observation (BLOCKED).** Dependency chain observed on Admin Box:
   - no `$HOME/firstmate` / operator metas (only disposable seed);
   - ASQ-017 now stops at **`STATUS=BLOCKED_GITHUB_AUTH` / exit 45** after user-local `gh` 2.67.0 install cleared `MISSING_TOOLS=gh` / sudo-apt path;
   - credential automation is forbidden; operator must `gh auth login` in Ubuntu, then rerun ASQ-017, then obtain a real task before `OBSERVED_OPERATOR_CREW`.
2. **Crew-state fidelity.** Disposable seed still maps to `phase=unknown` for `working:` status; prove mappings on a real/instrumented home.
3. **Phase 3 — Prompt Kit routing adapter.** Out of observation mutation scope.
4. **Later — prompt dispatch / rollover.** Out of current slice.

## Owned / forbidden

- Owned: observation adapter, fixtures, regressions, live observation receipts (untracked), durable phase-map cite; bounded FM-WSL-12 false-blocker repairs required to reach the observation gate.
- Forbidden: `fm-send` / `fm-control`, new watcher/scheduler, Prompt Kit routing implementation in this plan's mutation scope, committing machine-local receipts/secrets, personal FirstMate home mutation, credential automation / token capture.

## Proof ceiling

**Reached:** `OBSERVED_DISPOSABLE_HOME` + ASQ-017 live attempt fail-closed at `BLOCKED_GITHUB_AUTH`.  
**Not reached:** `OBSERVED_OPERATOR_CREW`, physical-floor PASS, Prompt Kit routing/rollover.

## Validation

```text
python tests/test_firstmate_agent_observation_adapter.py
pwsh -NoLogo -NoProfile -File scripts/Test-FmAsbPromptKitProtocolContract.ps1
```

## Next command (credential gate → physical floor → operator observation)

Owner: **Admin Box operator** (Ubuntu `gh` auth). Dependency: interactive GitHub login in WSL; no token capture in evidence.

```powershell
$ErrorActionPreference='Stop'
$repo = if ($env:AGENT_SWITCHBOARD_REPO) { $env:AGENT_SWITCHBOARD_REPO } else { Join-Path $env:USERPROFILE 'dev\AgentSwitchBoard-Live' }
Set-Location -LiteralPath $repo
git fetch --all --prune --tags
if (git status --porcelain) { git status --short; throw 'Checkout dirty; preserve work before continuing.' }
git switch main; git pull --ff-only origin main
git merge-base --is-ancestor fa5b9be7d4253b4791565454ed7a9cebe4f3b6c5 HEAD
if ($LASTEXITCODE -ne 0) { throw 'Distro-probe timeout fix not contained in refreshed main.' }
wsl.exe -d Ubuntu -- bash -lc 'export PATH="$HOME/.local/bin:$PATH"; gh auth login --hostname github.com --git-protocol https --web; gh auth status --hostname github.com'
$ev = Join-Path $env:LOCALAPPDATA ('AgentSwitchboard\runtime-proof\fm-asb-observation\operator-crew-' + (Get-Date -Format 'yyyyMMddTHHmmssZ'))
New-Item -ItemType Directory -Force -Path $ev | Out-Null
$fmPath = '/home/pa_rperez26/.cache/asb-fm-observation/firstmate-b182d0f908b78d08c7ccb8dce3775bdca8c5d657'
pwsh -NoLogo -NoProfile -File .\Invoke-Asq017AdminBoxLiveFloor.ps1 -SkipGitRefresh -FirstMatePath $fmPath -EvidenceRoot $ev -PrerequisiteTimeoutSeconds 180
$childExit=$LASTEXITCODE; Write-Host "CHILD_EXIT_CODE=$childExit"; if ($childExit -ne 0) { throw "ASQ-017 failed with exit $childExit" }
```
