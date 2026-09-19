import hashlib
import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
NODE = shutil.which('node')
BASH = shutil.which('bash')

class Installers(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='lmm installers ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'; self.bin.mkdir()
        for command in ('uname','mkdir','mktemp','rm','rmdir','mv','chmod','tar','gzip','cat','sleep','sha256sum','shasum','openssl'):
            found = shutil.which(command)
            if found: (self.bin / command).symlink_to(found)
        self.env = dict(os.environ, PATH=str(self.bin), LMM_INSTALL_ROOT=str(self.root/'installation with spaces'), LMM_CACHE_ROOT=str(self.root/'cache'), LMM_RETRIES='2', LMM_COMMAND_TIMEOUT='5')
        for name in ('BASH_ENV','ENV','NODE_OPTIONS','LMM_NODE_BASE_URL','LMM_NPM_REGISTRY'):
            self.env.pop(name, None)

    def script(self, name, content):
        path = self.bin / name
        if path.exists(): path.unlink()
        path.write_text('#!/bin/sh\n'+content+'\n');path.chmod(0o755)
        return path

    def runtime(self):
        self.assertIsNotNone(NODE)
        (self.bin/'node').symlink_to(NODE)
        self.script('npm', 'if [ "$1" = --version ]; then echo 10.9.0; exit 0; fi\nexit 1')

    def run_script(self, app='pi', args=(), script=None, **env):
        return subprocess.run([BASH,str(script or ROOT/(app+'.sh')),*args],env={**self.env,**env},capture_output=True,text=True,timeout=20)

    def test_help_works_without_tools_or_network(self):
        result=self.run_script(args=['--help'],PATH=str(self.root/'empty'))
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('LMM_DOWNLOAD_TIMEOUT',result.stdout)
        self.assertFalse((self.root/'cache').exists())

    def test_check_reports_missing_dependencies_without_writes(self):
        result=self.run_script(args=['--check'])
        self.assertEqual(result.returncode,2,result.stderr)
        self.assertIn('Node/npm missing',result.stderr)
        self.assertFalse((self.root/'cache').exists())

    def test_no_bootstrap_and_bad_configuration_are_clear_failures(self):
        result=self.run_script(args=['--no-bootstrap'])
        self.assertNotEqual(result.returncode,0)
        self.assertIn('Compatible Node/npm missing',result.stderr)
        result=self.run_script(LMM_RETRIES='0')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('positive integers',result.stderr)

    def test_existing_pi_keeps_proxy_and_returns_native_install_error(self):
        self.runtime()
        log=self.root/'arguments'
        self.script('pi', 'if [ "$1" = --version ]; then echo 0.85.1; exit 0; fi\nprintf "%s\\n" "$@" > "$TEST_LOG"\n[ "$HTTPS_PROXY" = "$TEST_PROXY" ] || exit 9\nexit 17')
        result=self.run_script(TEST_LOG=str(log),HTTPS_PROXY='http://placeholder:private@127.0.0.1:9',TEST_PROXY='http://placeholder:private@127.0.0.1:9')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('npm:@tokennotincluded/pi-lmm-provider@0.1.0-alpha.1',log.read_text())
        self.assertNotIn('placeholder:private',result.stderr+result.stdout)
        self.assertFalse(Path(self.env['LMM_INSTALL_ROOT'],'.installer-lock').exists())

    def test_existing_dsh_forwards_arguments_with_spaces(self):
        self.runtime();log=self.root/'arguments'
        self.script('dsh','if [ "$1" = --version ]; then echo 0.1.5-rc.1; exit 0; fi\nprintf "%s\\n" "$@" > "$TEST_LOG"')
        result=self.run_script('dsh',['--','--cwd','folder with spaces'],TEST_LOG=str(log))
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(log.read_text().splitlines(),['web','--cwd','folder with spaces'])

    def test_failed_npm_install_never_promotes_partial_client(self):
        self.runtime()
        result=self.run_script('dsh',['--install-only'])
        self.assertNotEqual(result.returncode,0)
        self.assertFalse(Path(self.env['LMM_INSTALL_ROOT'],'apps/dsh-0.1.5-rc.1').exists())
        self.assertEqual(list(Path(self.env['LMM_INSTALL_ROOT']).glob('.stage.*')),[])

    def test_lock_does_not_delete_another_installation(self):
        self.runtime();lock=Path(self.env['LMM_INSTALL_ROOT'],'.installer-lock');lock.mkdir(parents=True);(lock/'pid').write_text('unrelated')
        result=self.run_script()
        self.assertNotEqual(result.returncode,0)
        self.assertEqual((lock/'pid').read_text(),'unrelated')

    def test_timeout_stops_installer_and_returns_failure(self):
        self.runtime()
        self.script('pi','if [ "$1" = --version ]; then echo 0.85.1; exit 0; fi\nsleep 10')
        result=self.run_script(LMM_COMMAND_TIMEOUT='1')
        self.assertNotEqual(result.returncode,0)
        self.assertIn('timed out',result.stderr)

    def test_download_retries_and_retains_partial_data(self):
        counter=self.root/'tries'
        self.script('curl','printf chunk >> "$LMM_CACHE_ROOT/node-v24.21.0-linux-x64.tar.gz.part"\nprintf x >> "$TEST_COUNTER"\nexit 28')
        self.script('uname','if [ "$1" = -s ]; then echo Linux; else echo x86_64; fi')
        self.script('sleep','exit 0')
        result=self.run_script(TEST_COUNTER=str(counter))
        self.assertNotEqual(result.returncode,0)
        self.assertEqual(counter.read_text(),'xx')
        self.assertEqual(Path(self.env['LMM_CACHE_ROOT'],'node-v24.21.0-linux-x64.tar.gz.part').read_text(),'chunkchunk')
        self.assertIn('rerun to resume',result.stderr)

    def test_checksum_failure_never_extracts_download(self):
        self.script('curl','printf corrupt > "$LMM_CACHE_ROOT/node-v24.21.0-linux-x64.tar.gz.part"\nprintf 200')
        self.script('uname','if [ "$1" = -s ]; then echo Linux; else echo x86_64; fi')
        self.script('sleep','exit 0')
        result=self.run_script()
        self.assertNotEqual(result.returncode,0)
        self.assertIn('Checksum mismatch',result.stderr)
        self.assertFalse(any(Path(self.env['LMM_INSTALL_ROOT']).glob('node-v*')))

    def test_truncated_pipe_input_never_starts_installation(self):
        source=(ROOT/'pi.sh').read_text()
        for text in (source[:len(source)//2],source[:-4]):
            result=subprocess.run([BASH],input=text,env=self.env,capture_output=True,text=True,timeout=5)
            self.assertNotEqual(result.returncode,0)
            self.assertFalse(Path(self.env['LMM_INSTALL_ROOT']).exists())
            self.assertFalse(Path(self.env['LMM_CACHE_ROOT']).exists())

    def test_generated_files_are_reproducible(self):
        for app,package,version in [('pi','@earendil-works/pi-coding-agent','0.85.1'),('dsh','@deepseek-ai/dsh','0.1.5-rc.1')]:
            for extension in ('sh','ps1'):
                expected=(ROOT/'templates'/('installer.'+extension)).read_text().replace('@APP@',app).replace('@PACKAGE@',package).replace('@VERSION@',version)
                self.assertEqual((ROOT/(app+'.'+extension)).read_text(),expected)

if __name__=='__main__':unittest.main()
