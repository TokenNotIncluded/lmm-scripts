"""Network-loader regressions; all HTTP is replaced with deterministic fixtures."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

P = Path(__file__).resolve().parents[1]
FAKE_CURL = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
with open(os.environ['LMM_LOADER_LOG'], 'a') as log:
    log.write(json.dumps(sys.argv[1:]) + '\n')
mode = os.environ.get('LMM_LOADER_MODE', 'ok')
if mode == 'empty':
    print('  ')
    sys.exit(0)
if mode == 'fail' or (mode == 'retry' and not Path(os.environ['LMM_LOADER_RETRIED']).exists()):
    Path(os.environ['LMM_LOADER_RETRIED']).touch()
    print('touch "$LMM_LOADER_MARKER"')
    sys.exit(18)
name = sys.argv[-1].rsplit('/', 1)[-1]
sys.stdout.write((Path(os.environ['LMM_LOADER_FIXTURES']) / name).read_text())
'''

class LoaderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.bin = self.base / 'bin'
        self.bin.mkdir()
        curl = self.bin / 'curl'
        curl.write_text(FAKE_CURL)
        curl.chmod(0o755)
        self.libs = self.base / "local libraries with ' spaces"
        self.libs.mkdir()
        (self.libs / 'one.sh').write_text('lmm_loaded=42\nlmm_test() { printf "%s\\n" "$lmm_loaded"; }\n')
        (self.libs / 'two.sh').write_text('lmm_loaded=43\n')
        self.log = self.base / 'requests.jsonl'
        self.log.write_text('')
        self.marker = self.base / 'partial-executed'
        self.revision = json.loads((P / 'versions.json').read_text())['library_revision']
        self.loader = (P / 'templates/load.sh.in').read_text()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                        LMM_LIB_DIR='', LMM_LOADER_LOG=str(self.log), LMM_LOADER_FIXTURES=str(self.libs),
                        LMM_LOADER_MARKER=str(self.marker), LMM_LOADER_RETRIED=str(self.base / 'retried'))

    def tearDown(self):
        self.tmp.cleanup()

    def run_loader(self, commands, **env):
        code = 'set -euo pipefail\nLIB_REVISION=' + self.revision + '\n' + self.loader + '\n' + commands
        return subprocess.run(['bash', '-s'], input=code, env=self.env | env, text=True, capture_output=True, timeout=10)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_remote_import_keeps_functions_and_variables(self):
        result = self.run_loader('lmm_source_lib one.sh\nlmm_test')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '42\n')
        url = self.calls()[0][-1]
        self.assertEqual(url, f'https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/{self.revision}/templates/lib/one.sh')
        self.assertIn('--max-time', self.calls()[0])
        self.assertIn('--connect-timeout', self.calls()[0])

    def test_multiple_imports_share_scope(self):
        result = self.run_loader('lmm_source_lib one.sh\nlmm_source_lib two.sh\nlmm_test')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '43\n')

    def test_failed_transfer_never_executes_partial_text(self):
        result = self.run_loader('lmm_source_lib one.sh\nprintf continued', LMM_LOADER_MODE='fail')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.marker.exists())
        self.assertNotIn('continued', result.stdout)
        self.assertIn('Cannot load library one.sh', result.stderr)
        self.assertEqual(len(self.calls()), 3)

    def test_retry_discards_previous_response(self):
        result = self.run_loader('lmm_source_lib one.sh\nlmm_test', LMM_LOADER_MODE='retry')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '42\n')
        self.assertFalse(self.marker.exists())
        self.assertEqual(len(self.calls()), 2)

    def test_empty_response_is_not_success(self):
        result = self.run_loader('lmm_source_lib one.sh\nprintf continued', LMM_LOADER_MODE='empty')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('continued', result.stdout)

    def test_local_directory_with_spaces_never_fetches(self):
        result = self.run_loader('lmm_source_lib one.sh\nlmm_test', LMM_LIB_DIR=str(self.libs))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '42\n')
        self.assertEqual(self.calls(), [])

    def test_missing_local_module_does_not_silently_fetch(self):
        result = self.run_loader('lmm_source_lib missing.sh', LMM_LIB_DIR=str(self.libs))
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_local_source_error_stops_caller(self):
        (self.libs / 'bad.sh').write_text('return 9\n')
        result = self.run_loader('lmm_source_lib bad.sh\nprintf continued', LMM_LIB_DIR=str(self.libs))
        self.assertEqual(result.returncode, 9)
        self.assertNotIn('continued', result.stdout)

    def test_help_and_invalid_options_do_not_fetch(self):
        for target in ('pi', 'dsh', 'lmm'):
            for args, code in [(['--help'], 0), (['--not-an-option'], 1)]:
                with self.subTest(target=target, args=args):
                    result = subprocess.run(['bash', str(P / f'{target}.sh'), *args], env=self.env,
                                            text=True, capture_output=True, timeout=10)
                    self.assertEqual(result.returncode, code, result.stderr)
        self.assertEqual(self.calls(), [])

    def test_library_failure_preserves_existing_launcher(self):
        root = self.base / 'installed'
        (root / 'bin').mkdir(parents=True)
        for target in ('pi', 'dsh', 'lmm'):
            launcher = root / 'bin' / target
            launcher.write_text('old launcher')
            result = subprocess.run(['bash', str(P / f'{target}.sh'), '--root', str(root)],
                                    env=self.env | {'LMM_LOADER_MODE': 'fail'}, text=True, capture_output=True, timeout=10)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(launcher.read_text(), 'old launcher')
            self.assertFalse((root / '.setup-lock').exists())
            self.assertFalse((root / 'cache').exists())

    def test_termux_remote_path_uses_same_importer(self):
        import test_installers as fixtures
        fixture = fixtures.InstallerTests()
        fixture.setUp()
        try:
            (fixture.bin / 'curl').write_text(FAKE_CURL)
            env = self.env | {'TERMUX_VERSION': 'test', 'PREFIX': str(self.base / 'termux'),
                              'LMM_LOADER_FIXTURES': str(P / 'templates/lib'), 'TMPDIR': ''}
            env.pop('PATH')
            result = fixture.run_script('pi', env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertGreaterEqual(len(self.calls()), 4)
            self.assertNotIn('/usr/bin/env', (fixture.root / 'bin/pi').read_text())
        finally:
            fixture.tearDown()

    def test_pinned_modules_match_checked_out_sources(self):
        self.assertRegex(self.revision, r'^[0-9a-f]{40}$')
        for path in sorted((P / 'templates/lib').glob('*')):
            if path.is_file():
                data = subprocess.check_output(['git', 'show', f'{self.revision}:{path.relative_to(P).as_posix()}'], cwd=P)
                self.assertEqual(data, path.read_bytes(), f'Update library_revision after changing {path.name}')

    def test_published_installers_are_small_and_do_not_embed_shared_code(self):
        for target in ('pi', 'dsh', 'lmm'):
            sh = (P / f'{target}.sh').read_text()
            ps = (P / f'{target}.ps1').read_text()
            self.assertNotIn('download() {', sh)
            self.assertNotIn('lmm_is_termux() {', sh)
            self.assertNotIn('function Invoke-Bounded', ps)
            self.assertNotIn('function Receive-Stream', ps)
            self.assertIn("source <(printf '%s\\n'", sh)
            self.assertIn('Get-LmmLibrary $library', ps)
            self.assertLess(len(sh.encode()), 18000)
            self.assertLess(len(ps.encode()), 20000)
        self.assertNotIn('sha256', self.loader.lower())
        self.assertNotIn('Get-FileHash', (P / 'templates/load.ps1.in').read_text())

if __name__ == '__main__':
    unittest.main(verbosity=2)
