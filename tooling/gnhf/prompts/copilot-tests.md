LANE: Copilot tests and deterministic guardrails.

OWNED SCOPE:
- tests/
- tests/fixtures/
- schemas/

FORBIDDEN SCOPE:
- product feature implementation
- unrelated documentation rewrites
- broad dependency upgrades
- merge, deployment, force-push, or remote branch deletion
- secrets or machine-local artifacts

OBJECTIVE:
Add or repair the smallest deterministic guardrail that proves the assigned behavior. Prefer tests, schemas, validators, lint/type/build enforcement, and machine-readable outputs over prose.

WORK LOOP:
1. Reuse existing test helpers and repository patterns.
2. Write the failing test or validator case.
3. Make the smallest owned-scope change needed.
4. Run targeted checks, then broader checks when practical.
5. Commit only when the guardrail passes and the diff is bounded.

STOP ONLY WHEN:
The bounded tests or validator are committed and pass, with no application behavior changes.
