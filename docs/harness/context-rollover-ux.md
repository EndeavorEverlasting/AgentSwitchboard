# Context rollover UX — FirstMate ↔ ASB ↔ Prompt Kit

Machine-readable authority: `.ai/harness/fm-asb-promptkit-rollover-state-machine.json`.

Protocol binding: `asb.context-transition/v1` in `.ai/harness/schemas/fm-asb-promptkit/`.

## Intent

Context rollover must feel like a **safe checkpointed continuation**, not a session crash and not a magical “resume.” FirstMate does not expose a universal resume contract across harnesses; the portable operation is `relaunch` after durable truth is current.

Core invariant:

> The old conversation may disappear only after everything required to continue the mission has become durable; the new conversation may mutate only after it proves it recovered the same mission against current truth.

## User-visible states

| User-visible state | Meaning | Interrupt? |
|---|---|---:|
| Healthy | Conversation can continue normally. | No |
| Context getting full | Verified or estimated pressure is rising; ASB prepares in the background. | No |
| Checkpointing | Durable task state is being brought current. | No |
| Ready to continue fresh | Checkpoint proven complete; replacement may proceed when authorized. | No |
| Relaunching | FirstMate replaces the agent while preserving task/worktree identity. | No |
| Verified & continuing | Replacement loaded durable state and passed post-rollover checks. | No |
| Needs attention | A prerequisite/postcondition could not be proven safely. | Yes |

Default indicators stay quiet:

```text
● Working
◐ Context getting full · preparing checkpoint
✓ Checkpoint ready
↻ Fresh context · work preserved · continuing
⚠ Needs attention · rollover paused
```

Do not stream raw percentages in the normal view.

## Two health dimensions

```text
CONVERSATION HEALTH
├── Resource pressure — distance to harness/model context limit
└── Semantic health — whether the task model is still grounded
```

| Resource pressure | Semantic condition | Behavior |
|---|---|---|
| Low | Healthy | Continue |
| High (verified) | Healthy | Checkpoint → rollover at safe boundary |
| Low | Drifting | Critique/reground without necessarily restarting |
| High (verified) | Drifting | Checkpoint + rebootstrap/relaunch |
| Unknown / estimated | Healthy | Prepare checkpoint only; never auto-relaunch |
| Any | Unrecoverable durability gap | Stop before rollover; keep current session |

## Pressure confidence tiers

**Tier A — automatic eligible:** `native-provider`, `native-harness`, `verified-adapter`

**Tier B — preparation only:** `estimated`, `unavailable`

Tier B may prepare checkpoints and reduce nonessential context. It must not automatically terminate a healthy agent.

## State machine (internal)

```text
HEALTHY
  │ pressure.rising.* / semantic.divergence
  ▼
CHECKPOINT_PREP → CHECKPOINTING
  │
  ├─ checkpoint.failed ──────────────► NEEDS_ATTENTION (old agent preserved)
  │
  ▼
ROLLOVER_READY
  │
  ├─ pressure.dropped / deferred ────► HEALTHY
  │
  └─ rollover.authorized (crew + tmux/Herdr + verified/operator)
           ▼
      TRANSITION (FirstMate relaunch)
           │
           ├─ precheck refused / launch failed / uncertain ─► NEEDS_ATTENTION
           │
           ▼
      NEW_CONTEXT → post.verify.passed → VERIFIED → HEALTHY
                 └─ post.verify.failed → NEEDS_ATTENTION
```

Protocol message states map as:

| `asb.context-transition/v1` state | Internal states |
|---|---|
| PROPOSED | CHECKPOINT_PREP |
| CHECKPOINTING | CHECKPOINTING |
| READY | ROLLOVER_READY |
| EXECUTING | TRANSITION, NEW_CONTEXT |
| COMPLETED | VERIFIED |
| FAILED | NEEDS_ATTENTION, FAILED |

Transition method for crew tasks is `firstmate-relaunch` (never harness keystrokes).

## Events

| Event | Meaning |
|---|---|
| `pressure.rising.verified` | Tier A pressure crossed prepare threshold |
| `pressure.rising.estimated` | Tier B pressure; prepare only |
| `semantic.divergence` | Prompt Kit / correction burden indicates drift |
| `checkpoint.requested` / `progress` / `completed` / `failed` | Durability lifecycle |
| `rollover.authorized` | Checkpoint complete and automatic/operator gate passed |
| `rollover.deferred.unverified-pressure` | Checkpoint kept; auto transition disabled |
| `relaunch.requested` / `precheck.refused` / `old-stopped` / `new-running` | FirstMate control-plane lifecycle |
| `relaunch.launch-failed-after-stop` | Old agent gone; replacement did not start |
| `relaunch.state-uncertain` | New record published but agent not confirmed |
| `post.verify.passed` / `failed` | ASB post-rollover semantic verification |
| `operator.decision.required` | Human wake |

