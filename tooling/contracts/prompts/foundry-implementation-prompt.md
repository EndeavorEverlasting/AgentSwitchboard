# Implementation Prompt: Foundry Delegation Analytics and Fixture ingestion

## Context
Repo: `EndeavorEverlasting/foundry`
Branch: `feature/2026-05-01-billing-bridge-branch-intelligence` or sibling branch
Lane: analytics/integration
Target fixture: `examples/fixtures/delegation-fixture-contract.json`

## Objective
Implement delegation assessment and analytics logging in Foundry that reads task/mergeability assessments and logs estimated-versus-observed outcome metrics.

## Requirements
1. **Fixture Ingestion**: Load and parse `delegation-fixture-contract.json` to extract task and mergeability assessment records.
2. **Assessment Integration**:
   - Assess tasks based on required capabilities and complexity.
   - Enforce mergeability checks (e.g. check for conflicts, check that PR is mergeable, check for unresolved threads).
3. **Delegation Decisions**:
   - Verify decisions are routed to valid executors (e.g. `AgentSwitchboard`) under the `ada-mechanical-profile`.
4. **Analytics Logging**:
   - Capture estimated versus observed metrics (duration, files changed, success rates).
   - Maintain read-only observation constraints—Foundry must NOT act as the authorization authority.

## Expected Output
A TypeScript service/component `packages/core/src/delegation/DelegationTracker.ts` that ingests the fixture data, validates task complexity bounds, and prints the estimated-versus-observed variance report.
