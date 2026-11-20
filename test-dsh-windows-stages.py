"""Diagnostic only: install the complete official wheel in a job-owned venv."""
from pathlib import Path
from email.parser import BytesParser
import configparser
import hashlib
import http.cookiejar
import json
import os
import platform
import queue
import re
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import zipfile

BASE_SHA256 = 'eb4c97b09e913a0aa3192d23229dcf4bb252c1cfb4a7a30c3e0a741280203032'
WHEEL_NAME = 'deepseek_harness_runtime_bin-0.2.2rc2-py3-none-win_amd64.whl'
WHEEL_URL = 'https://files.pythonhosted.org/packages/4e/87/cc1080f32f3835637d93d265ff94d2b24a1ec6b96780894a7e7eeb0a0b5a/' + WHEEL_NAME
WHEEL_SHA256 = 'a791af95a97be205a73354c6819e95b5fe2ff40a57ef8a78d53c188ee33e9aea'
RUNTIME_VERSION = '0.2.2-rc.2'
DIST = 'deepseek_harness_runtime_bin-0.2.2rc2.dist-info/'
PAYLOAD = 'deepseek_harness_runtime/runtime/'
REQUIRED = [PAYLOAD + 'deepseek-harness-sdk-runtime-win-x64.exe',
            PAYLOAD + 'deepseek-harness-sdk-runtime-win-x64-rg.exe',
            PAYLOAD + 'win-x64/downloads.json']
RECORD = {'scope': 'official-wheel-diagnostic-only', 'qualification_for_default_npm_installer': False}


class DiagnosticFailure(Exception):
    """Only fixed, credential-free reasons written by this controller."""


def emit(event, **values):
    print('LMM_DSH_WHEEL ' + json.dumps({'event': event, **values}, separators=(',', ':')), flush=True)


def sha256(path):
    with path.open('rb') as stream:
        return stream_sha256(stream)


def stream_sha256(stream):
    digest = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        digest.update(chunk)
    return digest.hexdigest()


def run(argv, phase, *, env, cwd, timeout):
    started = time.monotonic()
    emit('start', phase=phase)
    try:
        result = subprocess.run(argv, env=env, cwd=cwd, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=timeout)
    except subprocess.TimeoutExpired:
        emit('end', phase=phase, timed_out=True)
        raise DiagnosticFailure('bounded command timed out') from None
    emit('end', phase=phase, exit=result.returncode,
         elapsed_ms=round((time.monotonic() - started) * 1000))
    if result.returncode:
        raise DiagnosticFailure('command failed')
    return result.stdout


