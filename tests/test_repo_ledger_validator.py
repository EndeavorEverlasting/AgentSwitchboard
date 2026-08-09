from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_PATHS = (
    Path('.ai/README.md'),
    Path('.ai/WORK_QUEUE.md'),
    Path('.ai/repo-ledger-adoption.json'),
    Path('scripts/ai-harness/validate-repo-ledger.py'),
)


class RepoLedgerValidatorTests(unittest.TestCase):
    def run_fixture(self, mutator=None) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory(prefix='agentswitchboard-ledger-test-') as temp_dir:
            root = Path(temp_dir)
            for relative in FIXTURE_PATHS:
                source = ROOT / relative
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
            if mutator is not None:
                mutator(root)
            return subprocess.run(
                [sys.executable, str(root / 'scripts/ai-harness/validate-repo-ledger.py')],
                cwd=root,
                text=True,
                capture_output=True,
                check=False,
            )

    def test_current_queue_passes(self) -> None:
        result = self.run_fixture()
        self.assertEqual(result.returncode, 0, msg=f'{result.stdout}\n{result.stderr}')
        self.assertIn('[repo-ledger] PASS', result.stdout)

    def test_symbolic_contract_pin_fails_closed(self) -> None:
        def mutate(root: Path) -> None:
            manifest_path = root / '.ai/repo-ledger-adoption.json'
            manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
            manifest['contract']['commit'] = 'main'
            manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')

        result = self.run_fixture(mutate)
        self.assertNotEqual(result.returncode, 0)
        self.assertRegex(result.stdout + result.stderr, r'contract pin drifted|exact 40-hex')

    def test_done_without_durable_proof_fails(self) -> None:
        def mutate(root: Path) -> None:
            queue_path = root / '.ai/WORK_QUEUE.md'
            source = queue_path.read_text(encoding='utf-8')
            blocks = re.split(r'(?=^## ASQ-\d{3,} — )', source, flags=re.MULTILINE)
            done_index = next(
                (index for index, block in enumerate(blocks) if re.search(r'^- \*\*Status:\*\* DONE$', block, re.MULTILINE)),
                None,
            )
            self.assertIsNotNone(done_index, 'fixture must contain at least one DONE task')
            assert done_index is not None
            blocks[done_index] = re.sub(
                r'^- \*\*Last proof:\*\* .*$',
                '- **Last proof:** none',
                blocks[done_index],
                count=1,
                flags=re.MULTILINE,
            )
            queue_path.write_text(''.join(blocks), encoding='utf-8')

        result = self.run_fixture(mutate)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('DONE requires a durable proof token', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
