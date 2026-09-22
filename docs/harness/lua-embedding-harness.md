# Lua embedding operational harness

This harness makes a future Lua integration reviewable before product code is allowed to depend on it.

The design basis is the owner-supplied technical breakdown attributed to Roberto Ierusalimschy on 2026-08-09. This sprint does **not** independently verify that attribution or select an upstream Lua version. It converts the supplied principles into repository-owned engineering gates.

## Architectural contract

Lua is treated as an **embedded library**, not the owner of the application main loop. AgentSwitchboard's host layer retains lifecycle, scheduling, rollback, cleanup, performance-critical behavior, and the script-visible capability boundary.

The scripting layer is reserved for dynamic logic that benefits from frequent controlled change.

## VM state and cleanup

Each declared isolation boundary requires an **independent VM state**. A future host wrapper must make create-run-close ownership explicit so one state can be reset or destroyed without relying on unrelated process memory.

A state-close call in source is not leak proof. Runtime evidence must exercise repeated teardown under bounded resource observation.

## Error boundary

Lua code may raise an error. The host must invoke Lua through a protected boundary, catch the error, and own rollback and cleanup. An uncaught script error is never allowed to become the host's normal failure-control mechanism.

## Execution model

Interpreter-first is sufficient. A small bytecode VM and simple dispatch are acceptable design assumptions for this harness. LuaJIT is not a prerequisite.

If JIT is later adopted, its sprint must prove deoptimization and reconstructible interpreter/stack state instead of treating JIT success as a transparent optimization.

## Dynamic type discipline

Lua remains dynamically typed. Host boundaries must perform runtime checks, while developers document an internal type discipline for tables, callback parameters, return values, and host-owned resources.

Performance-critical allocation and static layout stay in the host when possible.

## Sandbox and security

The default is **deny**.

`os`, `io`, `package`, and `debug` are forbidden by default. Script-visible host behavior is exposed only by registering explicitly approved host functions in a capability allow-list.

The tracked safe and unsafe Lua fixtures are static contract inputs. The unsafe fixture is never executed by the harness.

Before untrusted or AI-generated scripts run, a runtime sprint must define resource limits as well as capability limits.

## Conceptual integrity

When a requirement can be solved cleanly in the host, prefer the host instead of expanding Lua.

Lua-native **1-based** table indexing is preserved. The harness does not invent a 0-index compatibility layer.

Feature exclusion is the default when a new scripting feature would increase hidden state or capability surface without a demonstrated need.

## AI-authored Lua

Generated snippets must remain human-auditable and non-magical. Ambient capability acquisition, implicit global mutation, and hidden side effects are rejected unless a later explicit capability contract reviews them.

The goal is not to make Lua less expressive; it is to keep generated behavior explainable at the host/script boundary.

## Workflow choice

Use `lua-task-intake` first for a new Lua request.

Use `lua-embedding-design-validation` for host ownership, lifecycle, errors, execution model, performance partition, or type-discipline changes.

Use `lua-sandbox-validation` whenever scripts are untrusted/AI-generated or request OS, I/O, package, debug, hardware, or host capabilities.

Use `lua-failure-recovery` when a deterministic gate fails.

Use `lua-handoff` when the harness is complete or product/runtime code is the next owner.

## Artifacts

Generated evidence is untracked and belongs under the operating-system temporary directory:

- `lua-harness-report.md`
- `lua-readiness.json`
- future `lua-runtime-handoff.json`

Generate the current report with:

```powershell
python tooling/lua/Get-LuaHarnessStatus.py
```

For read-only terminal output:

```powershell
python tooling/lua/Get-LuaHarnessStatus.py --no-write
```

## Validation

```powershell
python tests/test_lua_harness_contracts.py
pwsh -NoLogo -NoProfile -File scripts/Test-LuaHarnessCompleteness.ps1
python tooling/lua/Get-LuaHarnessStatus.py --no-write
pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1
git diff --check <base>...HEAD
```

The optional pre-commit and pre-push helpers are never installed implicitly.

## Runtime promotion gate

A later explicitly authorized product/runtime sprint must, at minimum:

1. pin an exact Lua implementation/version and official embedding API source;
2. implement the host wrapper and public host-to-Lua interface;
3. create independent VM states and explicit create-run-close lifecycle;
4. prove host-caught script errors plus rollback/cleanup;
5. prove default-deny sandbox behavior and allow-listed host functions;
6. define and test resource limits before untrusted/AI-generated execution;
7. prove repeated state teardown with bounded resource/leak evidence;
8. document the host-versus-script performance partition;
9. run the exact runtime path through end-to-end validation.

## Proof ceiling

A green Lua harness proves the tracked architecture, workflow, sandbox policy, artifacts, validators, hooks, fixtures, documentation, and hosted contract gates. It does **not** prove a Lua runtime is installed, embedded, executing, isolated, sandboxed, leak-free, faster, or accepted by an operator.
