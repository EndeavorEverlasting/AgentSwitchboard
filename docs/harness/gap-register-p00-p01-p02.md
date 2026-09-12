# Harness Gap Register: P00 / P01 / P02 Convergence

**Repo:** EndeavorEverlasting/AgentSwitchboard

**Branch:** `feat/harness-gap-register-p00-p01-p02`

**Sprint:** `xyz_runtime_sprint` — harness discipline / doctrine and gap registry lane

**Source:** AgentSwitchboard × BlacksmithGuild Sprint Map and Executable Launch Pack (pasted panel pack)

**Generated:** 2026-07-18

## Base state

| Repository | Branch | HEAD | Worktree clean | Required floor | Descends from floor |
|---|---|---|---|---|---|
| AgentSwitchboard | main | `0e09c00` | yes | `864e373` | yes |
| BlacksmithGuild | main | `e58e47f` | yes | `956ac2b7` | yes |

## What this register is

This is a **read-only, evidence-backed gap register** produced by inspecting current `main` of both repositories against the P00/P01/P02 requirements in the attached launch pack. It does not implement the gaps. It records exactly what is missing so the next bounded sprint can start from proven ground.

## Scope

**Owned:** inspect existing harness, schemas, skills, scripts, validators, docs, branches, and PRs; identify missing P00/P01/P02 surfaces; run all Linux-executable validators; produce a machine-readable gap register and operator report.

**Forbidden:** live provider execution, Bannerlord launch, save mutation, automatic PR merge/close, Windows-only PowerShell execution, inventing new product behavior, claiming runtime proof from static checks.

## Validation actually run

```bash
python3 tests/harness/test_tbg_end_to_end_harness.py          # PASS
python3 JSON parse checks on .ai/harness and .tbg/harness      # PASS
git diff --check                                                # PASS in both repos
PowerShell BOM inspection on both repos                         # PASS in BG, FAIL in ASB
```

## Key findings

1. **No P00/P01/P02 branches exist.** The launch pack has not been started on current main.
2. **AgentSwitchboard is missing the entire P00 orchestration spine.** No prompt-queue, queue-plan, lane-result, child-operation request/result, or trigger-snapshot schemas; no application-trigger registry; no queue planner; no child-operation dispatcher; no recovery value map for PRs #17/#20.
3. **BlacksmithGuild is missing the entire P01 callable surface.** No AgentSwitchboard operation-request/result schemas; no external-orchestration trigger export; no operation-dispatch capability; no `Invoke-TbgAgentSwitchboardOperation.ps1` dispatcher; the existing `operations.json` does not list the six P01 operations.
4. **P02 cross-repo activation is missing.** No BlacksmithGuild application profile, trigger-import adapter, one-command installed launcher, or deterministic fake-runtime tests exist in AgentSwitchboard.
5. **AgentSwitchboard PowerShell files lack UTF-8 BOM.** Every tracked `.ps1` in AgentSwitchboard is missing the BOM required by BlacksmithGuild doctrine. This is a harness hygiene gap that should be fixed before cross-repo PowerShell execution is claimed.
6. **The existing BlacksmithGuild night panel (PR #22) is a different, narrower path.** It is a direct WezTerm/GNHF launcher that runs BlacksmithGuild night objectives, but it does not implement the P00 child-operation contract, P01 callable operation surface, or P02 `agent-switchboard-blacksmithguild.cmd` adapter.

## Gap count by panel

| Panel | Blocking | Warning |
|---|---|---|
| P00 | 11 | 1 |
| P01 | 8 | 1 |
| P02 | 6 | 2 |
| Cross-repo | 1 | 0 |
| **Total** | **26** | **4** |

## Exact next command

Start P00 in an isolated AgentSwitchboard worktree:

```bash
cd /workspace/EndeavorEverlasting/AgentSwitchboard
git checkout -b feat/mainline-gnhf-orchestration-convergence main
```

Then implement the P00 schema spine, queue planner, child-operation dispatcher, fixtures, validators, and the `docs/recovery/mainline-orchestration-value-map.md` value map.

## Proof ceiling

Read-only repository inspection + static contract validation + committed gap register. No live runtime, no provider execution, no Bannerlord launch, no Windows-only PowerShell execution.
