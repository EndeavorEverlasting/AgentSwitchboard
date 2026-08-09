import json
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / 'scripts' / 'Test-RepositoryWorkLedgerContract.ps1'
POLICY = ROOT / '.ai' / 'harness' / 'repository-work-ledger.policy.json'


def run_validator(path=None, policy=None):
    command = ['pwsh', '-NoLogo', '-NoProfile', '-File', str(VALIDATOR)]
    if path:
        command += ['-LedgerPath', str(path)]
    if policy:
        command += ['-PolicyPath', str(policy)]
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=True)


HEADER = '''contractRef: agentswitchboard.repository-work-ledger.v1@1.0.0
localAuthority: AGENTS.md

# Test ledger

Continuation states are not stopping states.
PR opened is not completion.
DONE is strict.
Work class is required by the AgentSwitchboard local execution profile.
Canonical terminal action: none; no safe actionable work remains
'''


def task(**overrides):
    values = {
        'Status': 'READY', 'Priority': 'P1', 'Work class': 'BOUNDED', 'Owner': 'unclaimed',
        'Branch / PR': 'none', 'Scope': 'bounded test scope',
        'Forbidden': 'production mutation', 'Dependencies': 'none',
        'References': '`AGENTS.md`', 'Acceptance gate': 'observable proof exists',
        'Gate': 'none', 'Last proof': 'none',
        'Next action': 'create the bounded artifact and validate it',
        'Updated': '2026-08-09',
    }
    values.update(overrides)
    body = '\n'.join(f'- **{key}:** {value}' for key, value in values.items())
    return f'{HEADER}\n## ASQ-900 — Test task\n\n{body}\n'


class RepositoryWorkLedgerContractTests(unittest.TestCase):
    def test_repository_ledger_passes(self):
        result = run_validator()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('[repository-work-ledger] PASS', result.stdout)
        self.assertIn('local-profile=bounded-frontier', result.stdout)

    def run_temp(self, content):
        with tempfile.NamedTemporaryFile('w', suffix='.md', delete=False, dir=ROOT, encoding='utf-8') as handle:
            handle.write(content)
            relative = pathlib.Path(handle.name).relative_to(ROOT)
        try:
            return run_validator(relative)
        finally:
            pathlib.Path(handle.name).unlink(missing_ok=True)

    def test_done_requires_durable_proof_and_terminal_action(self):
        result = self.run_temp(task(Status='DONE', **{'Last proof': 'completed successfully', 'Next action': 'merge later'}))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('DONE requires durable Last proof', result.stderr)
        self.assertIn('DONE requires canonical terminal Next action', result.stderr)

    def test_done_accepts_durable_proof(self):
        result = self.run_temp(task(Status='DONE', Owner='agent-session', **{'Last proof': 'commit:1234567', 'Next action': 'none; no safe actionable work remains'}))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_operator_requires_exact_gate(self):
        result = self.run_temp(task(Status='OPERATOR', Owner='operator', Gate='none'))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('OPERATOR requires an exact Gate', result.stderr)

    def test_stale_local_reference_fails(self):
        result = self.run_temp(task(References='`definitely/not/a/real/path.txt`'))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('stale local reference', result.stderr)

    def test_malformed_task_heading_is_rejected(self):
        content = task() + '\n## ASQ-9 - Hidden task\n\n- **Status:** READY\n'
        result = self.run_temp(content)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('malformed ASQ heading', result.stderr)

    def test_duplicate_fields_are_rejected(self):
        content = task().replace('- **Status:** READY', '- **Status:** DONE\n- **Status:** READY', 1)
        result = self.run_temp(content)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("duplicate field 'Status'", result.stderr)

    def test_claimed_rejects_unassigned_owner_sentinels(self):
        for owner in ('unclaimed', 'none', 'unknown', 'tbd', 'n/a'):
            with self.subTest(owner=owner):
                result = self.run_temp(task(Status='CLAIMED', Owner=owner))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('CLAIMED requires a concrete owner', result.stderr)

    def test_continuation_rejects_non_action_next_steps(self):
        for next_action in ('status unchanged', 'PR opened', 'CI green', 'wait', 'merge later'):
            with self.subTest(next_action=next_action):
                result = self.run_temp(task(**{'Next action': next_action}))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('continuation state requires an executable next action', result.stderr)

    def test_continuation_accepts_concrete_action_verb(self):
        result = self.run_temp(task(Status='VERIFY', Owner='agent-session', **{'Next action': 'run the owning validator and record its artifact receipt'}))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_work_class_is_required(self):
        content = task().replace('- **Work class:** BOUNDED\n', '')
        result = self.run_temp(content)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing field 'Work class'", result.stderr)

    def test_invalid_work_class_is_rejected(self):
        result = self.run_temp(task(**{'Work class': 'EPIC'}))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid Work class 'EPIC'", result.stderr)

    def test_unbounded_ready_requires_bounded_decomposition(self):
        result = self.run_temp(task(**{'Work class': 'UNBOUNDED', 'Next action': 'inspect the repository until the route becomes clear'}))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('UNBOUNDED READY requires a next action that creates bounded child work', result.stderr)

    def test_unbounded_ready_accepts_bounded_decomposition(self):
        result = self.run_temp(task(**{'Work class': 'UNBOUNDED', 'Next action': 'decompose this parent into bounded child ASQ items with acceptance gates'}))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_unbounded_cannot_be_claimed_as_monolithic_implementation(self):
        result = self.run_temp(task(Status='CLAIMED', Owner='agent-session', **{'Work class': 'UNBOUNDED', 'Next action': 'execute the parent implementation'}))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('UNBOUNDED tasks may only use READY, BLOCKED, OPERATOR, or DONE', result.stderr)

    def test_policy_cannot_remove_v1_required_field(self):
        policy = json.loads(POLICY.read_text(encoding='utf-8'))
        policy['requiredFields'].remove('Acceptance gate')
        with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False, dir=ROOT, encoding='utf-8') as handle:
            json.dump(policy, handle)
            relative = pathlib.Path(handle.name).relative_to(ROOT)
        try:
            result = run_validator(policy=relative)
        finally:
            pathlib.Path(handle.name).unlink(missing_ok=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('requiredFields does not match immutable v1 contract', result.stderr)


if __name__ == '__main__':
    unittest.main()
