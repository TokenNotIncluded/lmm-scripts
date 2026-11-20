"""Observe one exact DSH script in a temporary copy; this is diagnostic only."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit

BASE_SHA256 = 'eb4c97b09e913a0aa3192d23229dcf4bb252c1cfb4a7a30c3e0a741280203032'
TIMERS = frozenset('''npm npm:load command:install idealTree idealTree:init
idealTree:userRequests idealTree:buildDeps idealTree:fixDepFlags idealTree:checkEngine
build build:deps build:links build:queue build:link build:run:preinstall
build:run:install build:run:postinstall reify reify:loadTrees reify:diffTrees
reify:retireShallow reify:createSparse reify:loadShrinkwraps reify:loadBundles
reify:audit reify:unpack reify:unretire reify:build reify:trash reify:save'''.split())
VERSION = r'[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?'
PACKAGE = r'(?:@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*'
ANSI = re.compile(r'\x1b\[[0-?]*[ -/]*[@-~]')
STAGE = re.compile(r'LMM_DSH_STAGE name=(host-install|provider-download|provider-verify|plugin-add) event=(start|end)(?: elapsed_ms=([0-9]{1,12}) exit=(exception|-?[0-9]{1,11}))?')


def npm_event(line):
    """Return only bounded public identifiers/numbers; never return raw log text."""
    match = re.search(r'\bnpm (info|timing|http) (.+)$', line)
    if not match:
        return None
    level, message = match.groups()
    if level == 'timing':
        item = re.fullmatch(r'([^ ]+) Completed in ([0-9]{1,12})ms', message)
        if item and item[1] in TIMERS:
            return {'event': 'timer', 'name': item[1], 'elapsed_ms': int(item[2])}
    if level == 'info':
        item = re.fullmatch(r'using (npm|node)@v?(' + VERSION + ')', message)
        if item and len(item[2]) <= 80:
            return {'event': 'using', 'component': item[1], 'version': item[2]}
        item = re.fullmatch(r'run (' + PACKAGE + ')@(' + VERSION + r') (preinstall|install|postinstall|prepare) (.+)', message)
        if item and len(item[1]) <= 214 and len(item[2]) <= 80:
            result = {'package': item[1], 'version': item[2], 'phase': item[3]}
            if item[4].startswith('{'):
                end = re.fullmatch(r"\{ code: (null|-?[0-9]{1,11}), signal: (null|'SIG[A-Z0-9]{1,15}') \}", item[4])
                if end:
                    return {'event': 'lifecycle_end', **result,
                            'code': None if end[1] == 'null' else int(end[1]),
                            'signal': None if end[2] == 'null' else end[2][1:-1]}
            else:
                return {'event': 'lifecycle_start', **result}
    if level == 'http':
        item = re.fullmatch(r'fetch (GET|POST) ([1-5][0-9]{2}) (\S+) ([0-9]{1,12})ms(?: \((cache hit|cache miss|cache revalidated|cache updated)\))?', message)
        if item:
            result = {'event': 'http', 'method': item[1], 'status': int(item[2]),
                      'elapsed_ms': int(item[4])}
            # Read only the two public archive names, never print a URL or query.
            try:
                url = urlsplit(item[3])
                if url.scheme == 'https' and url.netloc == 'registry.npmjs.org' and not url.query and not url.fragment:
                    path = unquote(url.path)
                    for package, prefix in (('@deepseek-ai/dsh', '/@deepseek-ai/dsh/-/dsh-'), ('pnpm', '/pnpm/-/pnpm-')):
                        if path.startswith(prefix) and path.endswith('.tgz'):
                            version = path[len(prefix):-4]
                            if len(version) <= 80 and re.fullmatch(VERSION, version):
                                result.update(archive_package=package, archive_version=version)
            except ValueError:
                pass
            return result
    return None


def report_output(stream):
    """Stream allowlisted observations; cancellation need not reach a final file."""
    omitted = 0
    discarding = False
    for raw in iter(lambda: stream.readline(65537), b''):
        complete = raw.endswith(b'\n')
        if discarding or not complete or len(raw) > 65536:
            omitted += 1
            discarding = not complete
            continue
        line = ANSI.sub('', raw.decode('utf-8', errors='replace')).strip()
        stage_match = STAGE.search(line)
        if stage_match:
            print(stage_match[0], flush=True)
            continue
        event = npm_event(line)
        if event:
            print('LMM_DSH_NPM ' + json.dumps(event, separators=(',', ':')), flush=True)
        else:
            omitted += 1
    print('LMM_DSH_NPM ' + json.dumps({'event': 'stream_end', 'omitted_lines': omitted}), flush=True)


def stage(name, body, native=False, indent=''):
    lines = []
    if name == 'host-install':
        lines += [indent + '$dshNpmTimingBefore = $env:npm_config_timing',
                  indent + '$dshNpmLoglevelBefore = $env:npm_config_loglevel']
    lines += [indent + '$dshStageClock = [Diagnostics.Stopwatch]::StartNew()',
             indent + "$dshStageExit = 'exception'",
             indent + "Write-Host 'LMM_DSH_STAGE name=" + name + " event=start'",
             indent + 'try {']
    if name == 'host-install':
        lines += [indent + "  $env:npm_config_timing = 'true'",
                  indent + "  $env:npm_config_loglevel = 'info'"]
    lines += [indent + '  ' + line for line in body.splitlines()]
    lines += [indent + '  $dshStageExit = ' + ('$LASTEXITCODE' if native else '0'),
              indent + '} finally {']
    if name == 'host-install':
        lines += [indent + '  $env:npm_config_timing = $dshNpmTimingBefore',
                  indent + '  $env:npm_config_loglevel = $dshNpmLoglevelBefore']
    lines += [indent + '  $dshStageClock.Stop()',
              indent + '  Write-Host ("LMM_DSH_STAGE name=' + name + ' event=end elapsed_ms={0} exit={1}" -f $dshStageClock.ElapsedMilliseconds, $dshStageExit)',
              indent + '}']
    return '\n'.join(lines)


def instrument(original):
    if hashlib.sha256(original).hexdigest() != BASE_SHA256:
        raise ValueError('DSH diagnostic source binding mismatch')
    source = original.decode('utf-8')
    host = 'npm.cmd install -g @deepseek-ai/dsh@latest pnpm@latest'
    download = "Invoke-WebRequest -UseBasicParsing 'https://github.com/TokenNotIncluded/dsh-lmm-provider/releases/download/v0.1.0-alpha.9/dsh-lmm-provider.tgz' -OutFile $download"
    verify = '\n'.join([
        "if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $expected) { throw 'DSH checksum mismatch.' }",
        'if (-not (Test-Path -LiteralPath $plugin)) { [IO.File]::Move($download, $plugin) }',
        '$info = Get-Item -LiteralPath $plugin -Force',
        "if ($info.PSIsContainer -or ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash -LiteralPath $plugin -Algorithm SHA256).Hash -ne $expected) { throw 'DSH checksum mismatch.' }"
    ])
    plugin = 'dsh.cmd plugin --profile $Profile add $plugin --ignore-scripts'
    changes = [
        (host + '\nif ($LASTEXITCODE) { exit $LASTEXITCODE }', stage('host-install', host, native=True) + '\nif ($dshStageExit) { exit $dshStageExit }'),
        ('  ' + download, stage('provider-download', download, indent='  ')),
        ('\n'.join('  ' + line for line in verify.splitlines()), stage('provider-verify', verify, indent='  ')),
        ('  ' + plugin + '\n  exit $LASTEXITCODE', stage('plugin-add', plugin, native=True, indent='  ') + '\n  exit $dshStageExit')
    ]
    candidate = source
    for before, after in changes:
        if candidate.count(before) != 1:
            raise ValueError('DSH diagnostic stage boundary mismatch')
        candidate = candidate.replace(before, after, 1)
    restored = candidate
    for before, after in reversed(changes):
        if restored.count(after) != 1:
            raise ValueError('DSH diagnostic inverse boundary mismatch')
        restored = restored.replace(after, before, 1)
    if restored.encode('utf-8') != original:
        raise ValueError('DSH diagnostic inverse changed source')
    return candidate.encode('utf-8')


def main():
    if len(sys.argv) != 1:
        raise ValueError('DSH diagnostic takes no arguments')
    root = Path(__file__).resolve().parent
    source = root / 'dsh.ps1'
    original = source.read_bytes()
    overlay = instrument(original)
    print('LMM_DSH_DIAGNOSTIC scope=instrumented-copy-only base_sha256=' + BASE_SHA256
          + ' overlay_sha256=' + hashlib.sha256(overlay).hexdigest(), flush=True)
    try:
        with tempfile.TemporaryDirectory(prefix='lmm-dsh-stages-') as work:
            script = Path(work) / 'dsh.ps1'
            with script.open('xb') as stream:
                stream.write(overlay)
            with subprocess.Popen(['powershell.exe', '-NoProfile', '-NonInteractive',
                                   '-ExecutionPolicy', 'Bypass', '-File', str(script)],
                                  cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT) as child:
                report_output(child.stdout)
                result = child.wait()
            print('LMM_DSH_DIAGNOSTIC event=end exit=' + str(result), flush=True)
            return result
    finally:
        if source.read_bytes() != original:
            raise ValueError('DSH diagnostic original source drift')


if __name__ == '__main__':
    sys.exit(main())
