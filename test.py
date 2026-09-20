"""Offline command-contract tests. No packages are installed."""
import json
import os
from pathlib import Path
import sys
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
STUB = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['LOG'], 'a') as f:
    f.write(json.dumps([name, args]) + '\n')
if name == 'curl':
    if os.environ.get('FAIL_DOWNLOAD'):
        print('touch "$HOME/should-not-exist"')
        sys.exit(18)
    url = next(a for a in args if a.startswith('https://'))
    if '/codex/install.sh' in url or url == 'https://claude.ai/install.sh':
        print('printf "%s\\n" "$@" > "$HOME/received-args"')
    elif url.endswith('/desktop.sh'):
        print(Path(os.environ['PROJECT'], 'desktop.sh').read_text())
    elif '/releases/latest' in url:
        print(json.dumps({'assets': [] if os.environ.get('NO_ASSET') else [
            {'name': 'Tool-amd64.deb', 'browser_download_url': 'https://github.com/official/tool.deb'},
            {'name': 'Tool-amd64.deb.sig', 'browser_download_url': 'https://github.com/official/tool.deb.sig'},
            {'name': 'Tool-aarch64.rpm', 'browser_download_url': 'https://github.com/official/arm64.rpm'},
            {'name': 'Tool-x86_64.rpm', 'browser_download_url': 'https://github.com/official/x64.rpm'},
            {'name': 'Tool-armhfp.rpm', 'browser_download_url': 'https://github.com/official/armv7.rpm'},
            {'name': 'Tool-x86_64.AppImage', 'browser_download_url': 'https://github.com/official/tool.AppImage'},
        ]}))
    elif '-o' in args:
        Path(args[args.index('-o')+1]).write_bytes(b'fixture')
    else: sys.exit(7)
elif name == 'uname': print(os.environ.get('OS_NAME','Linux') if '-s' in args else os.environ.get('ARCH','x86_64'))
elif name == 'jq':
    os.execv(os.environ['REAL_JQ'], ['jq', *args])
elif name == 'brew' and args[0] == 'list': sys.exit(int(os.environ.get('BREW_MISSING','1')))
elif name == 'tar':
    dest=Path(args[args.index('-C')+1], 'lmm')
    dest.write_text('#!/bin/sh\nexit '+os.environ.get('BINARY_EXIT','0')+'\n'); dest.chmod(0o755)
elif name == 'proot-distro':
    # Record the actual guest invocation; do not fake an Android binary.
    sys.exit(0)
