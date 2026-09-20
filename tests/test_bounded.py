"""Exercise the actual Bash wrapper with real Unix process groups, without HTTP."""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
LIBRARY = ROOT / 'templates/lib/node.sh'
FIXTURE = r'''
import json, os, signal, subprocess, sys, time
from pathlib import Path
base = Path(sys.argv[1])
mode = sys.argv[2]
if mode == 'retry':
    attempted = base / 'attempted'
    if attempted.exists():
        pid = (base / 'worker').read_text()
        state = subprocess.run(['ps', '-o', 'stat=', '-p', pid], text=True, capture_output=True).stdout.strip()
        sys.exit(88 if state and not state.startswith('Z') else 0)
    attempted.touch()
    mode = 'orphan'
if mode == 'worker':
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    signal.signal(signal.SIGINT, signal.SIG_IGN)
    (base / 'worker').write_text(str(os.getpid()))
    while True:
        if not (base / 'stage').exists() or not (base / '.setup-lock').exists():
            (base / 'early-cleanup').touch()
        time.sleep(.02)
if mode == 'ignore':
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
if mode == 'cooperative':
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
(base / 'leader').write_text(json.dumps({'pid': os.getpid(), 'wrapper': os.getppid()}))
if mode in ('orphan', 'cooperative'):
    subprocess.Popen([sys.executable, __file__, str(base), 'worker'],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
while True:
    time.sleep(.02)
'''
HARNESS = r'''
set -euo pipefail
source "$1/templates/lib/node.sh"
source "$1/templates/lib/lifecycle.sh"
shift
ROOT=$1; shift
STAGE=$ROOT/stage LOCKED=1 PHASE=test
mkdir -p "$STAGE" "$ROOT/.setup-lock"
printf '%s\n' "$$" > "$ROOT/.setup-lock/pid"
log() { printf '%s\n' "$*" >&2; }
fail() { log "$*"; exit 1; }
trap cleanup EXIT
if [ "${TEST_RETRY:-0}" = 1 ]; then
  NETWORK=auto NPM_SELECTED=1 npm_config_registry=https://registry.npmjs.org/
  with_registry_retry "$@"
else
  bounded "$@"
fi
'''


@unittest.skipUnless(os.name == 'posix' and shutil.which('bash') and shutil.which('node'),
                     'Bash, Node and Unix process groups required')
class BoundedTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.base = Path(self.tmp.name)
        self.fixture = self.base / 'build fixture.py'
        self.fixture.write_text(FIXTURE, encoding='utf-8')
        self.process = None

    def tearDown(self):
        # Every test owns a separate detached group; never leak even on failure.
        leader = self.base / 'leader'
        if leader.exists():
            try:
                os.killpg(json.loads(leader.read_text())['pid'], signal.SIGKILL)
            except ProcessLookupError:
                pass
        if self.process:
            try:
                os.killpg(self.process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            self.process.communicate(timeout=5)
        self.tmp.cleanup()

    def start(self, *command, seconds=1, retry=False):
        self.started = time.monotonic()
        self.process = subprocess.Popen(
            ['bash', '-c', HARNESS, 'bounded-test', str(ROOT), str(self.base), *command],
            env=dict(os.environ, COMMAND_TIMEOUT=str(seconds), TEST_RETRY=str(int(retry))),
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)

    def wait_ready(self, name):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            path = self.base / name
            if path.exists() and path.stat().st_size:
                return path
            if self.process.poll() is not None:
                break
            time.sleep(.02)
        self.fail(f'Fixture never became ready: {name}')

    def finish(self, expected):
        stdout, stderr = self.process.communicate(timeout=9)
        self.assertEqual(self.process.returncode, expected, stdout + stderr)
        self.assertFalse((self.base / '.setup-lock').exists())
        self.assertFalse((self.base / 'stage').exists())
        self.assertFalse((self.base / 'early-cleanup').exists(), 'cleanup ran while a worker was active')
        return stderr

    def assert_stopped(self, pid):
        # Orphans can briefly remain zombies until init reaps them.
        deadline = time.monotonic() + 1
        while time.monotonic() < deadline:
            state = subprocess.run(['ps', '-o', 'stat=', '-p', str(pid)],
                                   text=True, capture_output=True, check=False).stdout.strip()
            if not state or state.startswith('Z'):
                return
            time.sleep(.02)
        self.fail(f'Process {pid} still running after wrapper returned: {state}')

    def test_timeout_keeps_lock_and_stage_until_orphan_is_killed(self):
        self.start(sys.executable, str(self.fixture), str(self.base), 'orphan')
        worker = int(self.wait_ready('worker').read_text())
        time.sleep(max(0, self.started + 1.5 - time.monotonic()))
        self.assertIsNone(self.process.poll(), 'wrapper exited before its hard-kill deadline')
        self.assertTrue((self.base / '.setup-lock').is_dir())
        self.assertTrue((self.base / 'stage').is_dir())
        self.assertIn('timed out', self.finish(124))
        self.assert_stopped(worker)

    def test_timeout_kills_leader_ignoring_sigterm(self):
        self.start(sys.executable, str(self.fixture), str(self.base), 'ignore')
        leader = json.loads(self.wait_ready('leader').read_text())['pid']
        self.finish(124)
        self.assert_stopped(leader)

    def test_normal_exit_has_no_grace_delay(self):
        for code in (0, 7):
            with self.subTest(code=code):
                self.start(sys.executable, '-c', f'raise SystemExit({code})', seconds=30)
                self.finish(code)
                self.assertLess(time.monotonic() - self.started, 3)

    def test_spawn_error_does_not_keep_timers_alive(self):
        self.start(str(self.base / 'missing-command'), seconds=30)
        self.assertIn('ENOENT', self.finish(1))
        self.assertLess(time.monotonic() - self.started, 3)

    def test_already_exited_group_preserves_signal_status(self):
        self.start(sys.executable, '-c', 'import os,signal; os.kill(os.getpid(),signal.SIGTERM)', seconds=30)
        self.finish(143)
        self.assertLess(time.monotonic() - self.started, 3)

    def cancel(self, signum, expected, mode='orphan', repeated=False):
        self.start(sys.executable, str(self.fixture), str(self.base), mode, seconds=2)
        worker = int(self.wait_ready('worker').read_text())
        wrapper = json.loads((self.base / 'leader').read_text())['wrapper']
        os.kill(wrapper, signum)
        if repeated:
            time.sleep(.1)
            os.kill(wrapper, signal.SIGTERM)
        stderr = self.finish(expected)
        self.assertNotIn('timed out', stderr, 'cancellation must clear the original deadline')
        self.assert_stopped(worker)

    def test_sigint_waits_for_descendants(self):
        self.cancel(signal.SIGINT, 130)

    def test_sigterm_preserved_when_child_exits_successfully(self):
        self.cancel(signal.SIGTERM, 143, mode='cooperative')

    def test_repeated_cancel_preserves_first_reason(self):
        self.cancel(signal.SIGINT, 130, repeated=True)

    def test_cancellation_does_not_retry_registry(self):
        for code in (130, 143):
            for network in ('auto', 'official'):
                with self.subTest(code=code, network=network):
                    calls = self.base / 'calls'
                    calls.write_text('')
                    script = r'''
set -euo pipefail
source "$1"
bounded() { printf 'attempt\n' >> "$2"; return "$1"; }
log() { :; }
fail() { exit 1; }
NETWORK=$4 NPM_SELECTED=1 npm_config_registry=https://registry.npmjs.org/
with_registry_retry "$2" "$3"
'''
                    result = subprocess.run(['bash', '-c', script, 'retry-test', str(LIBRARY), str(code), str(calls), network],
                                            text=True, capture_output=True, timeout=5)
                    self.assertEqual(result.returncode, code, result.stderr)
                    self.assertEqual(calls.read_text().splitlines(), ['attempt'])

    def test_registry_retry_waits_for_timed_out_group(self):
        self.start(sys.executable, str(self.fixture), str(self.base), 'retry', retry=True)
        worker = int(self.wait_ready('worker').read_text())
        self.finish(0)
        self.assert_stopped(worker)


if __name__ == '__main__':
    unittest.main(verbosity=2)