## Checkpoint requirements

Before FirstMate replaces an agent, prove current:

- mission / requested outcome
- exact repo / worktree
- branch + HEAD
- dirty-state summary
- current Prompt Kit prompt identity + registry/prompt SHA
- completed/proven state and remaining work
- blockers / decisions
- proof ceiling and exact next action
- evidence refs
- grounding episode

ASB depends on the generic checkpoint contract (`requested` / `complete` / `failed`), not a literal `/stow` command string. FirstMate may implement checkpoint via `/stow` or a later programmatic API.

## Backend and scope gates

| Backend | Automatic crew rollover v1 |
|---|---:|
| tmux | Supported |
| Herdr | Supported |
| Zellij / cmux / Orca | Checkpoint only |

| Scope | v1 posture |
|---|---|
| crew-task | Automatic when authorized |
| primary-session | Checkpoint + fresh-session packet; operator starts fresh primary |

## First successor turn

Mutation is forbidden until the replacement:

1. loads the checkpoint,
2. refreshes durable repository truth,
3. reconciles differences,
4. states the next bounded action.

## Receipt stack

Persist four receipts plus one aggregate:

1. **Pressure observation** — why preparation started
2. **Checkpoint receipt** — proof conversation state can be discarded
3. **FirstMate relaunch receipt** — runtime/worktree/process transition
4. **Post-rollover verification receipt** — successor recovered the mission
5. **CONTEXT TRANSITION aggregate** — user-facing summary referencing the four

Fixtures live under `.ai/harness/fixtures/fm-asb-promptkit/receipts/`.

### Default user view

```text
Fresh context ready · continuing
```

### Expanded technical details

```text
Task        task-42
Transition  ctx_…
Prompt      P83
Generation  4 → 5
Worktree    unchanged
HEAD        unchanged
Checkpoint  PASS
Verification PASS
```

### Aggregate receipt (PASS)

```text
CONTEXT TRANSITION · PASS

Task
  auth-refactor

Why
  Verified context pressure
  Prompt Kit intervention: REBOOTSTRAP

Before
  Generation: 4
  Grounding: ge_018
  Prompt: P83

Checkpoint
  PASS

Transition
  Method: FirstMate relaunch
  Worktree preserved: yes

After
  Generation: 5
  Grounding: ge_019

Verification
  Durable state loaded: yes
  Repository identity: yes
  Prompt identity: yes
  Next action recovered: yes

Outcome
  CONTINUING
```

### Needs attention — checkpoint failed

```text
Needs attention · rollover paused

The current conversation is still running.
AgentSwitchboard could not prove that the continuation checkpoint is complete.

Missing:
• exact repository evidence floor

Nothing was relaunched.

[Retry checkpoint] [Continue current session] [View missing proof]
```

### Needs attention — launch failed after stop

```text
⚠ Agent stopped; work is preserved

The previous agent exited successfully.
The replacement agent did not start.

Preserved:
✓ worktree
✓ uncommitted changes
✓ checkpoint
✓ task identity
✓ continuation note

No agent is currently running.

[Retry relaunch] [Open task] [View receipt]
```

## Failure taxonomy (do not collapse)

| Failure | UX | Recovery |
|---|---|---|
| Pressure uncertain | Monitoring | Prepare only |
| Checkpoint incomplete | Rollover paused | Keep current agent |
| FirstMate precheck refused | Rollover paused | Keep old agent |
| Old agent stop unproven | Transition uncertain | Do not spawn replacement |
| Old stopped; new launch failed | Agent stopped · work preserved | Retry from checkpoint |
| New record published; agent unconfirmed | Agent state uncertain | Let FirstMate recover |
| Wrong repo/worktree after relaunch | Verification failed | Stop mutation; reground |
| Checkpoint not loaded | Verification failed | Bounded recovery / relaunch |
| Legitimate HEAD advance | Reconciling newer state | Refresh and rebuild task model |
| Task identity mismatch | Hard stop | No automatic continuation |

## Notification policy

Silent for successful prepare/checkpoint/relaunch/verify. Passive AFK return summary may mention completed refreshes. Interrupt only for safety failures, consent gates, unsupported backends, identity mismatches, or operator decisions.

## AFK return summary (draft)

```text
WHILE YOU WERE AWAY

Context health
4 safe context refreshes
0 lost checkpoints
0 identity mismatches

Agent transitions
auth-refactor    Pi        gen 4 → 5   ✓
migration        Codex     checkpoint ready · rollover deferred

Needs you
migration: Codex safe-state cannot currently be verified for automatic rollover
```

## Proof ceiling

This document plus the state-machine JSON and receipt fixtures prove **contract UX shape** only. They do not prove live context-pressure observation, FirstMate relaunch, or Admin Box AFK behavior.
