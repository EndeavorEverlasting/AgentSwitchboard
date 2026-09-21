# Execution Adapter Contract v1

Machine-readable authority: tooling/harness/execution-adapters/execution-adapter-contract.v1.json.

## Purpose

This contract defines the seam between AgentSwitchboard routing/dispatch authority and native execution harnesses. Prompt Kit remains the semantic owner of workflow meaning and prompt selection. AgentSwitchboard owns adapter selection, correlation, fail-closed dispatch, and normalized evidence. The native harness owns its process/session/provider mechanics. FirstMate remains the canonical crew/session runtime; this adapter layer is not a crew scheduler.

## V1 interface

Every adapter implements two operations:

    probe() -> agentswitchboard.execution-capability-report/v1
    execute(agentswitchboard.execution-request/v1) -> agentswitchboard.execution-receipt/v1

probe() is read-only and must not launch interactive authentication. execute() is bounded by the request timeout, mutation policy, scopes, network policy, and output limit. One accepted request produces exactly one terminal receipt.

## Initial adapters

| Adapter | Native harness | Target implementation | Minimum end-to-end proof |
|---|---|---|---|
| local-argv | OS child process | tooling/harness/execution-adapters/adapters/local_argv.py | LOCAL_RUNTIME_OBSERVED |
| claude-code | Claude Code CLI | tooling/harness/execution-adapters/adapters/claude_code.py | CLAUDE_CODE_RUNTIME_OBSERVED |
| cursor-cloud-agent | Cursor Task / CloudAgent | tooling/harness/execution-adapters/adapters/cursor_cloud_agent.py | CURSOR_CLOUD_AGENT_RUNTIME_OBSERVED |

The adapter kind is extensible; the v1 milestone requires these three implementations. OpenCode, Codex, Augment, and future harnesses implement and register the same contract rather than extending the dispatcher with another provider-specific execution branch.

## Request rules

The execution request carries immutable request/correlation identity, resolved adapter kind and mission, cwd/timeout, mutation scopes, an execution profile, adapter-specific input already resolved by upstream routing, and provenance. The adapter does not choose a Prompt Kit prompt or decide what work means next.

Interactive authentication is forbidden in v1 machine dispatch. Missing authentication is a blocker, not an invitation to open a login flow.

## Capability probe rules

A capability report separates overall readiness from host, binary, auth, transport, and dispatch. A Cursor socket or CLI binary existing does not by itself prove dispatch readiness. READY requires no blocker. BLOCKED or UNSUPPORTED requires an explicit blocker. Probe proof ceiling is CAPABILITY_PROBE_ONLY.

## Receipt rules

Terminal statuses are EXECUTED, FAILED, TIMED_OUT, and BLOCKED. EXECUTED requires an observed native execution identity and no blocker. Every non-success terminal state carries an explicit blocker. Output excerpts are bounded; sensitive raw output must be redacted before durable sharing.

Runtime proof is never established solely by adapter self-report. Each adapter needs independent deterministic observation of the requested effect.

## Minimum end-to-end proof

### local-argv

1. Real child process emits a known marker and exits 0.
2. Real child process emits known stdout/stderr and exits 42; exact code is preserved.
3. Bounded hang is classified TIMED_OUT, never EXECUTED.
4. Cwd, timing, output bounds, and normalized receipt are verified.

### Claude Code

1. ASB invokes real Claude Code CLI noninteractively.
2. Claude works only in a disposable fixture repository under request-governed mutation scope.
3. Claude produces the deterministic fixture change.
4. An independent validator proves filesystem state after Claude exits.
5. Missing binary/auth, timeout, nonzero CLI failure, or malformed structured output fail closed.
6. Receipt records native session/runtime identity when exposed.

### Cursor CloudAgent

1. One ASB dispatch reaches real Cursor Task invocation without an operator bridge.
2. Fresh CloudAgent execution identity is captured.
3. Terminal completion/failure/timeout is machine-observed.
4. Deterministic artifact/result proves the task effect independently.
5. Wrong host, missing API/Task bridge, and timeout fail closed.

## Migration and collision boundary

The current Triage dispatcher is a legacy consumer during migration. tooling/harness/triage-consumer/dispatch/schemas/dispatch-receipt.schema.json remains compatible until a translator maps generic receipts to lane receipts.

PR #332 owns current Cursor implementation files under tooling/harness/triage-consumer/dispatch/**. The shared contract floor intentionally does not modify those files. The Cursor adapter lane must reconcile and reuse #332 after this floor lands.

The end state is registry-based dispatch: resolve adapter, probe it, execute when ready, otherwise emit a blocked receipt. Generic dispatch must not accumulate native-harness execution branches.

## Proof ceiling

The v1 contract floor proves schema shape, public-safe fixtures, semantic invariants, fail-closed vocabulary, and deterministic static validation only. It does not prove local extraction/runtime, Claude Code execution, Cursor Task completion, provider delivery, deployment, or operator acceptance.

Validate with:

    pwsh -NoLogo -NoProfile -File scripts/Test-ExecutionAdapterContract.ps1

Canonical roadmap: plans/active/ASB-2026-09-execution-adapter-trio-v1.plan.json.