def acquire_wheel(path):
    started = time.monotonic()
    size = 0
    emit('start', phase='wheel-acquire')
    with urllib.request.urlopen(WHEEL_URL, timeout=60) as response, path.open('xb') as stream:
        if response.status != 200 or response.geturl() != WHEEL_URL:
            raise DiagnosticFailure('wheel origin changed')
        while chunk := response.read(1024 * 1024):
            size += len(chunk)
            if size > 128 * 1024 * 1024 or time.monotonic() - started > 180:
                raise DiagnosticFailure('wheel acquisition bound exceeded')
            stream.write(chunk)
    if sha256(path) != WHEEL_SHA256:
        raise DiagnosticFailure('wheel digest mismatch')
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise DiagnosticFailure('duplicate wheel member')
        for info in archive.infolist():
            parts = info.filename.split('/')
            if info.filename.startswith('/') or '..' in parts or '\\' in info.filename or ':' in info.filename:
                raise DiagnosticFailure('unsafe wheel member')
            if (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise DiagnosticFailure('wheel symlink not accepted')
        metadata = BytesParser().parsebytes(archive.read(DIST + 'METADATA'))
        if metadata['Name'] != 'deepseek-harness-runtime-bin' or metadata['Version'] != '0.2.2rc2':
            raise DiagnosticFailure('wheel identity mismatch')
        if metadata.get_all('Requires-Dist', []) or metadata['Requires-Python'] != '>=3.10':
            raise DiagnosticFailure('unexpected wheel dependency contract')
        wheel = BytesParser().parsebytes(archive.read(DIST + 'WHEEL'))
        if wheel.get_all('Tag') != ['py3-none-win_amd64']:
            raise DiagnosticFailure('wheel platform mismatch')
        entry = configparser.ConfigParser(interpolation=None)
        entry.read_string(archive.read(DIST + 'entry_points.txt').decode())
        if entry['console_scripts']['dsh'].replace(' ', '') != 'deepseek_harness_runtime:main':
            raise DiagnosticFailure('wheel launcher mismatch')
        if {name[len(PAYLOAD):].split('/')[0] for name in names if name.startswith(PAYLOAD) and name != PAYLOAD} != {
                'deepseek-harness-sdk-runtime-win-x64.exe',
                'deepseek-harness-sdk-runtime-win-x64-rg.exe', 'win-x64'}:
            raise DiagnosticFailure('unexpected runtime payload')
        members = []
        for name in REQUIRED:
            with archive.open(name) as stream:
                digest = stream_sha256(stream)
            members.append({'name': name, 'bytes': archive.getinfo(name).file_size, 'sha256': digest})
    RECORD['wheel'] = {'file': WHEEL_NAME, 'sha256': WHEEL_SHA256, 'bytes': size,
                       'requires_python': '>=3.10', 'requires_dist': [], 'members': members}
    emit('wheel_verified', **RECORD['wheel'])


def prepare_host(root, work, venv, env):
    emit('stage_start', phase='host-install')
    started = time.monotonic()
    archive = work / WHEEL_NAME
    acquire_wheel(archive)
    run([sys.executable, '-I', '-m', 'venv', str(venv)], 'venv-create', env=env, cwd=root, timeout=60)
    python = venv / 'Scripts/python.exe'
    launcher = venv / 'Scripts/dsh.exe'
    requirements = work / 'requirements.txt'
    requirements.write_text(archive.as_uri() + ' --hash=sha256:' + WHEEL_SHA256 + '\n', encoding='utf-8')
    run([str(python), '-I', '-m', 'pip', '--isolated', 'install', '--disable-pip-version-check',
         '--no-input', '--no-index', '--no-deps', '--no-cache-dir', '--only-binary=:all:',
         '--require-hashes', '-r', str(requirements)], 'wheel-install', env=env, cwd=root, timeout=120)
    probe = "import importlib.metadata,json; import deepseek_harness_runtime as r; print(json.dumps({'version':importlib.metadata.version('deepseek-harness-runtime-bin'),'root':str(r.bundled_package_dir()),'runtime':str(r.bundled_runtime_path()),'argv':r.resolve_bundled_launch_args('exe')}))"
    installed = json.loads(run([str(python), '-I', '-c', probe], 'payload-validate', env=env, cwd=root, timeout=20))
    package_root = Path(installed['root']).resolve()
    if installed['version'] != '0.2.2rc2' or not package_root.is_relative_to(venv.resolve()):
        raise DiagnosticFailure('installed wheel escaped owned venv')
    runtime = Path(installed['runtime']).resolve()
    if installed['argv'] != [str(runtime)] or not launcher.is_file():
        raise DiagnosticFailure('installed launcher identity mismatch')
    for member in RECORD['wheel']['members']:
        relative = member['name'].removeprefix('deepseek_harness_runtime/')
        path = package_root / relative
        if not path.is_file() or path.stat().st_size != member['bytes'] or sha256(path) != member['sha256']:
            raise DiagnosticFailure('installed runtime member mismatch')
    run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command',
         'npm.cmd install -g pnpm@latest; exit $LASTEXITCODE'], 'pnpm-install', env=env, cwd=root, timeout=None)
    version = run([str(launcher), '--version'], 'host-version', env=env, cwd=root, timeout=30).decode().strip()
    if version != RUNTIME_VERSION:
        raise DiagnosticFailure('actual host version mismatch')
    RECORD['runtime'] = {'version': version, 'launcher': 'Scripts/dsh.exe', 'launcher_sha256': sha256(launcher), 'members_match_wheel': True}
    emit('stage_end', phase='host-install', exit=0, elapsed_ms=round((time.monotonic()-started)*1000), **RECORD['runtime'])
    return launcher


def instrument(original, launcher):
    if hashlib.sha256(original).hexdigest() != BASE_SHA256:
        raise DiagnosticFailure('DSH source binding mismatch')
    host = 'npm.cmd install -g @deepseek-ai/dsh@latest pnpm@latest\nif ($LASTEXITCODE) { exit $LASTEXITCODE }'
    command = 'dsh.cmd plugin --profile $Profile add $plugin --ignore-scripts'
    replacement = "& '" + str(launcher).replace("'", "''") + "' plugin --profile $Profile add $plugin --ignore-scripts"
    changes = [(host, '# Official complete wheel and original pnpm installation were validated by the diagnostic helper.'),
               (command, replacement)]
    result = original.decode()
    for before, after in changes:
        if result.count(before) != 1:
            raise DiagnosticFailure('DSH replacement boundary mismatch')
        result = result.replace(before, after, 1)
    restored = result
    for before, after in reversed(changes):
        if restored.count(after) != 1:
            raise DiagnosticFailure('DSH inverse boundary mismatch')
        restored = restored.replace(after, before, 1)
    if restored.encode() != original:
        raise DiagnosticFailure('DSH inverse drift')
    return result.encode()


