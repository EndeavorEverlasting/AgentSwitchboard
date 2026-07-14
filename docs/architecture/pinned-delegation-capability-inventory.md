# Pinned Delegation Capability Inventory

This inventory maps BlacksmithGuild's state, routing, evidence, and agent-feedback capabilities to versioned destinations and portability dispositions.

## Donor Pins
- Repository: `EndeavorEverlasting/BlacksmithGuild`
- `feat/continuum-harness-interoperability`: `6243ce524459a6c70e46e24508a1731386e34db8`
- `origin/agent-feedback-stop-hook`: `c4a6c93e90bab382f3bbc58bf2d0b21623e59745`
- `main`: `b1975f523dd7fe088e17e013127b0f0e73d2be34`

## Disposition Classifications

| Capability | Pinned Commit | Pinned File Paths | Canonical Destination | Disposition Value |
|---|---|---|---|---|
| **Event Journal** | `6243ce52` | `scripts/tbg/Read-TbgJournal.ps1`, `Write-TbgJournalEvent.ps1` | `Continuum` Core | `continuum_portable_now` |
| **Deterministic Reducers** | `6243ce52` | `scripts/tbg/Invoke-TbgReducer.ps1`, `Resolve-TbgStateView.ps1` | `Continuum` Core | `continuum_portable_now` |
| **Work-Item Model** | `6243ce52` | `scripts/tbg/Reduce-TbgWorkItem.ps1` | `Continuum` Core | `continuum_portable_now` |
| **Constraints & Dispositions**| `6243ce52` | `scripts/tbg/Reduce-TbgConstraint.ps1`, `Reduce-TbgDisposition.ps1` | `Continuum` Core | `continuum_portable_now` |
| **Capability Gaps** | `6243ce52` | `scripts/tbg/Reduce-TbgCapabilityGap.ps1` | `Continuum` Core | `continuum_portable_now` |
| **Action Lifecycle** | `6243ce52` | `scripts/tbg/Resolve-TbgAction.ps1` | `Continuum` Core | `continuum_portable_now` |
| **Risk Classification** | `6243ce52` | `.tbg/state/provider-catalog.json` | `Continuum` Core | `continuum_portable_now` |
| **Provider Catalog** | `6243ce52` | `scripts/tbg/Build-TbgProviderCatalog.ps1` | `Continuum` Core | `continuum_portable_now` |
| **Use-Case & Skill Routing** | `6243ce52` | `scripts/tbg/Test-TbgSkillRouting.ps1` | `Continuum` Adapters | `continuum_after_runtime_adapter` |
| **Artifact Engine** | `6243ce52` | `scripts/tbg/Invoke-TbgArtifactEngine.ps1` | `Continuum` Adapters | `continuum_after_runtime_adapter` |
| **Watcher Lifecycle** | `6243ce52` | `scripts/tbg/Test-TbgArtifactWatcher.ps1` | `Continuum` Adapters | `continuum_after_runtime_adapter` |
| **Agent Feedback Harness** | `c4a6c93e` | `docs/handoff/agent-feedback-harness.md`, `scripts/write-agent-feedback-summary.ps1` | `AgentSwitchboard` | `agent_switchboard_candidate` |
| **Runtime Proof Boundaries** | `c4a6c93e` | `scripts/tbg/Test-TbgRuntimeGuardrail.ps1` | BlacksmithGuild | `domain_specific_retain` |

## Portable Candidates
- All core state engine components (`event-journal`, `reducers`, `work-item-model`, `constraints`, `dispositions`, `capability-gaps`, `action-lifecycle`, `risk-classification`, and `provider-catalog`) can be imported into `Continuum` without any external dependencies.

## Deferred Candidates
- `watcher-lifecycle` and `artifact-engine` are deferred until `Continuum` has a fully reviewed runtime-adapter interface.
- `agent-feedback-harness` is assigned as a candidate for `AgentSwitchboard` rather than `Continuum` to keep local agent execution loops tight.

## Risks & Ownership Questions
- **Safety Boundary**: The feedback loop should not silently merge PRs or execute unchecked scripts on the host system.
- **Authority**: Deciding task priority and mergeability must reside in `Continuum`/Human, not `AgentSwitchboard`.
