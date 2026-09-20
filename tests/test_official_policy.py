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


class TermuxAndCompositionTests(unittest.TestCase):
    def setUp(self):
        self.fixture = fixtures.InstallerTests()
        self.fixture.setUp()
        self.prefix = self.fixture.base / 'termux prefix'
        (self.prefix / 'tmp').mkdir(parents=True)
        self.env = {'TERMUX_VERSION': 'test', 'PREFIX': str(self.prefix), 'TMPDIR': ''}

    def tearDown(self):
        self.fixture.tearDown()

    def test_termux_32_bit_native_node_is_supported(self):
        for arch in ('armv7l', 'i686'):
            with self.subTest(arch=arch):
                r = self.fixture.run_script('pi', env=self.env | {'LMM_TEST_ARCH': arch})
                self.assertEqual(r.returncode, 0, r.stderr)
        self.assertFalse(any(name == 'curl' for name, _ in self.fixture.calls()))

    def test_desktop_32_bit_is_not_misidentified_as_termux(self):
        r = self.fixture.run_script('pi', env={'TERMUX_VERSION': '', 'TERMUX_APP__PACKAGE_NAME': '', 'PREFIX': '', 'LMM_TEST_ARCH': 'armv7l'})
        self.assertNotEqual(r.returncode, 0)
        self.assertFalse(self.fixture.root.exists())

    def test_termux_requires_native_android_node(self):
        r = self.fixture.run_script('pi', env=self.env | {'LMM_TEST_NODE_PLATFORM': 'linux'})
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('native Node/npm', r.stderr)
        self.assertFalse(self.fixture.root.exists())
        self.assertFalse(any(name == 'curl' for name, _ in self.fixture.calls()))

    def test_prefix_alone_identifies_termux(self):
        env = self.env | {'TERMUX_VERSION': '', 'TERMUX_APP__PACKAGE_NAME': '', 'PREFIX': str(self.fixture.base / 'com.termux/files/usr'), 'LMM_TEST_NODE_OK': '0'}
        r = self.fixture.run_script('pi', env=env)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('In Termux', r.stderr)
        self.assertFalse(self.fixture.root.exists())

    def test_termux_check_is_read_only(self):
        r = self.fixture.run_script('pi', '--check', env=self.env)
        self.assertIn(r.returncode, (0, 1))
        self.assertFalse(self.fixture.root.exists())
        self.assertFalse(any(name in ('curl', 'npm') and 'install' in args for name, args in self.fixture.calls()))

    def test_shared_storage_is_rejected_before_installation(self):
        for path in ('/sdcard/lmm-tools', '/storage/emulated/0/lmm-tools', '/mnt/media_rw/card/lmm-tools'):
            with self.subTest(path=path):
                r = self.fixture.run_script('pi', '--root', path, env=self.env)
                self.assertNotEqual(r.returncode, 0)
                self.assertIn('shared storage', r.stderr)
        self.assertFalse(any(name == 'curl' for name, _ in self.fixture.calls()))

    def test_shared_storage_symlink_ancestor_is_rejected(self):
        alias = self.fixture.base / 'shared alias'
        alias.symlink_to('/storage/emulated/0', target_is_directory=True)
        r = self.fixture.run_script('pi', '--root', str(alias / 'tools'), env=self.env)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('shared storage', r.stderr)

    def test_shared_cache_and_temp_are_rejected(self):
        for key in ('LMM_CACHE_ROOT', 'TMPDIR'):
            with self.subTest(key=key):
                r = self.fixture.run_script('pi', env=self.env | {key: '/sdcard/lmm-cache'})
                self.assertNotEqual(r.returncode, 0)
                self.assertIn('shared storage', r.stderr)
        self.assertFalse((self.fixture.root / 'bin/pi').exists())

    def test_launcher_uses_absolute_bash_and_explicit_node(self):
        r = self.fixture.run_script('pi', env=self.env)
        self.assertEqual(r.returncode, 0, r.stderr)
        body = (self.fixture.root / 'bin/pi').read_text()
        self.assertNotIn('/usr/bin/env', body)
        self.assertIn('/node', body)
        self.assertTrue(body.startswith('#!/'))
        version = fixtures.subprocess.run([str(self.fixture.root / 'bin/pi'), '--version'], env=self.fixture.env | self.env, capture_output=True, text=True)
        self.assertEqual(version.returncode, 0, version.stderr)

    def test_menu_temp_fallback_uses_prefix_not_desktop_tmp(self):
        source = (P / 'templates/lib/termux.sh').read_text(encoding='utf-8')
        r = fixtures.subprocess.run(['bash', '-c', source + '\nlmm_temp_root'], env=self.fixture.env | self.env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.strip(), str(self.prefix / 'tmp'))
        explicit = str(self.fixture.base / 'explicit temp')
        r = fixtures.subprocess.run(['bash', '-c', source + '\nlmm_temp_root'], env=self.fixture.env | self.env | {'TMPDIR': explicit}, capture_output=True, text=True)
        self.assertEqual(r.stdout.strip(), explicit)

    def test_termux_does_not_reuse_cached_linux_lmm(self):
        v = fixtures.json.loads((P / 'versions.json').read_text())
        app = self.fixture.root / 'apps/lmm' / (v['lmm_version'] + '-linux-x64')
        app.mkdir(parents=True)
        (app / '.lmm-managed').write_text(v['lmm_version'])
        binary = app / 'lmm'
        binary.write_text('#!/bin/sh\nexit 0\n')
        binary.chmod(0o755)
        r = self.fixture.run_script('lmm', env=self.env)
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('No Android LMM CLI binary', r.stderr)
        self.assertFalse((self.fixture.root / 'bin/lmm').exists())

    def test_relative_install_root_works(self):
        relative = fixtures.os.path.relpath(self.fixture.root)
        r = self.fixture.run_script('pi', '--root', relative)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue((self.fixture.root / 'bin/pi').exists())

    def test_generated_scripts_omit_other_target_implementations(self):
        for ext, pnpm, lmm, node in [('sh', 'ensure_pnpm()', 'install_lmm()', 'ensure_node()'), ('ps1', 'function Install-Pnpm', 'function Install-Lmm', 'function Install-Node')]:
            pi = (P / f'pi.{ext}').read_text()
            dsh = (P / f'dsh.{ext}').read_text()
            cli = (P / f'lmm.{ext}').read_text()
            self.assertNotIn(pnpm, pi)
            self.assertNotIn(lmm, pi)
            self.assertNotIn(lmm, dsh)
            self.assertNotIn(pnpm, cli)
            self.assertNotIn(node, cli)
            self.assertNotIn('DSH_PROVIDER_SHA256=', pi)

    def test_shared_helpers_are_loaded_not_copied(self):
        for target in ('pi', 'dsh', 'lmm'):
            body = (P / f'{target}.sh').read_text(encoding='utf-8')
            for definition in ('lmm_is_termux() {', 'sha256() {', 'lmm_root() {', 'download() {'):
                self.assertNotIn(definition, body)
            self.assertIn('lmm_source_lib "$library"', body)
            self.assertNotIn('@@LIBRARIES@@', body)
        menu = (P / 'menu.sh').read_text(encoding='utf-8')
        self.assertEqual(menu.count('lmm_is_termux() {'), 1)
        fixtures.subprocess.run(['python3', str(P / 'tools/generate_menus.py'), '--check'], check=True)

    def test_every_generated_shell_help_is_standalone(self):
        for target in ('pi', 'dsh', 'lmm', 'lmm-use', 'menu'):
            body = (P / f'{target}.sh').read_text(encoding='utf-8')
            r = fixtures.subprocess.run(['bash', '-s', '--', '--help'], input=body, env=self.fixture.env | self.env, text=True, capture_output=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            partial = body.rsplit('if true; then', 1)[0]
            r = fixtures.subprocess.run(['bash', '-s'], input=partial, env=self.fixture.env | self.env, text=True, capture_output=True)
            self.assertFalse(self.fixture.root.exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
