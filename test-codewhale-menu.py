"""Real pseudo-terminal checks for menu routing; no packages or accounts are used."""
import errno
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parent


class MenuTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='lmm-menu-')
        self.home = Path(self.tmp.name)
        shutil.copyfile(ROOT / 'menu.sh', self.home / 'menu.sh')
        self.env = dict(os.environ)
        self.env.pop('TERMUX_VERSION', None)
        self.env.pop('PREFIX', None)

    def tearDown(self):
        self.tmp.cleanup()

    def run_menu(self, choices):
        bash = shutil.which('bash')
        pid, fd = pty.fork()
        if pid == 0:
            os.chdir(self.home)
            os.execve(bash, [bash, str(self.home / 'menu.sh')], self.env)
        output = b''
        pending = list(choices)
        deadline = time.monotonic() + 8
        status = None
        try:
            while time.monotonic() < deadline:
                ready, _, _ = select.select([fd], [], [], 0.05)
                if ready:
                    try:
                        chunk = os.read(fd, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    if not chunk:
                        break
                    output += chunk
                    if output.endswith(b'> ') and pending:
                        os.write(fd, (pending.pop(0) + '\n').encode())
                done, value = os.waitpid(pid, os.WNOHANG)
                if done:
                    status = value
                    break
            if status is None:
                done, value = os.waitpid(pid, os.WNOHANG)
                if done:
                    status = value
            if status is None:
                os.kill(pid, signal.SIGKILL)
                os.waitpid(pid, 0)
                self.fail('Menu did not terminate: ' + output.decode(errors='replace'))
            self.assertTrue(os.WIFEXITED(status), output)
            self.assertEqual(os.WEXITSTATUS(status), 0, output)
            self.assertFalse(pending, output)
            return output.decode(errors='replace')
        finally:
            os.close(fd)

    def stub(self, name):
        (self.home / (name + '.sh')).write_text("printf 'SELECTED:" + name + " %s\\n' \"$*\"\n")

    def test_new_eighth_option_routes_to_codewhale_submenu(self):
        self.stub('codewhale')
        output = self.run_menu(['8', '0'])
        self.assertIn('8  codewhale', output)
        self.assertIn('SELECTED:codewhale menu', output)

    def test_old_numbering_and_argument_contract_are_preserved(self):
        self.stub('pi')
        output = self.run_menu(['1', '0'])
        self.assertIn('SELECTED:pi ', output)
        self.assertNotIn('SELECTED:pi menu', output)

    def test_out_of_range_and_overflow_input_return_to_menu(self):
        output = self.run_menu(['9', '999999999999999999999999999', '-1', '0'])
        self.assertNotIn('SELECTED:', output)

    def test_termux_hides_desktop_apps_and_routes_sixth_option(self):
        self.stub('codewhale')
        self.env['TERMUX_VERSION'] = 'test'
        output = self.run_menu(['6', '0'])
        self.assertNotIn('cc-switch', output)
        self.assertNotIn('clash-verge-rev', output)
        self.assertIn('6  codewhale', output)
        self.assertIn('SELECTED:codewhale menu', output)

    def test_remote_menu_preserves_submenu_argument(self):
        bin_dir = self.home / 'bin'
        bin_dir.mkdir()
        stub = bin_dir / 'curl'
        stub.write_text("#!/bin/sh\ncat <<'SCRIPT'\nprintf 'REMOTE:%s\\n' \"$*\"\nSCRIPT\n")
        stub.chmod(0o755)
        self.env['PATH'] = str(bin_dir) + os.pathsep + self.env['PATH']
        output = self.run_menu(['8', '0'])
        self.assertIn('REMOTE:menu', output)

    def test_failed_remote_download_is_not_executed(self):
        bin_dir = self.home / 'bin'
        bin_dir.mkdir()
        stub = bin_dir / 'curl'
        stub.write_text('#!/bin/sh\necho "touch should-not-exist"\nexit 18\n')
        stub.chmod(0o755)
        self.env['PATH'] = str(bin_dir) + os.pathsep + self.env['PATH']
        self.run_menu(['8', '0'])
        self.assertFalse((self.home / 'should-not-exist').exists())


if __name__ == '__main__':
    unittest.main(verbosity=2)
