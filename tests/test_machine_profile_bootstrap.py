import hashlib
import json
import os
import re
import subprocess
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DETECTOR = os.path.join(ROOT, 'tooling', 'profiles', 'windows', 'Get-AgentSwitchboardMachineProfile.ps1')
HARNESS_ROOT = os.path.join(ROOT, 'tooling', 'profiles', 'windows', 'harness', 'machine-profile')
REGISTRY = os.path.join(HARNESS_ROOT, 'machine-profile.registry.json')
CODEBASE_MAP = os.path.join(HARNESS_ROOT, 'codebase-map.json')
SCHEMA = os.path.join(HARNESS_ROOT, 'schemas', 'machine-profile.schema.json')
SKILL = os.path.join(ROOT, '.ai', 'skills', 'machine-profile-bootstrap', 'SKILL.md')
BOOTSTRAP = os.path.join(ROOT, 'AgentSwitchboard-Technician-Bootstrap.cmd')
DIRECTORY_BOOTSTRAP = os.path.join(ROOT, 'Bootstrap-AgentSwitchboard-In-Directory.cmd')
PULL = os.path.join(ROOT, 'Pull-And-Run-AgentSwitchboard.cmd')


def text(path):
    with open(path, encoding='utf-8') as handle:
        return handle.read()


class MachineProfileBootstrapContract(unittest.TestCase):
    def test_registry_schema_map_skill_and_fixtures(self):
        registry = json.loads(text(REGISTRY))
        schema = json.loads(text(SCHEMA))
        codebase_map = json.loads(text(CODEBASE_MAP))
        skill = text(SKILL)
        self.assertEqual('agentswitchboard.machine-profile-registry.v1', registry['schema'])
        self.assertEqual('agentswitchboard.machine-profile-codebase-map.v1', codebase_map['schema'])
        self.assertEqual('agentswitchboard.machine-profile.v1', schema['properties']['schema']['const'])
        ids = [item['profileId'] for item in registry['profiles']]
        self.assertEqual([
            'enterprise-managed-onedrive',
            'enterprise-managed-local',
            'work-or-school-onedrive',
            'personal-onedrive',
            'local-windows',
        ], ids)
        for token in [
            'Get-AgentSwitchboardMachineProfile.ps1',
            'Do not guess',
            'machine-profile.json',
            'AGENT_SWITCHBOARD_REPO',
            'proof ceiling',
        ]:
            self.assertIn(token, skill)
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
            "AllowEmptyCollection",
            "environmentOverride",
            "AGENT_SWITCHBOARD_REPO selected the repository root before checkout discovery",
            "if (-not $git) { return $false }",
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
            'PROFILE_REF=',
            'PROFILE_URL=',
            'Machine profile:',
            'profile recommendation',
            'machine-profile.json',
            'Windows PowerShell',
            'commit-pinned machine-profile detector',
        ]:
            self.assertIn(token, bootstrap)
        match = re.search(r'PROFILE_REF=([a-f0-9]{40})', bootstrap, flags=re.IGNORECASE)
        self.assertIsNotNone(match)
        profile_ref = match.group(1).lower()
        self.assertIn('/%PROFILE_REF%/tooling/profiles/windows/%PROFILE_NAME%', bootstrap)
        self.assertNotIn('EXPECTED_PROFILE_SHA256=', bootstrap)
        pinned_detector = subprocess.check_output(
            ['git', 'show', f'{profile_ref}:tooling/profiles/windows/Get-AgentSwitchboardMachineProfile.ps1'],
            cwd=ROOT,
        )
        tracked_detector = subprocess.check_output(
            ['git', 'show', 'HEAD:tooling/profiles/windows/Get-AgentSwitchboardMachineProfile.ps1'],
            cwd=ROOT,
        )
        self.assertEqual(tracked_detector, pinned_detector)

    def test_directory_bootstrap_is_generic_explicit_and_immutable(self):
        wrapper = text(DIRECTORY_BOOTSTRAP)
        for token in [
            'WORKSPACE_ROOT=%~1',
            'REPO_LEAF=%~2',
            'AgentSwitchBoard-Live',
            'AgentSwitchboard-Technician-Bootstrap.cmd',
            'call "%BOOTSTRAP_PATH%" "%REPO_ROOT%" main',
            'EXPECTED_BOOTSTRAP_BLOB=',
            'No downloaded bootstrap was executed.',
            '/%BOOTSTRAP_REF%/AgentSwitchboard-Technician-Bootstrap.cmd',
        ]:
            self.assertIn(token, wrapper)
        self.assertNotIn('CheeksMcClappeth', wrapper)
        self.assertNotIn('OneDrive', wrapper)
        self.assertNotIn('/main/AgentSwitchboard-Technician-Bootstrap.cmd', wrapper)
        self.assertIn('Usage: %~nx0 "C:\\path\\to\\Dev"', wrapper)

        ref_match = re.search(r'BOOTSTRAP_REF=([a-f0-9]{40})', wrapper, flags=re.IGNORECASE)
        blob_match = re.search(r'EXPECTED_BOOTSTRAP_BLOB=([a-f0-9]{40})', wrapper, flags=re.IGNORECASE)
        self.assertIsNotNone(ref_match)
        self.assertIsNotNone(blob_match)
        pinned = subprocess.check_output(
            ['git', 'show', f'{ref_match.group(1)}:AgentSwitchboard-Technician-Bootstrap.cmd'],
            cwd=ROOT,
        )
        git_blob = hashlib.sha1(
            b'blob ' + str(len(pinned)).encode('ascii') + b'\0' + pinned,
            usedforsecurity=False,
        ).hexdigest()
        self.assertEqual(blob_match.group(1).lower(), git_blob)

    def test_acquire_mode_does_not_require_pwsh(self):
        pull = text(PULL)
        acquire_gate = pull.index('if /I not "%MODE%"=="acquire" goto :require_pwsh')
        pwsh_gate = pull.index(':require_pwsh')
        clone = pull.index(':clone_repo')
        self.assertLess(acquire_gate, pwsh_gate)
        self.assertLess(pwsh_gate, clone)
        self.assertIn('Repository acquisition completed without requiring PowerShell 7', pull)
        self.assertIn('Workstation setup is intentionally deferred.', pull)


if __name__ == '__main__':
    unittest.main()