def check_web(launcher, root, env):
    # These are the same launch and signed-out RPC contracts used by DSH1948's test-host.mjs.
    child = subprocess.Popen([str(launcher), 'web', '--no-open', '--port', '0'], cwd=root,
                             env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    messages = queue.Queue(maxsize=1024)
    overflow = threading.Event()
    def read_lines():
        for line in iter(lambda: child.stdout.readline(65537), b''):
            try:
                messages.put_nowait(line[:65536])
            except queue.Full:
                overflow.set()
    reader = threading.Thread(target=read_lines, daemon=True)
    reader.start()
    try:
        deadline = time.monotonic() + 30
        launch = None
        while time.monotonic() < deadline:
            if overflow.is_set() or child.poll() is not None:
                raise DiagnosticFailure('web startup failed')
            try:
                line = messages.get(timeout=min(0.1, max(0.001, deadline-time.monotonic())))
            except queue.Empty:
                continue
            found = re.search(rb'http://127\.0\.0\.1:([0-9]{1,5})/\?token=[\w-]+', line)
            if found and 0 < int(found[1]) < 65536:
                launch = found[0].decode()
                break
        if launch is None:
            raise DiagnosticFailure('web startup deadline')
        origin = launch.split('/?')[0]
        endpoint = origin + '/api/lmm-auth/status'
        direct = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        try:
            direct.open(urllib.request.Request(endpoint, data=b'{}', headers={'Content-Type': 'application/json'}), timeout=5)
        except urllib.error.HTTPError as error:
            if error.code != 401:
                raise DiagnosticFailure('unauthenticated route status mismatch') from None
            error.close()
        else:
            raise DiagnosticFailure('unauthenticated route accepted')
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))
        with opener.open(launch, timeout=5) as response:
            if response.status != 200:
                raise DiagnosticFailure('launch authentication failed')
            response.read(1024 * 1024)
        body = json.dumps({'type': 'client-request', 'rpcId': 'test', 'method': 'lmm-auth/status', 'payload': {}}).encode()
        request = urllib.request.Request(endpoint, data=body, headers={'Origin': origin, 'Content-Type': 'application/json'})
        with opener.open(request, timeout=5) as response:
            result = json.loads(response.read(1024 * 1024))
            if response.status != 200 or result['result']['ok'] is not True or result['result']['value']['signedIn'] is not False:
                raise DiagnosticFailure('real plugin signed-out status mismatch')
        RECORD['web'] = {'actual_plugin_route': True, 'unauthenticated_status': 401, 'authenticated_status': 200,
                         'signed_in': False, 'oauth_started': False, 'model_requests': 0}
        emit('web_verified', **RECORD['web'])
    finally:
        exit_before_cleanup = child.poll()
        if exit_before_cleanup is None:
            stopped = subprocess.run(['taskkill.exe', '/PID', str(child.pid), '/T', '/F'],
                                     stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)
            child.wait(timeout=10)
            emit('owned_web_stopped', tree_kill_exit=stopped.returncode, process_exit=child.returncode)
            if stopped.returncode and sys.exc_info()[0] is None:
                raise DiagnosticFailure('web cleanup failed')
        else:
            emit('owned_web_already_exited', process_exit=exit_before_cleanup)
        reader.join(timeout=1)
        child.stdout.close()
        if exit_before_cleanup is not None and sys.exc_info()[0] is None:
            raise DiagnosticFailure('web launcher exited before owned cleanup')


def main():
    if len(sys.argv) != 1 or sys.platform != 'win32' or platform.machine().lower() not in ('amd64', 'x86_64') or sys.version_info < (3, 10):
        raise DiagnosticFailure('Windows x64 Python >=3.10 required')
    root = Path(__file__).resolve().parent
    source = root / 'dsh.ps1'
    original = source.read_bytes()
    if hashlib.sha256(original).hexdigest() != BASE_SHA256:
        raise DiagnosticFailure('DSH source binding mismatch')
    temporary = Path(os.environ['RUNNER_TEMP']).resolve(strict=True)
    home = Path(os.environ['DSH_HOME']).resolve()
    if not home.is_relative_to(temporary) or os.environ.get('DSH_RUNTIME_MODE') not in (None, 'exe'):
        raise DiagnosticFailure('explicit job-owned native runtime home required')
    venv = temporary / 'lmm-dsh-official-wheel-rc2'
    if venv.exists():
        raise DiagnosticFailure('owned runtime path already exists')
    env = os.environ.copy()
    env['DSH_RUNTIME_MODE'] = 'exe'
    emit('source', original_sha256=BASE_SHA256, scope=RECORD['scope'])
    try:
        with tempfile.TemporaryDirectory(prefix='lmm-dsh-wheel-input-', dir=temporary) as work:
            work = Path(work)
            launcher = prepare_host(root, work, venv, env)
            overlay = instrument(original, launcher)
            script = work / 'dsh.ps1'
            script.write_bytes(overlay)
            emit('overlay', sha256=hashlib.sha256(overlay).hexdigest(), inverse_matches=True)
            run(['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', str(script)],
                'provider-original-install', env=env, cwd=root, timeout=None)
            check_web(launcher, root, env)
            RECORD['result'] = 'PASS'
            emit('complete', **RECORD)
            return 0
    finally:
        if source.read_bytes() != original:
            raise DiagnosticFailure('original source drift')
        # Keep this job-owned venv for the original five final version checks.
        # GitHub removes the ephemeral runner; no user/system PATH is changed.


if __name__ == '__main__':
    try:
        sys.exit(main())
    except Exception as error:
        emit('failed', error_type=type(error).__name__,
             reason=str(error) if isinstance(error, DiagnosticFailure) else 'external-operation-failed')
        sys.exit(1)