elif name == 'npm': sys.exit(int(os.environ.get('NPM_EXIT','0')))
elif name == 'sudo': os.execvp(args[0],args)
else: sys.exit(int(os.environ.get('COMMAND_EXIT','0')))
'''

class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.bin = self.home/'bin'
        self.bin.mkdir()
        self.log = self.home/'commands.jsonl'
        self.log.touch()
        # Keep host package managers out of simulated platform tests.
        for name in ('bash','sh','dirname','mktemp','rm','mkdir','install'):
            os.symlink(shutil.which(name), self.bin/name)
        for name in ('curl','npm','pi','dsh','uname','jq','tar','proot-distro','brew','cargo','sudo'):
            self.stub(name)
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin), LOG=str(self.log), PROJECT=str(ROOT), REAL_JQ=shutil.which('jq'))
        for key in ('TERMUX_VERSION','PREFIX','LMM_DISTRO'):
            self.env.pop(key,None)

    def tearDown(self):
        self.tmp.cleanup()

    def stub(self,name):
        path=self.bin/name
        path.write_text(STUB.replace('#!/usr/bin/env python3', '#!'+sys.executable))
        path.chmod(0o755)

    def run_script(self,name,*args,**env):
        return subprocess.run([shutil.which('bash'),str(ROOT/name),*args],env=self.env|env,text=True,capture_output=True,timeout=10)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_pi_and_dsh_keep_official_commands_and_lmm_plugins(self):
        self.assertEqual(self.run_script('pi.sh').returncode,0)
        calls=self.calls()
        self.assertIn('--ignore-scripts', calls[0][1])
        self.assertEqual(calls[1],['pi',['install','npm:@tokennotincluded/pi-lmm-provider@0.1.0-alpha.1']])
        self.assertEqual(self.run_script('dsh.sh','headless').returncode,0)
        self.assertEqual(self.calls()[-1][1][:3],['plugin','--profile','headless'])

    def test_npm_failure_never_installs_plugin(self):
        for script in ('pi.sh','dsh.sh'):
            self.assertEqual(self.run_script(script,NPM_EXIT='9').returncode,9)
        self.assertTrue(all(name=='npm' for name,_ in self.calls()))

    def test_removed_flags_fail_instead_of_silently_installing(self):
        for script in ('pi.sh','dsh.sh','cc-switch.sh','clash-verge-rev.sh','lmm.sh','menu.sh'):
            self.assertNotEqual(self.run_script(script,'--network','china').returncode,0)
        self.assertEqual(self.calls(),[])

    def test_native_cli_delegates_and_preserves_arguments(self):
        for script,args in [('codex.sh',['--release','1.2.3']),('claude-code.sh',['stable'])]:
            result=self.run_script(script,*args)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual((self.home/'received-args').read_text().splitlines(),args)
        self.assertTrue(all(name=='curl' for name,_ in self.calls()))

    def test_failed_download_does_not_execute_partial_script(self):
        for name in ('codex.sh','claude-code.sh'):
            self.assertNotEqual(self.run_script(name,FAIL_DOWNLOAD='1').returncode,0)
        self.assertFalse((self.home/'should-not-exist').exists())

    def test_termux_uses_guest_and_forwards_upstream_arguments(self):
        for script in ('codex.sh','claude-code.sh'):
            result=self.run_script(script,'stable',TERMUX_VERSION='test',LMM_DISTRO='debian')
            self.assertEqual(result.returncode,0,result.stderr)
            name,args=self.calls()[-1]
            self.assertEqual(name,'proot-distro')
            self.assertEqual(args[:4],['login','debian','--','sh' if script=='codex.sh' else 'bash'])
            self.assertEqual(args[-2:],['--','stable'])

    def test_termux_desktop_rejected_without_download(self):
        for script in ('cc-switch.sh','clash-verge-rev.sh'):
            for env in ({'TERMUX_VERSION':'test'},{'PREFIX':'/data/data/com.termux/files/usr'}):
                result=self.run_script(script,**env)
                self.assertNotEqual(result.returncode,0)
                self.assertIn('Termux',result.stderr)
        self.assertEqual(self.calls(),[])

    def test_macos_delegates_install_and_update_to_homebrew(self):
        for tool in ('cc-switch','clash-verge-rev'):
            for missing,action in [('1','install'),('0','upgrade')]:
                result=self.run_script('desktop.sh',tool,OS_NAME='Darwin',BREW_MISSING=missing)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertEqual(self.calls()[-1],['brew',[action,'--cask',tool]])

    def test_linux_packages_use_native_manager_and_architecture(self):
        for manager,arch,pattern in [('apt-get','x86_64','(amd64|x86_64)\\.deb$'),('dnf','aarch64','(arm64|aarch64)\\.rpm$'),('yum','x86_64','(amd64|x86_64)\\.rpm$'),('zypper','armv7l','(armhf|armhfp|armv7)\\.rpm$')]:
            self.stub(manager)
            result=self.run_script('desktop.sh','clash-verge-rev',ARCH=arch)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(self.calls()[-1][0],manager)
            self.assertIn(pattern,next(args for name,args in reversed(self.calls()) if name=='jq'))
            (self.bin/manager).unlink()

    def test_failed_asset_resolution_does_not_install(self):
        self.stub('apt-get')
        self.assertNotEqual(self.run_script('desktop.sh','cc-switch',NO_ASSET='1').returncode,0)
        self.assertNotIn('apt-get',[name for name,_ in self.calls()])

    def test_appimage_fallback_is_only_for_cc_switch(self):
        result=self.run_script('desktop.sh','cc-switch')
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertTrue((self.home/'.local/bin/cc-switch').exists())
        self.assertNotEqual(self.run_script('desktop.sh','clash-verge-rev').returncode,0)

    def test_lmm_checks_binary_before_replacing_existing_install(self):
        dest=self.home/'.local/bin/lmm'; dest.parent.mkdir(parents=True); dest.write_text('old')
        self.assertNotEqual(self.run_script('lmm.sh',BINARY_EXIT='9').returncode,0)
        self.assertEqual(dest.read_text(),'old')
        self.assertEqual(self.run_script('lmm.sh').returncode,0)
        self.assertNotEqual(dest.read_text(),'old')
        self.assertNotEqual(self.run_script('lmm.sh',TERMUX_VERSION='test').returncode,0)

    def test_single_downloaded_desktop_entry_loads_shared_root_file(self):
        self.stub('apt-get')
        entry=self.home/'cc-switch.sh'
        entry.write_text((ROOT/'cc-switch.sh').read_text())
        result=subprocess.run([shutil.which('bash'),str(entry)],env=self.env,text=True,capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertTrue(any(name=='curl' and any('/desktop.sh' in arg for arg in args) for name,args in self.calls()))

    def test_termux_menu_omits_desktop_entries(self):
        code=(ROOT/'menu.sh').read_text().split('while true; do')[0]+'printf "%s\\n" "${tools[@]}"\n'
        result=subprocess.run([shutil.which('bash'),'-c',code],env=self.env|{'TERMUX_VERSION':'test'},text=True,capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout.splitlines(),['pi','dsh','lmm','codex','claude-code'])

    def test_flat_layout_and_size_budget(self):
        for path in ('templates','tools','docs','versions.json','generate.py'):
            self.assertFalse((ROOT/path).exists())
        scripts=[*ROOT.glob('*.sh'),*(f for f in ROOT.glob('*.ps1') if f.name!='test.ps1')]
        self.assertLess(sum(len(f.read_bytes()) for f in scripts),14000)
        for file in scripts:
            text=file.read_text()
            self.assertNotRegex(text,r'npmmirror|rank_urls|LMM_NETWORK|LMM_RETRIES|LMM_COMMAND_TIMEOUT|configure_npm')
            self.assertNotIn('@MENU_REV@',text)
            self.assertNotIn('@DESKTOP_REV@',text)
        for name in ('codex','claude-code','pi','dsh'):
            self.assertLessEqual(len((ROOT/f'{name}.sh').read_text().splitlines()),10)

if __name__=='__main__':
    unittest.main(verbosity=2)
