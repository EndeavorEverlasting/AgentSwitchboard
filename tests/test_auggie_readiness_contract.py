from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTRACT = ROOT / 'tooling' / 'gnhf' / 'auggie-readiness.contract.json'
PROBE = ROOT / 'tooling' / 'gnhf' / 'Test-AuggieReadiness.ps1'


def text(path: Path) -> str:
    return path.read_text(encoding='utf-8')


class AuggieReadinessContract(unittest.TestCase):
    def test_contract_links_existing_owned_surfaces(self) -> None:
        contract = json.loads(text(CONTRACT))
        self.assertEqual('agentswitchboard.auggie-readiness.v1', contract['contractId'])
        self.assertEqual('auggie --acp', contract['upstreamContract']['acpServerCommand'])
        self.assertEqual('--print', contract['upstreamContract']['nonInteractiveFlag'])
        for path in contract['entrypoints'].values():
            self.assertTrue((ROOT / path).is_file(), path)
        self.assertFalse(contract['artifact']['tracked'])
        self.assertFalse(contract['artifact']['rawHelpPersisted'])

    def test_probe_is_bounded_read_only_capability_detection(self) -> None:
        body = text(PROBE)
        for token in (
            'ProcessStartInfo',
            'UseShellExecute = $false',
            "ArgumentList @('--version')",
            "ArgumentList @('--help')",
            ".EndsWith('.cmd'",
            "@('/d', '/s', '/c', $FilePath)",
            'acpServerAdvertised',
            'nonInteractivePrintAdvertised',
            "'acp:auggie --acp'",
            'authenticationChecked = $false',
            'acpServerStarted = $false',
            'rawHelpPersisted = $false',
            'repositoryMutationAttempted = $false',
            'FailIfNotReady',
        ):
            self.assertIn(token, body, token)

        for forbidden in (
            'auggie login',
            'auggie token',
            '@augmentcode/auggie',
            'npm install',
            'winget install',
            'Start-Process',
        ):
            self.assertNotIn(forbidden, body, forbidden)

        self.assertNotIn("ArgumentList @('--acp')", body)
        self.assertNotIn('rawHelp =', body)

    def test_fixtures_preserve_ready_and_blocked_capabilities(self) -> None:
        ready = text(ROOT / 'tooling' / 'gnhf' / 'fixtures' / 'auggie-ready.fixture.ps1')
        blocked = text(ROOT / 'tooling' / 'gnhf' / 'fixtures' / 'auggie-no-acp.fixture.ps1')
        self.assertIn('--acp', ready)
        self.assertIn('--print', ready)
        self.assertNotIn('--acp', blocked)
        self.assertIn('--print', blocked)

    def test_docs_and_ci_preserve_the_proof_ceiling(self) -> None:
        docs = text(ROOT / 'docs' / 'workstation' / 'auggie-readiness.md')
        workflow = text(ROOT / '.github' / 'workflows' / 'auggie-readiness.yml')
        for token in (
            'authentication',
            'ACP handshake',
            'Test-AuggieReadiness.ps1',
            'auggie --acp',
        ):
            self.assertIn(token, docs, token)
        self.assertIn('tests.test_auggie_readiness_contract', workflow)
        self.assertIn('Test-GnhfFleetContracts.ps1', workflow)
        self.assertIn('git diff --check', workflow)
        self.assertIn('auggie-ready.fixture.ps1', workflow)
        self.assertIn('auggie-no-acp.fixture.ps1', workflow)


if __name__ == '__main__':
    unittest.main()
