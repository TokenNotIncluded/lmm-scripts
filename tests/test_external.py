"""Distribution routing, official delegation and asset contracts; no real downloads."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

P=Path(__file__).resolve().parents[1]
FAKE=r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
name=Path(sys.argv[0]).name; args=sys.argv[1:]
with open(os.environ['TEST_LOG'],'a') as f: f.write(json.dumps([name,args])+'\n')
if name=='uname': print(os.environ.get('TEST_OS','Linux') if '-s' in args else os.environ.get('TEST_ARCH','x86_64'))
elif name=='realpath': print(os.path.realpath(args[-1]))
elif name=='ldd': print(os.environ.get('TEST_LIBC','glibc'))
elif name=='curl':
    out=Path(args[args.index('-o')+1])
    if os.environ.get('TEST_FAIL'):
        out.write_text('touch "'+os.environ['TEST_MARKER']+'"\n'); sys.exit(18)
    tool='codex' if any('chatgpt.com/codex/' in a for a in args) else 'claude'
    out.write_text('#!/bin/bash\nset -eu\nprintf "%s\\n" "$@" > "$TEST_ARGS"\nmkdir -p "$HOME/.local/bin"\nprintf "#!/bin/sh\\necho version-ok\\n" > "$HOME/.local/bin/TOOL"\nchmod +x "$HOME/.local/bin/TOOL"\n'.replace('TOOL',tool))
elif name=='proot-distro': print('guest-ok')
elif name in ('apk','apt-get','dnf','yum','pacman','zypper','xbps-install','rg'): sys.exit(0)
else: sys.exit(2)
'''

class ExternalTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(); self.base=Path(self.tmp.name)
        self.fake=self.base/'bin'; self.fake.mkdir(); (self.base/'home').mkdir()
        self.log=self.base/'calls'; self.log.write_text('')
        self.release=self.base/'os-release'
        for name in ('uname','realpath','ldd','curl','proot-distro','apk','apt-get','dnf','pacman','zypper','xbps-install','rg'):
            p=self.fake/name; p.write_text(FAKE); p.chmod(0o755)
        self.env=dict(os.environ,HOME=str(self.base/'home'),TMPDIR=str(self.base),PATH=str(self.fake)+os.pathsep+os.environ['PATH'],TERMUX_VERSION='',TERMUX_APP__PACKAGE_NAME='',PREFIX='',LMM_OS_RELEASE=str(self.release),LMM_INSTALL_ROOT=str(self.base/'tools'),TEST_LOG=str(self.log),TEST_MARKER=str(self.base/'bad'),TEST_ARGS=str(self.base/'args'))
        for key in ('CODEX_INSTALL_DIR','CODEX_HOME','LMM_PROOT_DISTRO'): self.env.pop(key,None)
        self.code='\n'.join((P/'templates/lib'/f).read_text(encoding='utf-8') for f in ('termux.sh','quote.sh','external.sh'))

    def tearDown(self): self.tmp.cleanup()

    def run_tool(self,target,*args,distro='ubuntu',**env):
        self.release.write_text(f'ID={distro}\nVERSION="24.04.5 LTS (Noble Numbat)"\nNAME="Fixture Linux"\n')
        return subprocess.run(['bash','-c',self.code+'\nTARGET=$1; shift; lmm_external_main "$@"','test',target,*args],env=self.env|env,text=True,capture_output=True,timeout=30)

    def calls(self): return [json.loads(x) for x in self.log.read_text().splitlines()]

    def test_cli_distro_matrix_without_node_or_package_installs(self):
        for distro in ('ubuntu','debian','fedora','rocky','opensuse-leap','arch','alpine','void'):
            for target in ('codex','claude-code'):
                with self.subTest(distro=distro,target=target):
                    r=self.run_tool(target,'--dry-run',distro=distro)
                    self.assertEqual(r.returncode,0,r.stderr); self.assertIn('official:https:',r.stdout)
                    if distro=='alpine': self.assertIn('libc:musl',r.stdout)
        self.assertFalse(any(name=='curl' for name,_ in self.calls()))
        self.assertFalse((self.base/'tools').exists())

    def test_linux_and_macos_delegate_to_official_cli_installer(self):
        for target in ('codex','claude-code'):
            for osname in ('Linux','Darwin'):
                r=self.run_tool(target,'--update','--version','1.2.3',TEST_OS=osname)
                self.assertEqual(r.returncode,0,r.stderr); self.assertIn('version-ok',r.stdout)
                expected=['--release','1.2.3'] if target=='codex' else ['1.2.3']
                self.assertEqual((self.base/'args').read_text().splitlines(),expected)
        self.assertFalse((self.base/'home/.claude.json').exists())

    def test_claude_explicit_latest_is_not_replaced_by_stable(self):
        r=self.run_tool('claude-code','--version','latest'); self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual((self.base/'args').read_text().strip(),'latest')

    def test_os_release_does_not_override_tool_version(self):
        for target, expected in [('codex', ['--release', 'latest']), ('claude-code', ['stable'])]:
            r=self.run_tool(target, '--update')
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual((self.base/'args').read_text().splitlines(), expected)
        r=self.run_tool('codex', '--version', '1.2.3')
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual((self.base/'args').read_text().splitlines(), ['--release', '1.2.3'])

    def test_partial_upstream_script_is_not_executed(self):
        r=self.run_tool('codex',TEST_FAIL='1'); self.assertNotEqual(r.returncode,0)
        self.assertFalse((self.base/'bad').exists()); self.assertFalse((self.base/'home/.local/bin/codex').exists())

    def test_check_is_read_only_and_does_not_download(self):
        r=self.run_tool('codex','--check'); self.assertNotEqual(r.returncode,0)
        self.assertFalse(any(n=='curl' for n,_ in self.calls())); self.assertFalse((self.base/'tools').exists())

    def test_termux_routes_cli_to_existing_proot_guest(self):
        for target in ('codex','claude-code'):
            r=self.run_tool(target,'--dry-run','--distro','my-linux',TERMUX_VERSION='test')
            self.assertEqual(r.returncode,0,r.stderr); self.assertIn('proot:my-linux',r.stdout)

    def test_termux_launch_keeps_working_directory_and_arguments(self):
        r=self.run_tool('codex','--launch','--','two words','--help',TERMUX_VERSION='test')
        self.assertEqual(r.returncode,0,r.stderr)
        launcher=self.base/'tools/bin/codex'
        self.assertTrue(launcher.exists()); self.assertNotIn('/usr/bin/env',launcher.read_text())
        calls=[args for name,args in self.calls() if name=='proot-distro']
        self.assertIn('--work-dir',calls[-1]); self.assertEqual(calls[-1][-2:],['two words','--help'])
        self.assertFalse(any(args and args[0] in ('install','reset','remove') for args in calls))

    def test_termux_desktop_tools_fail_before_downloading(self):
        for target in ('cc-switch','clash-verge-rev'):
            r=self.run_tool(target,'--dry-run',TERMUX_VERSION='test')
            self.assertNotEqual(r.returncode,0); self.assertIn('Termux is not supported',r.stderr)
        self.assertFalse(any(n=='curl' for n,_ in self.calls()))

    def test_desktop_package_manager_matrix(self):
        for distro,expected in [('ubuntu','apt:deb'),('debian','apt:deb'),('fedora','dnf-or-yum:rpm'),('opensuse','zypper:rpm'),('arch','paru-or-yay:AUR')]:
            for target in ('cc-switch','clash-verge-rev'):
                r=self.run_tool(target,'--dry-run',distro=distro)
                self.assertEqual(r.returncode,0,r.stderr); self.assertIn(expected,r.stdout)
        self.assertIn('AppImage',self.run_tool('cc-switch','--dry-run',distro='gentoo').stdout)
        self.assertNotEqual(self.run_tool('clash-verge-rev','--dry-run',distro='gentoo').returncode,0)

    def test_release_architecture_and_signature_filtering(self):
        cases=[('cc-switch','linux','x64','deb','CC-Switch-v3.20.3-Linux-x86_64.deb'),('cc-switch','linux','arm64','rpm','CC-Switch-v3.20.3-Linux-arm64.rpm'),('cc-switch','darwin','arm64','dmg','CC-Switch-v3.20.3-macOS.dmg'),('clash-verge-rev','linux','x64','deb','Clash.Verge_2.5.2_amd64.deb'),('clash-verge-rev','linux','arm64','rpm','Clash.Verge-2.5.2-1.aarch64.rpm'),('clash-verge-rev','darwin','x64','dmg','Clash.Verge_2.5.2_x64.dmg')]
        for target,osname,arch,ext,asset in cases:
            r=subprocess.run(['bash','-c',self.code+'\nlmm_desktop_pattern "$@"','test',target,osname,arch,ext],capture_output=True,text=True,check=True)
            pattern=r.stdout.strip(); self.assertRegex(asset,pattern); self.assertIsNone(re.search(pattern,asset+'.sig'))

    def test_invalid_arguments_and_32bit_fail(self):
        for args in [('--version',';touch-bad'),('--distro','../guest'),('--network','invalid'),('--root','/'),('--root',)]:
            self.assertNotEqual(self.run_tool('codex',*args).returncode,0)
        self.assertNotEqual(self.run_tool('codex','--dry-run',TEST_ARCH='armv7l').returncode,0)
        self.assertFalse(any(n=='curl' for n,_ in self.calls()))

    def test_alpine_claude_update_keeps_nonrecursive_launcher(self):
        for _ in range(2):
            r=self.run_tool('claude-code','--update',distro='alpine'); self.assertEqual(r.returncode,0,r.stderr)
        body=(self.base/'tools/bin/claude').read_text()
        self.assertIn('USE_BUILTIN_RIPGREP=0',body)
        self.assertIn(str(self.base/'home/.local/bin/claude'),body)
        self.assertNotIn(str(self.base/'tools/bin/claude'),body)

if __name__=='__main__': unittest.main(verbosity=2)
