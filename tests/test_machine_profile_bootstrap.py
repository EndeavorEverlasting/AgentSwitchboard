import json
import os
import re
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DETECTOR = os.path.join(ROOT, 'tooling', 'profiles', 'windows', 'Get-AgentSwitchboardMachineProfile.ps1')
REGISTRY = os.path.join(ROOT, 'tooling', 'profiles', 'windows', 'harness', 'machine-profile', 'machine-profile.registry.json')
SCHEMA = os.path.join(ROOT, 'tooling', 'profiles', 'windows', 'harness', 'machine-profile', 'schemas', 'machine-profile.schema.json')
BOOTSTRAP = os.path.join(ROOT, 'AgentSwitchboard-Technician-Bootstrap.cmd')
PULL = os.path.join(ROOT, 'Pull-And-Run-AgentSwitchboard.cmd')


def text(path):
    with open(path, encoding='utf-8') as handle:
        return handle.read()


class MachineProfileBootstrapContract(unittest.TestCase):
    def test_registry_schema_and_fixtures(self):
        registry = json.loads(text(REGISTRY))
        schema = json.loads(text(SCHEMA))
        self.assertEqual('agentswitchboard.machine-profile-registry.v1', registry['schema'])
        self.assertEqual('agentswitchboard.machine-profile.v1', schema['properties']['schema']['const'])
        ids = [item['profileId'] for item in registry['profiles']]
        self.assertEqual([
            'enterprise-managed-onedrive',
            'enterprise-managed-local',
            'work-or-school-onedrive',
            'personal-onedrive',
            'local-windows',
        ], ids)
        fixture_root = os.path.join(os.path.dirname(REGISTRY), 'fixtures')
        for name in ['enterprise-onedrive.fixture.json', 'local-windows.fixture.json']:
            payload = json.loads(text(os.path.join(fixture_root, name)))
            self.assertIn('username', payload)
            self.assertIn('userProfile', payload)
            self.assertIn('tools', payload)

    def test_detector_is_windows_powershell_compatible_and_local_only(self):
        detector = text(DETECTOR)
        for token in [
            "agentswitchboard.machine-profile.v1",
            "OneDriveCommercial",
            "OneDriveConsumer",
            "dsregcmd.exe",
            "User Shell Folders",
            "repo-path.txt",
            "recommendedRoot",
            "selectionPolicy",
            "machine-profile.env.cmd",
            "machine-profile.env.ps1",
            "ProbeFile",
        ]:
            self.assertIn(token, detector)
        self.assertNotIn('ConvertFrom-Json -AsHashtable', detector)
        self.assertNotIn('SetEnvironmentVariable(', detector)
        self.assertIn("Join-Path $env:LOCALAPPDATA 'AgentSwitchboard\\machine-profile'", detector)
        self.assertIn("Join-Path ([string]$facts.userProfile) 'dev\\AgentSwitchBoard-Live'", detector)

    def test_bootstrap_profiles_before_acquisition_and_pwsh_after(self):
        bootstrap = text(BOOTSTRAP)
        profile_call = bootstrap.index('Get-AgentSwitchboardMachineProfile.ps1')
        parent_call = bootstrap.index('call "%PARENT_TEMP%"')
        pwsh_gate = bootstrap.index('where pwsh.exe')
        self.assertLess(profile_call, parent_call)
        self.assertLess(parent_call, pwsh_gate)
        for token in [
            'EXPECTED_PROFILE_SHA256=',
            'PROFILE_URL=',
            'Machine profile:',
            'profile recommendation',
            'machine-profile.json',
            'Windows PowerShell',
        ]:
            self.assertIn(token, bootstrap)
        self.assertRegex(bootstrap, r'EXPECTED_PROFILE_SHA256=[a-f0-9]{64}')

    def test_acquire_mode_does_not_require_pwsh(self):
        pull = text(PULL)
        acquire_gate = pull.index('if /I not "%MODE%"=="acquire" goto :require_pwsh')
        pwsh_gate = pull.index(':require_pwsh')
        clone = pull.index(':clone_repo')
        self.assertLess(acquire_gate, pwsh_gate)
        self.assertLess(pwsh_gate, clone)
        self.assertIn('Repository acquisition completed without requiring PowerShell 7', pull)


if __name__ == '__main__':
    unittest.main()
