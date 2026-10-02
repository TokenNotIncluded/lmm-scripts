"""Offline installer contracts: never install packages or contact providers."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
NATIVE = {'cursor-cli': ('https://cursor.com/install', []),
          'grok-build': ('https://x.ai/cli/install.sh', []),
          'kimi': ('https://code.kimi.com/kimi-code/install.sh', []),
          'hermes': ('https://hermes-agent.nousresearch.com/install.sh', ['--skip-setup']),
          'openclaw': ('https://openclaw.ai/install.sh', ['--no-onboard']),
          'aider': ('https://aider.chat/install.sh', []),
          'uv': ('https://astral.sh/uv/install.sh', [])}
NPM = {'gemini': '@google/gemini-cli', 'qwen-code': '@qwen-code/qwen-code', 'codebuddy': '@tencent-ai/codebuddy-code'}
ALL = [*NATIVE, *NPM, 'astrbot', 'cursor', 'cherry-studio', 'ollama']
STUB = r'''import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ['LOG'], 'a') as f: f.write(json.dumps([name, args])+'\n')
if name == 'curl':
    if os.environ.get('FAIL_DOWNLOAD'):
        print('touch "$HOME/partial-executed"'); sys.exit(18)
    url = next(a for a in args if a.startswith('https://'))
    if '-o' in args: Path(args[args.index('-o')+1]).write_bytes(b'fixture')
    elif 'api/download' in url:
        host = 'evil.invalid' if os.environ.get('FOREIGN') else 'downloads.cursor.com'
        print(json.dumps({k: 'https://'+host+'/package' for k in ['downloadUrl','debUrl','rpmUrl']}))
    elif 'releases/latest' in url:
        base = 'https://evil.invalid/' if os.environ.get('FOREIGN') else 'https://github.com/CherryHQ/cherry-studio/releases/download/v1/'
        assets = [{'name': f'Cherry-Studio{cn}-1-linux-{arch}.{ext}', 'browser_download_url': base+'package'} for cn in ['', '-CN'] for arch in ['x64','arm64'] for ext in ['deb','rpm','AppImage']]
        print(json.dumps({'assets': [] if os.environ.get('NO_ASSET') else assets}))
    else:
        print('printf "%s\\n" "$@" > "$HOME/upstream-args"\nexit '+os.environ.get('INSTALL_EXIT','0'))
elif name == 'sudo': os.execvp(args[0],args)
elif name == 'uname': print(os.environ.get('OS_NAME','Linux') if '-s' in args else os.environ.get('ARCH','x86_64'))
elif name == 'brew' and args[0] == 'list': sys.exit(int(os.environ.get('BREW_MISSING','1')))
elif name == 'npm': sys.exit(int(os.environ.get('NPM_EXIT','0')))
else: sys.exit(int(os.environ.get('COMMAND_EXIT','0')))
'''

class ToolsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.home = Path(self.temp.name)
        self.bin = self.home/'bin'; self.bin.mkdir()
        self.log = self.home/'log'; self.log.touch()
        for name in ['bash','sh','mkdir','dirname','mktemp','rm','install','jq']:
            os.symlink(shutil.which(name), self.bin/name)
        for name in ['sudo','curl','uname','brew','npm','node','uv','astrbot','cursor-agent','grok','kimi','hermes','openclaw','aider','gemini','qwen','codebuddy']:
            self.stub(name)
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin), LOG=str(self.log))
        for key in ['TERMUX_VERSION','PREFIX']: self.env.pop(key,None)

    def tearDown(self): self.temp.cleanup()

    def stub(self,name):
        path=self.bin/name; path.write_text('#!'+sys.executable+'\n'+STUB); path.chmod(0o755)

    def run_tool(self,name,*args,**env):
        self.log.write_text('')
        return subprocess.run([shutil.which('bash'),str(ROOT/(name+'.sh')),*args],env=self.env|env,capture_output=True,text=True,timeout=10)

    def calls(self): return [json.loads(s) for s in self.log.read_text().splitlines()]

    def test_native_installers_skip_configuration_and_propagate_failures(self):
        for name,(url,args) in NATIVE.items():
            with self.subTest(name=name):
                result=self.run_tool(name)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertIn(url,self.calls()[0][1])
                self.assertEqual((self.home/'upstream-args').read_text().split(),args)
                self.assertEqual(self.run_tool(name,INSTALL_EXIT='9').returncode,9)
                self.assertEqual(self.run_tool(name,FAIL_DOWNLOAD='1').returncode,18)
                self.assertFalse((self.home/'partial-executed').exists())

    def test_setup_never_downloads_or_installs(self):
        setups={'cursor-cli':['cursor-agent',['login']], 'grok-build':['grok',['login']], 'kimi':['kimi',[]], 'hermes':['hermes',['setup']], 'openclaw':['openclaw',['onboard']], 'aider':['aider',[]], 'gemini':['gemini',[]], 'qwen-code':['qwen',[]], 'codebuddy':['codebuddy',[]]}
        for name,expected in setups.items():
            self.assertEqual(self.run_tool(name,'setup').returncode,0)
            self.assertEqual(self.calls(),[expected])
            self.assertEqual(self.run_tool(name,'setup',COMMAND_EXIT='7').returncode,7)

    def test_npm_packages_and_failure_propagation(self):
        for name,package in NPM.items():
            self.assertEqual(self.run_tool(name).returncode,0)
            self.assertEqual(self.calls()[-1],['npm',['install','-g',package+'@latest']])
            self.assertEqual(self.run_tool(name,NPM_EXIT='9').returncode,9)
            self.assertEqual(self.run_tool(name,COMMAND_EXIT='8').returncode,8)
            self.assertFalse(any(call[0]=='npm' for call in self.calls()))
        (self.bin/'npm').unlink()
        for name in NPM:
            self.assertNotEqual(self.run_tool(name).returncode,0)
            self.assertFalse(any(call[0]=='npm' for call in self.calls()))

    def test_astrbot_requires_explicit_directory_and_uses_uv_upgrade(self):
        self.assertEqual(self.run_tool('astrbot').returncode,0)
        self.assertEqual(self.calls(),[['uv',['tool','install','--upgrade','astrbot','--python','3.12']]])
        self.assertEqual(self.run_tool('astrbot','setup').returncode,2)
        self.assertEqual(self.calls(),[])
        instance=self.home/'instance with spaces'; instance.mkdir(); (instance/'existing').write_text('keep')
        self.assertEqual(self.run_tool('astrbot','setup',str(instance)).returncode,0)
        self.assertEqual(self.calls(),[['astrbot',['init']]])
        self.assertEqual((instance/'existing').read_text(),'keep')
        self.assertEqual(self.run_tool('astrbot','setup',str(instance),COMMAND_EXIT='6').returncode,6)
        (instance/'data').mkdir(); (instance/'data'/'config.json').write_text('keep')
        self.assertEqual(self.run_tool('astrbot','setup',str(instance)).returncode,0)
        self.assertEqual(self.calls(),[])
        self.assertEqual((instance/'data'/'config.json').read_text(),'keep')

    def test_desktop_assets_architecture_and_foreign_urls(self):
        for name in ['cursor','cherry-studio']:
            for arch in ['x86_64','aarch64']:
                result=self.run_tool(name,ARCH=arch)
                self.assertEqual(result.returncode,0,result.stderr)
                self.assertTrue((self.home/'.local/bin'/name).exists())
            for env in [{'FOREIGN':'1'}, {'FAIL_DOWNLOAD':'1'}]:
                self.assertNotEqual(self.run_tool(name,**env).returncode,0)
                self.assertFalse(any('-o' in args for _,args in self.calls()))
            self.stub('apt-get')
            self.assertEqual(self.run_tool(name).returncode,0)
            self.assertEqual(self.calls()[-1][0],'apt-get')
            self.assertEqual(self.run_tool(name,COMMAND_EXIT='9').returncode,9)
            (self.bin/'apt-get').unlink()
        self.assertNotEqual(self.run_tool('cherry-studio',NO_ASSET='1').returncode,0)

    def test_macos_desktop_and_ollama_install_update(self):
        for name in ['cursor','cherry-studio','ollama']:
            for missing,action in [('1','install'),('0','upgrade')]:
                self.assertEqual(self.run_tool(name,OS_NAME='Darwin',BREW_MISSING=missing).returncode,0)
                self.assertEqual(self.calls()[-1],['brew',[action,*(['--cask'] if name!='ollama' else []),name]])
        self.assertEqual(self.run_tool('ollama',INSTALL_EXIT='7').returncode,7)

    def test_help_and_invalid_actions_do_not_mutate(self):
        for name in ALL:
            self.assertEqual(self.run_tool(name,'help').returncode,0)
            self.assertEqual(self.calls(),[])
            self.assertNotEqual(self.run_tool(name,'--network','china').returncode,0)
            self.assertEqual(self.calls(),[])
            self.assertNotEqual(self.run_tool(name,'install','unexpected').returncode,0)
            self.assertEqual(self.calls(),[])

    def test_unsupported_termux_native_entries_stop_before_download(self):
        for name in [*NATIVE,'cursor','cherry-studio','ollama']:
            self.assertNotEqual(self.run_tool(name,TERMUX_VERSION='test').returncode,0)
            self.assertEqual(self.calls(),[])

    def test_menu_entries_have_both_platforms_and_preserve_original_numbers(self):
        code=(ROOT/'menu.sh').read_text().split('while true; do')[0]+'printf "%s\\n" "${tools[@]}"\n'
        result=subprocess.run([shutil.which('bash'),'-c',code],env=self.env,text=True,capture_output=True)
        entries=result.stdout.splitlines()
        self.assertEqual(entries[:9],['pi','dsh','lmm','codex','claude-code','cc-switch','clash-verge-rev','codewhale','opencode'])
        self.assertEqual(set(entries[9:]),set(ALL))
        for name in ALL:
            self.assertTrue((ROOT/(name+'.sh')).is_file()); self.assertTrue((ROOT/(name+'.ps1')).is_file())
            self.assertIn("'"+name+"'",(ROOT/'menu.ps1').read_text())

if __name__=='__main__': unittest.main(verbosity=2)
