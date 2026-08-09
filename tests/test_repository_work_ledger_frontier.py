import json
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
FRONTIER = ROOT / 'scripts' / 'Get-RepositoryWorkLedgerFrontier.ps1'


def task(task_id, title, *, status='READY', priority='P1', work_class='BOUNDED', next_action='create the bounded artifact'):
    fields = {
        'Status': status,
        'Priority': priority,
        'Work class': work_class,
        'Owner': 'unclaimed',
        'Branch / PR': 'none',
        'Scope': f'{title} scope',
        'Forbidden': 'unrelated mutation',
        'Dependencies': 'none',
        'References': '`AGENTS.md`',
        'Acceptance gate': f'{title} acceptance proof',
        'Gate': 'external dependency' if status in ('BLOCKED', 'OPERATOR') else 'none',
        'Last proof': 'none',
        'Next action': next_action,
        'Updated': '2026-08-09',
    }
    body = '\n'.join(f'- **{key}:** {value}' for key, value in fields.items())
    return f'## {task_id} — {title}\n\n{body}\n'


def run_frontier(content, *args):
    with tempfile.NamedTemporaryFile('w', suffix='.md', delete=False, dir=ROOT, encoding='utf-8') as handle:
        handle.write('# Test ledger\n\n' + content)
        relative = pathlib.Path(handle.name).relative_to(ROOT)
    try:
        return subprocess.run(
            ['pwsh', '-NoLogo', '-NoProfile', '-File', str(FRONTIER), '-LedgerPath', str(relative), *args],
            cwd=ROOT,
            text=True,
            capture_output=True,
        )
    finally:
        pathlib.Path(handle.name).unlink(missing_ok=True)


class RepositoryWorkLedgerFrontierTests(unittest.TestCase):
    def test_frontier_selects_highest_priority_actionable_task(self):
        content = ''.join([
            task('ASQ-901', 'bounded lower priority', priority='P1'),
            task('ASQ-902', 'unbounded urgent', priority='P0', work_class='UNBOUNDED', next_action='decompose this parent into bounded child ASQ items'),
            task('ASQ-903', 'blocked urgent', status='BLOCKED', priority='P0'),
        ])
        result = run_frontier(content, '-Json')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload['status'], 'ready')
        self.assertEqual(payload['actionableCount'], 2)
        self.assertEqual(payload['selected']['id'], 'ASQ-902')
        self.assertEqual(payload['selected']['route'], 'DECOMPOSE')

    def test_frontier_routes_bounded_work_to_execute(self):
        result = run_frontier(task('ASQ-901', 'bounded task'), '-Json')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload['selected']['route'], 'EXECUTE')
        self.assertEqual(payload['selected']['workClass'], 'BOUNDED')

    def test_frontier_all_is_priority_then_id_order(self):
        content = ''.join([
            task('ASQ-905', 'p2', priority='P2'),
            task('ASQ-904', 'p0 later id', priority='P0'),
            task('ASQ-902', 'p0 earlier id', priority='P0'),
        ])
        result = run_frontier(content, '-Json', '-All')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual([item['id'] for item in payload['items']], ['ASQ-902', 'ASQ-904', 'ASQ-905'])

    def test_frontier_excludes_terminal_operator_and_blocked(self):
        content = ''.join([
            task('ASQ-901', 'blocked', status='BLOCKED', priority='P0'),
            task('ASQ-902', 'operator', status='OPERATOR', priority='P0'),
            task('ASQ-903', 'done', status='DONE', priority='P0', next_action='none; no safe actionable work remains'),
        ])
        result = run_frontier(content, '-Json')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload['status'], 'empty')
        self.assertEqual(payload['actionableCount'], 0)
        self.assertIsNone(payload['selected'])

    def test_frontier_fails_closed_when_work_class_missing(self):
        content = task('ASQ-901', 'missing class').replace('- **Work class:** BOUNDED\n', '')
        result = run_frontier(content, '-Json')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing required frontier field 'Work class'", result.stderr)


if __name__ == '__main__':
    unittest.main()
