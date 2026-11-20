"""Observe one exact DSH script in a temporary copy; this is diagnostic only."""
from pathlib import Path
import hashlib
import subprocess
import sys
import tempfile

BASE_SHA256 = 'eb4c97b09e913a0aa3192d23229dcf4bb252c1cfb4a7a30c3e0a741280203032'


def stage(name, body, native=False, indent=''):
    lines = [indent + '$dshStageClock = [Diagnostics.Stopwatch]::StartNew()',
             indent + "$dshStageExit = 'exception'",
             indent + "Write-Host 'LMM_DSH_STAGE name=" + name + " event=start'",
             indent + 'try {']
    lines += [indent + '  ' + line for line in body.splitlines()]
    lines += [indent + '  $dshStageExit = ' + ('$LASTEXITCODE' if native else '0'),
              indent + '} finally {',
              indent + '  $dshStageClock.Stop()',
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
            result = subprocess.run(['powershell.exe', '-NoProfile', '-NonInteractive',
                                     '-ExecutionPolicy', 'Bypass', '-File', str(script)], cwd=root)
            print('LMM_DSH_DIAGNOSTIC event=end exit=' + str(result.returncode), flush=True)
            return result.returncode
    finally:
        if source.read_bytes() != original:
            raise ValueError('DSH diagnostic original source drift')


if __name__ == '__main__':
    sys.exit(main())
