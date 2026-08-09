# Lua embedding harness status

Status: **contract ready; runtime unproved**

## Working

- The owner-supplied Lua design principles are encoded as a machine-readable embedding contract.
- Lua is constrained to an embedded-library role with the host owning the main loop.
- Independent VM states and explicit state close are required.
- Script errors terminate at a protected host catch boundary with host-owned rollback and cleanup.
- Interpreter-first is the baseline; JIT is optional and separately gated.
- Dynamic host boundaries require runtime checks and an internal developer type discipline.
- Sandbox policy is deny-by-default and explicitly forbids `os`, `io`, `package`, and `debug` unless a future reviewed contract changes the allow-list.
- Lua-native 1-based indexing is preserved.
- AI-authored Lua requires explicit capabilities and auditable side effects.
- Task intake, embedding-design, sandbox, failure-recovery, and handoff workflows are tracked.
- Generated report/readiness evidence is untracked by policy.
- Optional pre-commit and pre-push helpers are tracked but never installed implicitly.

## Broken or blocked

- No exact Lua implementation/version or official embedding API has been selected or verified.
- No product host wrapper exists under this harness-only scope.
- No live Lua VM state has been created, reset, or closed.
- No runtime sandbox enforcement, resource limit, memory isolation, teardown, or leak evidence exists.
- No JIT benchmark or deoptimization evidence exists, and none is required for the interpreter-first baseline.

## Missing

- exact Lua implementation/version and official embedding API pin;
- separately authorized product/runtime host-wrapper implementation;
- independent-state runtime tests;
- protected host-call/error rollback tests;
- deny/allow sandbox runtime tests;
- resource-limit definition and tests for untrusted or AI-generated scripts;
- repeated teardown and bounded resource/leak evidence;
- exact end-to-end operator/runtime proof.

## Safe next state

After the repository contract gate is green, the next useful action is a separately authorized runtime integration sprint. That sprint must pin the Lua implementation/version and official embedding API before touching product code, then implement the smallest host wrapper capable of create-run-close, protected error handling, and default-deny capability exposure.

## Proof ceiling

This tracked report proves harness intent and current repository contract state only. It does not prove Lua installation, product embedding, VM execution, sandbox enforcement, state isolation, teardown, leak freedom, JIT behavior, performance, deployment, or operator acceptance.
