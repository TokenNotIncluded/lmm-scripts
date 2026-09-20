"""Regression tests for the documented installation policies (no network)."""
import unittest
from pathlib import Path
import test_installers as fixtures

P = Path(__file__).resolve().parents[1]

class OfficialPolicyTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.InstallerTests()
        self.fixture.setUp()

    def tearDown(self):
        self.fixture.tearDown()

    def client_install(self, target):
        return next(args for command, args in self.fixture.calls()
                    if command == 'npm' and any(f'/{target}' in arg for arg in args)
                    and 'install' in args)

    def test_pi_disables_lifecycle_scripts(self):
        result = self.fixture.run_script('pi')
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.client_install('pi-coding-agent')
        self.assertIn('--ignore-scripts', args)
        self.assertFalse(any(a.startswith('--allow-scripts') for a in args))

    def test_pi_accepts_existing_ignore_scripts_policy(self):
        result = self.fixture.run_script('pi', env={'npm_config_ignore_scripts': 'true'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('--ignore-scripts', self.client_install('pi-coding-agent'))

    def test_dsh_does_not_silently_override_build_policy(self):
        result = self.fixture.run_script('dsh', env={'npm_config_ignore_scripts': 'true'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('DSH needs native build scripts', result.stderr)
        self.assertFalse((self.fixture.root / 'bin/dsh').exists())

    def test_dsh_keeps_native_build_allowlist(self):
        result = self.fixture.run_script('dsh', fixture=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.client_install('dsh')
        self.assertNotIn('--ignore-scripts', args)
        self.assertTrue(any(a.startswith('--allow-scripts=@deepseek-ai/dsh-subprocess-local,') for a in args))

    def test_termux_never_downloads_desktop_node(self):
        result = self.fixture.run_script('pi', env={'TERMUX_VERSION': 'test', 'LMM_TEST_NODE_OK': '0'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('pkg install nodejs', result.stderr)
        self.assertFalse(any(name == 'curl' for name, _ in self.fixture.calls()))

    def test_termux_reuses_compatible_native_node(self):
        result = self.fixture.run_script('pi', env={'TERMUX_VERSION': 'test'})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(name == 'curl' for name, _ in self.fixture.calls()))

    def test_termux_rejects_desktop_lmm_binary(self):
        result = self.fixture.run_script('lmm', env={'TERMUX_VERSION': 'test'})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('No Android LMM CLI binary', result.stderr)
        self.assertFalse(any(name == 'curl' for name, _ in self.fixture.calls()))

if __name__ == '__main__':
    unittest.main(verbosity=2)
