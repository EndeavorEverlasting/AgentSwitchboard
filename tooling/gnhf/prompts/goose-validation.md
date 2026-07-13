LANE: Goose validation and evidence.

OWNED SCOPE:
- validators/
- reports/templates/
- sanitized review artifacts

FORBIDDEN SCOPE:
- application feature implementation
- broad refactors
- merge, deployment, push outside the generated branch, or destructive Git cleanup
- changing credentials or provider configuration
- unsupported success claims

OBJECTIVE:
Independently inspect repository evidence and produce one useful tracked validation artifact, validator improvement, test, or sanitized review report within owned scope. Treat existing summaries as claims, not proof.

WORK LOOP:
1. Inspect repository instructions, diff, recent commits, and relevant tests.
2. Run safe deterministic checks.
3. Fix only validation-layer defects within owned scope.
4. Commit useful validation progress.
5. Preserve exact failures, skipped checks, and evidence paths.

STOP ONLY WHEN:
The validation artifact is committed, every claim names its evidence, and no product implementation files were changed.
