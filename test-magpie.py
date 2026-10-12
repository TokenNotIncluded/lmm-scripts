"""Offline Magpie and menu checks. No software is installed and no network is used."""
import errno
import json
import os
from pathlib import Path
import pty
import re
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent
ORIGINAL = 'pi dsh lmm codex claude-code cc-switch clash-verge-rev codewhale opencode cursor-cli grok-build gemini qwen-code kimi codebuddy hermes openclaw astrbot aider cursor cherry-studio ollama uv'.split()
TERMUX = 'pi dsh lmm codex claude-code codewhale'.split()
CURL = r'''import json, os, sys
from pathlib import Path
args = sys.argv[1:]
url = next(arg for arg in args if arg.startswith('https://'))
with open(os.environ['LOG'], 'a') as log: log.write(json.dumps(url)+'\n')
if os.environ.get('FAIL_DOWNLOAD'):
    print('touch "$HOME/partial-executed"')
    sys.exit(18)
if 'raw.githubusercontent.com' in url:
    print(Path(os.environ['ROOT'], 'magpie.sh').read_text())
else:
    assert url == 'https://usemagpie.ai/install.sh'
    print('printf "%s\\n" "$@" > "$HOME/upstream-args"')
    print('printf "%s\\n" "${MAGPIE_CLI:-}" "${MAGPIE_BIN_DIR:-}" "${TERMUX_VERSION:-}" "${PREFIX:-}" > "$HOME/upstream-env"')
    print('exit '+os.environ.get('INSTALL_EXIT','0'))
'''


class MagpieTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        for name in ('bash', 'sh', 'dirname'):
            os.symlink(shutil.which(name), self.bin / name)
        curl = self.bin / 'curl'
        curl.write_text('#!' + sys.executable + '\n' + CURL)
        curl.chmod(0o755)
        self.log = self.home / 'calls'
        self.log.touch()
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin), LOG=str(self.log), ROOT=str(ROOT))
        for name in ('TERMUX_VERSION', 'PREFIX', 'MAGPIE_CLI', 'MAGPIE_BIN_DIR', 'LMM_SCRIPTS_REV', 'FAIL_DOWNLOAD', 'INSTALL_EXIT'):
            self.env.pop(name, None)

    def tearDown(self):
        self.tmp.cleanup()

    def run_script(self, *args, **env):
        return subprocess.run([shutil.which('bash'), str(ROOT / 'magpie.sh'), *args],
                              env=self.env | env, capture_output=True, text=True, timeout=10)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_install_update_and_exact_argument_forwarding(self):
        for action in ((), ('install',), ('update',)):
            result = self.run_script(*action)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((self.home / 'upstream-args').read_text().strip(), '')
        args = ('--proxy', 'http://localhost:7890', '--mirror', 'https://example.invalid/a b/')
        result = self.run_script('install', *args)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / 'upstream-args').read_text().splitlines(), list(args))

    def test_partial_download_is_not_executed(self):
        self.assertEqual(self.run_script(FAIL_DOWNLOAD='1').returncode, 18)
        self.assertFalse((self.home / 'partial-executed').exists())
        self.assertFalse((self.home / 'upstream-args').exists())

    def test_upstream_failure_and_cancellation_propagate(self):
        for code in (9, 130):
            self.assertEqual(self.run_script(INSTALL_EXIT=str(code)).returncode, code)

    def test_termux_and_custom_install_environment_are_preserved(self):
        values = ('1', str(self.home / 'custom bin'), 'test', '/data/data/com.termux/files/usr')
        result = self.run_script(**dict(zip(('MAGPIE_CLI', 'MAGPIE_BIN_DIR', 'TERMUX_VERSION', 'PREFIX'), values)))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / 'upstream-env').read_text().splitlines(), list(values))

    def test_help_and_invalid_action_do_not_download(self):
        for action in ('help', '--help', '-h'):
            self.assertEqual(self.run_script(action).returncode, 0)
        self.assertEqual(self.run_script('not-an-action').returncode, 2)
        self.assertEqual(self.calls(), [])

    def test_menu_numbers_and_platform_entries(self):
        script = (ROOT / 'menu.sh').read_text().split('while true; do')[0]
        script += 'printf "%s\\n" "${tools[@]}"\n'
        for env, expected in (({}, ORIGINAL + ['magpie']), ({'TERMUX_VERSION': 'test'}, TERMUX + ['magpie']),
                              ({'PREFIX': '/data/data/com.termux/files/usr'}, TERMUX + ['magpie'])):
            result = subprocess.run([shutil.which('bash'), '-c', script], env=self.env | env,
                                    capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), expected)
        powershell = (ROOT / 'menu.ps1').read_text()
        entries = re.search(r'\$tools = @\(([^\n]+)\)', powershell).group(1)
        self.assertEqual(re.findall(r"'([^']+)'", entries), ORIGINAL + ['magpie'])
        self.assertTrue((ROOT / 'magpie.ps1').is_file())

    def test_remote_menus_share_one_immutable_revision(self):
        shell = (ROOT / 'menu.sh').read_text()
        powershell = (ROOT / 'menu.ps1').read_text()
        revision = re.search(r'    revision=([0-9a-f]{40})\n', shell).group(1)
        self.assertIn("$revision = '" + revision + "'", powershell)
        self.assertNotIn('873bb8de2d9af00fb2a5fbb592b3da094e665271', shell + powershell)
        self.assertNotIn('revision=main', shell)
        self.assertNotIn("$revision = 'main'", powershell)

    def menu(self, inputs, local=False, **env):
        folder = self.home / 'menu copy'
        folder.mkdir(exist_ok=True)
        menu = folder / 'menu.sh'
        shutil.copyfile(ROOT / 'menu.sh', menu)
        if local:
            (folder / 'magpie.sh').write_text('printf "local-magpie\\n"; exit 9\n')
        pid, fd = pty.fork()
        if pid == 0:
            os.execve(shutil.which('bash'), ['bash', str(menu)], self.env | env)
        chunks = []
        try:
            os.write(fd, inputs.encode())
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline:
                ready, _, _ = select.select([fd], [], [], 0.1)
                if ready:
                    try:
                        data = os.read(fd, 65536)
                    except OSError as exc:
                        if exc.errno != errno.EIO:
                            raise
                        break
                    if not data:
                        break
                    chunks.append(data)
            else:
                self.fail('Menu did not exit within the test limit.')
        finally:
            os.close(fd)
            done, status = os.waitpid(pid, os.WNOHANG)
            if not done:
                os.kill(pid, signal.SIGKILL)
                _, status = os.waitpid(pid, 0)
        self.assertEqual(os.waitstatus_to_exitcode(status), 0, b''.join(chunks).decode())
        return b''.join(chunks).decode()

    def test_standalone_menu_downloads_magpie_at_selected_revision(self):
        self.menu('invalid\n99\n24\n0\n', LMM_SCRIPTS_REV='reviewed-test')
        self.assertEqual(self.calls(), [
            'https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/reviewed-test/magpie.sh',
            'https://usemagpie.ai/install.sh',
        ])

    def test_termux_menu_installs_magpie(self):
        self.menu('7\n0\n', TERMUX_VERSION='test')
        self.assertTrue(self.calls()[0].endswith('/magpie.sh'))
        self.assertEqual((self.home / 'upstream-env').read_text().splitlines()[2], 'test')

    def test_local_menu_keeps_working_after_installer_failure(self):
        output = self.menu('24\n0\n', local=True)
        self.assertIn('local-magpie', output)
        self.assertIn('Installation failed.', output)
        self.assertEqual(self.calls(), [])

    def test_menu_download_failure_does_not_execute_partial_script(self):
        output = self.menu('24\n0\n', FAIL_DOWNLOAD='1')
        self.assertIn('Could not download magpie.', output)
        self.assertFalse((self.home / 'partial-executed').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
