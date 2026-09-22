---
id: lua-embedding-integration
version: 1.0.0
status: experimental
---

# Lua embedding integration

## Trigger

Use when AgentSwitchboard work mentions Lua, embedded scripting, Lua VM states, LuaJIT, host callbacks, script sandboxes, script capability allow-lists, Lua-authored dynamic logic, or AI-generated Lua snippets. This skill is also selected when a proposed Lua runtime would expose operating-system, file-I/O, package, debug, hardware, or other host capabilities.

## Inputs

- repository, branch/worktree, sprint identity, owned and forbidden scope;
- requested Lua use case and why it should be script-owned instead of host-owned;
- host-language owner and proposed host-to-Lua interface;
- script trust level: repository-owned, operator-authored, AI-generated, or untrusted;
- requested host capabilities;
- state-isolation boundary and lifecycle;
- error boundary and rollback/cleanup owner;
- exact Lua implementation/version and official embedding API source when a runtime sprint is proposed;
- resource-limit plan for untrusted or AI-generated execution.

## Procedure

1. Read `AGENTS.md`, `docs/governance/harness-doctrine.md`, `tooling/lua/harness/manifest.json`, `tooling/lua/harness/lua-embedding.contract.json`, and the Lua codebase map.
2. Keep the language a host-embedded library. The host owns the main loop, startup, rollback, and teardown.
3. Partition performance-critical or lifecycle-critical work into the host. Use Lua for dynamic logic that benefits from safe frequent change.
4. Give each declared isolation boundary an independent VM state. Require explicit create-run-close ownership and never infer cleanup from garbage collection alone.
5. Let scripts raise errors, but terminate those errors at a protected host catch boundary. Rollback and cleanup remain host-owned.
6. Keep the interpreter-first design sufficient. LuaJIT is optional; any JIT promotion requires separate benchmark, deoptimization, and reconstructible-state evidence.
7. Treat Lua as dynamically typed while enforcing runtime checks at host boundaries and documenting an internal type discipline for maintainers.
8. Sandbox fail-closed. Do not expose `os`, `io`, `package`, or `debug` by default. Register only explicit host functions from a capability allow-list.
9. Preserve Lua-native 1-based indexing. Do not add a 0-index compatibility layer merely to mirror a host language.
10. Prefer exclusion over feature growth. If a requirement belongs cleanly in the host, do not enlarge the scripting surface.
11. Keep AI-authored Lua readable and auditable: no ambient capability acquisition, no implicit global mutation, and no hidden side effects without explicit review.
12. In a harness-only sprint, stop before product/runtime embedding. Generate readiness/handoff evidence and name the separate runtime owner and promotion gates.

## Outputs

- selected Lua workflow and host/Lua boundary map;
- machine-readable embedding-contract result;
- sandbox allow-list/deny decision when applicable;
- validator receipts;
- `lua-harness-report.md` and `lua-readiness.json` outside tracked authority;
- exact downstream runtime gate when product embedding is the next owner.

## Deterministic validation

- `python tests/test_lua_harness_contracts.py`
- `pwsh -NoLogo -NoProfile -File scripts/Test-LuaHarnessCompleteness.ps1`
- `python tooling/lua/Get-LuaHarnessStatus.py --no-write`
- `pwsh -NoLogo -NoProfile -File scripts/Test-AgentDocumentationContract.ps1`
- `git diff --check <base>...HEAD`

## Forbidden scope

- no edits to `AGENTS.md` or governance policy in this harness lane;
- no AgentSwitchboard product code mutation under a harness-only sprint;
- no Lua installation or package-manager mutation;
- no network/provider/secret access;
- no implicit exposure of `os`, `io`, `package`, or `debug`;
- no script-owned host rollback or teardown;
- no shared mutable VM state across declared isolation boundaries by default;
- no JIT requirement or performance claim without separate evidence;
- no runtime success claim from fixtures, static contracts, hosted CI, or a Lua executable merely being present;
- no generated evidence committed accidentally.

## Stop and escalate

Stop when the next action requires a concrete Lua distribution/version choice, official embedding API verification, host wrapper/product code, dependency installation, runtime resource limits, live sandbox enforcement, memory/leak observation, deployment, or another forbidden surface. Hand off the exact unresolved gate to a separately authorized runtime sprint and preserve the harness proof ceiling.
