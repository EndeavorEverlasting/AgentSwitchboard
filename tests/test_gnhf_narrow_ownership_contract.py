"""
Test that GNHF maintains its NARROW ownership boundary per ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME.

This contract test ensures:
1. GNHF README explicitly states NARROW boundary
2. ADR reference is present
3. No crew orchestration claims exist in GNHF docs
"""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
README_PATH = ROOT / 'tooling' / 'gnhf' / 'README.md'
ADR_PATH = ROOT / 'docs' / 'architecture' / 'asb-firstmate-runtime-boundary.md'


class GnhfNarrowOwnershipContractTests(unittest.TestCase):
    """Validate GNHF NARROW ownership boundary encoding per ASQ-016."""

    @classmethod
    def setUpClass(cls):
        """Load required files once for all tests."""
        cls.readme_text = README_PATH.read_text(encoding='utf-8') if README_PATH.exists() else None
        cls.adr_text = ADR_PATH.read_text(encoding='utf-8') if ADR_PATH.exists() else None

    def test_required_files_exist(self):
        """Required documentation files must exist."""
        self.assertTrue(README_PATH.exists(), f"tooling/gnhf/README.md is missing")
        self.assertTrue(ADR_PATH.exists(), f"docs/architecture/asb-firstmate-runtime-boundary.md is missing")

    def test_readme_ownership_section_header(self):
        """README must contain explicit 'Ownership boundary' section."""
        self.assertIsNotNone(self.readme_text, "README text not loaded")
        self.assertRegex(
            self.readme_text,
            r'(?i)##\s*Ownership\s+boundary',
            "README must contain '## Ownership boundary' section"
        )

    def test_readme_narrow_keyword(self):
        """README must explicitly state 'NARROW boundary'."""
        self.assertIsNotNone(self.readme_text, "README text not loaded")
        self.assertRegex(
            self.readme_text,
            r'\bNARROW\s+boundary\b',
            "README must explicitly state 'NARROW boundary'"
        )

    def test_readme_windows_single_agent_identity(self):
        """README must state Windows-first bounded single-agent launcher identity."""
        self.assertIsNotNone(self.readme_text, "README text not loaded")
        self.assertRegex(
            self.readme_text,
            r'(?i)Windows-first\s+bounded\s+single-agent',
            "README must state 'Windows-first bounded single-agent' identity"
        )

    def test_readme_firstmate_canonical_reference(self):
        """README must reference FirstMate as canonical crew runtime."""
        self.assertIsNotNone(self.readme_text, "README text not loaded")
        self.assertRegex(
            self.readme_text,
            r'(?i)FirstMate.*canonical.*crew\s+runtime',
            "README must reference FirstMate as canonical crew runtime"
        )

    def test_readme_adr_citation(self):
        """README must cite ADR ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME."""
        self.assertIsNotNone(self.readme_text, "README text not loaded")
        self.assertIn(
            'ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME',
            self.readme_text,
            "README must cite ADR ASB-ADR-2026-09-FIRSTMATE-CREW-RUNTIME"
        )

    def test_readme_adr_path_reference(self):
        """README must reference ADR path."""
        self.assertIsNotNone(self.readme_text, "README text not loaded")
        self.assertIn(
            'docs/architecture/asb-firstmate-runtime-boundary.md',
            self.readme_text,
            "README must reference ADR path docs/architecture/asb-firstmate-runtime-boundary.md"
        )

    def test_readme_forbid_multi_crew_control_plane(self):
        """README must explicitly forbid expanding into multi-crew control plane."""
        self.assertIsNotNone(self.readme_text, "README text not loaded")
        # Allow for markdown formatting like **not**
        self.assertRegex(
            self.readme_text,
            r'(?i)must\s+\*?\*?not\*?\*?\s+expand.*multi-crew.*control\s+plane',
            "README must forbid expanding into multi-crew control plane"
        )

    def test_readme_competing_with_firstmate(self):
        """README must state boundary prevents competing with FirstMate."""
        self.assertIsNotNone(self.readme_text, "README text not loaded")
        self.assertRegex(
            self.readme_text,
            r'(?i)competing\s+with\s+FirstMate',
            "README must state boundary prevents competing with FirstMate"
        )

    def test_readme_no_crew_orchestration_claims(self):
        """README must not claim GNHF is a crew orchestration platform."""
        self.assertIsNotNone(self.readme_text, "README text not loaded")

        # Negative assertion: should not contain patterns CLAIMING crew orchestration capability
        # Exclude the ownership section's forbidding language by requiring positive claim verbs
        crew_claim_pattern = r'(?i)GNHF\s+(?:is|provides|enables|supports|implements).*(?:crew|multi-agent)\s+(?:orchestration|supervision|control\s+plane)'
        match = re.search(crew_claim_pattern, self.readme_text)

        self.assertIsNone(
            match,
            f"README must not claim GNHF is a crew orchestration platform. Found: {match.group(0) if match else 'N/A'}"
        )

    def test_adr_firstmate_canonical(self):
        """ADR must establish FirstMate as canonical crew runtime."""
        self.assertIsNotNone(self.adr_text, "ADR text not loaded")
        self.assertRegex(
            self.adr_text,
            r'FirstMate.*canonical live crew runtime',
            "ADR must establish FirstMate as canonical crew runtime"
        )

    def test_adr_gnhf_narrow_disposition(self):
        """ADR must contain GNHF NARROW disposition."""
        self.assertIsNotNone(self.adr_text, "ADR text not loaded")
        self.assertRegex(
            self.adr_text,
            r'(?i)tooling/gnhf.*NARROW',
            "ADR must contain GNHF NARROW disposition"
        )

    def test_adr_gnhf_identity(self):
        """ADR must define GNHF as Windows-first bounded single-agent launcher."""
        self.assertIsNotNone(self.adr_text, "ADR text not loaded")
        self.assertRegex(
            self.adr_text,
            r'(?i)Windows-first\s+bounded\s+single-agent',
            "ADR must define GNHF as Windows-first bounded single-agent launcher"
        )


if __name__ == '__main__':
    unittest.main()
