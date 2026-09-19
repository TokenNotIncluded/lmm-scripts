import hashlib,io,json,os,subprocess,tarfile,tempfile,unittest,shutil,time
from pathlib import Path
P=Path(__file__).resolve().parents[1]
FAKE=r'''#!/usr/bin/env python3
import sys,os,json,shutil
from pathlib import Path
name=Path(sys.argv[0]).name;a=sys.argv[1:]
with open(os.environ['LMM_TEST_LOG'],'a') as f:f.write(json.dumps([name,a])+'\n')
if name=='uname':print('Linux' if '-s' in a else 'x86_64')
elif name=='node':
 if a and a[0]=='-':os.execv(os.environ['LMM_TEST_REAL_NODE'],[os.environ['LMM_TEST_REAL_NODE']]+a)
 if '-e' in a:sys.exit(0 if os.environ.get('LMM_TEST_NODE_OK','1')=='1' else 1)
 print('v24.21.0')
elif name=='curl':
 if '-ILs' in a:
  print('200 0.01');sys.exit(0)
 out=Path(a[a.index('--output')+1]);mode=os.environ.get('LMM_TEST_TRANSFER','ok')
 if mode=='fail':sys.exit(7)
 data=Path(os.environ['LMM_TEST_ARCHIVE']).read_bytes()
 if mode=='corrupt':out.write_bytes(b'corrupt');sys.exit(0)
 if mode=='resume' and not out.exists():out.write_bytes(data[:len(data)//2]);sys.exit(18)
 if mode=='resume':
  with open(os.environ['LMM_TEST_LOG'],'a') as f:f.write(json.dumps(['resumed',out.stat().st_size])+'\n')
 out.write_bytes(data)
elif name=='npm':
 if '--help' in a:print('--allow-scripts');sys.exit(0)
 if a[:2]==['config','get']:
  print('https://registry.npmjs.org/' if a[-1]=='registry' else os.environ['LMM_TEST_CACHE']);sys.exit(0)
 if os.environ.get('LMM_TEST_NPM_FAIL')=='1':sys.exit(9)
 if os.environ.get('LMM_TEST_NPM_SLEEP'):__import__('time').sleep(int(os.environ['LMM_TEST_NPM_SLEEP']))
 prefix=Path(a[a.index('--prefix')+1]);cmd='pi' if any('@earendil-works/pi-coding-agent@' in x for x in a) else ('pnpm' if any(x.startswith('pnpm@') for x in a) else 'dsh')
 (prefix/'bin').mkdir(parents=True,exist_ok=True)
 body='#!/usr/bin/env bash\nprintf "%s\\n" "'+cmd+' 0.1"\nif [ "${LMM_TEST_PLUGIN_FAIL:-0}" = 1 ] && [ "${1:-}" != --version ]; then exit 8; fi\n'
 f=prefix/'bin'/cmd;f.write_text(body);f.chmod(0o755)
else:sys.exit(4)
'''
class InstallerTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.base=Path(self.tmp.name);self.root=self.base/"install space's path";self.bin=self.base/'fake';self.bin.mkdir();self.log=self.base/'calls.jsonl';self.log.write_text('')
  for name in ['curl','uname','node','npm']:
   f=self.bin/name;f.write_text(FAKE);f.chmod(0o755)
  self.archive=self.base/'fixture.tar.gz'
  with tarfile.open(self.archive,'w:gz') as t:
   data=b'#!/usr/bin/env bash\necho "lmm 0.1.0"\n';x=tarfile.TarInfo('lmm');x.size=len(data);x.mode=0o755;t.addfile(x,io.BytesIO(data))
  self.env=dict(os.environ,PATH=str(self.bin)+os.pathsep+os.environ['PATH'],LMM_TEST_REAL_NODE=shutil.which('node'),LMM_TEST_LOG=str(self.log),LMM_TEST_ARCHIVE=str(self.archive),LMM_TEST_CACHE=str(self.base/'npm-cache'))
  for k in list(self.env):
   if k.lower().startswith('npm_config_'):self.env.pop(k)
 def tearDown(self):self.tmp.cleanup()
 def run_script(self,target,*args,env=None,fixture=False):
  script=P/(target+'.sh')
  if fixture:
   body=script.read_text();v=json.loads((P/'versions.json').read_text());body=body.replace(v['lmm_sha256']['linux-x64'],hashlib.sha256(self.archive.read_bytes()).hexdigest());body=body.replace(v['dsh_provider_sha256'],hashlib.sha256(self.archive.read_bytes()).hexdigest());script=self.base/(target+'.sh');script.write_text(body)
  return subprocess.run(['bash',str(script),'--root',str(self.root),'--no-path','--network','official',*args],env=self.env|dict(env or {}),text=True,capture_output=True,timeout=15)
 def calls(self):return [json.loads(x) for x in self.log.read_text().splitlines()]
 def test_help_and_check_make_no_installation(self):
  self.assertEqual(self.run_script('pi','--help').returncode,0);self.assertFalse(self.root.exists())
  self.assertIn(self.run_script('pi','--check').returncode,[0,1]);self.assertFalse(self.root.exists())
  self.assertFalse(any(x[0]=='curl' for x in self.calls()))
 def test_unknown_option_and_profile_refused(self):
  self.assertNotEqual(self.run_script('dsh','--profile','../../bad').returncode,0)
  self.assertNotEqual(self.run_script('pi','--surprise').returncode,0);self.assertFalse(self.root.exists())
 def test_install_and_reinstall_reuse_client_and_quoted_launcher(self):
  first=self.run_script('pi');self.assertEqual(first.returncode,0,first.stderr)
  version=subprocess.run([str(self.root/'bin/pi'),'--version'],env=self.env,text=True,capture_output=True);self.assertEqual(version.returncode,0,version.stderr)
  self.log.write_text('');second=self.run_script('pi');self.assertEqual(second.returncode,0,second.stderr)
  self.assertFalse(any(x[0]=='npm' and 'install' in x[1] for x in self.calls()))
  self.assertFalse((self.root/'.setup-lock').exists())
 def test_plugin_failure_does_not_replace_old_launcher(self):
  first=self.run_script('pi');self.assertEqual(first.returncode,0,first.stderr);before=(self.root/'bin/pi').read_bytes()
  failed=self.run_script('pi','--update',env={'LMM_TEST_PLUGIN_FAIL':'1'});self.assertNotEqual(failed.returncode,0)
  self.assertEqual(before,(self.root/'bin/pi').read_bytes());self.assertFalse((self.root/'.setup-lock').exists())
 def test_active_lock_keeps_foreign_owner(self):
  lock=self.root/'.setup-lock';lock.mkdir(parents=True);(lock/'pid').write_text(str(os.getpid()));(lock/'owner').write_text('lmm-installer-v1\n')
  failed=self.run_script('pi');self.assertNotEqual(failed.returncode,0);self.assertTrue((lock/'pid').exists())
  self.assertFalse(any(x[0]=='curl' for x in self.calls()))
 def test_download_hash_failure_never_installs(self):
  result=self.run_script('lmm',env={'LMM_TEST_TRANSFER':'corrupt'},fixture=True)
  self.assertNotEqual(result.returncode,0);self.assertIn('Checksum mismatch',result.stderr);self.assertFalse((self.root/'bin/lmm').exists())
 def test_partial_download_resumes_and_verified_cache_is_reused(self):
  result=self.run_script('lmm',env={'LMM_TEST_TRANSFER':'resume'},fixture=True);self.assertEqual(result.returncode,0,result.stderr)
  self.assertTrue(any(x[0]=='resumed' and x[1]>0 for x in self.calls()))
  self.log.write_text('');result=self.run_script('lmm',env={'LMM_TEST_TRANSFER':'fail'},fixture=True)
  self.assertEqual(result.returncode,0,result.stderr);self.assertFalse(any(x[0]=='curl' for x in self.calls()))
 def test_dsh_profile_and_verified_package(self):
  result=self.run_script('dsh','--profile','headless',fixture=True);self.assertEqual(result.returncode,0,result.stderr)
  self.assertTrue((self.root/'bin/dsh').exists())
 def test_timeout_and_legacy_flags(self):
  start=time.monotonic();r=self.run_script('pi',env={'LMM_COMMAND_TIMEOUT':'1','LMM_TEST_NPM_SLEEP':'10'})
  self.assertNotEqual(r.returncode,0);self.assertLess(time.monotonic()-start,7);self.assertIn('timed out',r.stderr);self.assertFalse((self.root/'bin/pi').exists())
  r=self.run_script('pi','--no-bootstrap');self.assertNotEqual(r.returncode,0)
  r=self.run_script('pi',env={'LMM_RETRIES':'0'});self.assertNotEqual(r.returncode,0)
 def test_truncated_pipe_never_runs_prefix(self):
  body=(P/'pi.sh').read_text().split('if true; then')[0]
  r=subprocess.run(['bash','-s','--','--root',str(self.root),'--no-path'],input=body,env=self.env,text=True,capture_output=True)
  self.assertFalse(self.root.exists());self.assertEqual(self.calls(),[])
 def test_custom_cache_registry_and_mirror_validation(self):
  cache=self.base/'separate cache';r=self.run_script('lmm',env={'LMM_CACHE_ROOT':str(cache)},fixture=True)
  self.assertEqual(r.returncode,0,r.stderr);self.assertTrue(list(cache.glob('*.tar.gz')))
  r=self.run_script('pi',env={'LMM_NODE_BASE_URL':'http://bad.invalid'});self.assertNotEqual(r.returncode,0)
  r=self.run_script('pi',env={'LMM_NPM_REGISTRY':'https://user:secret@bad.invalid'});self.assertNotEqual(r.returncode,0)
 def test_generated_files_match_templates(self):
  subprocess.run(['python3',str(P/'tools/generate.py'),'--check'],check=True)
 def test_usage_preserves_preview_exit_code(self):
  (self.root/'bin').mkdir(parents=True);f=self.root/'bin/lmm';f.write_text('#!/bin/sh\nexit 3\n');f.chmod(0o755)
  r=subprocess.run(['bash',str(P/'lmm-use.sh'),'plan','pi'],env=self.env|{'LMM_INSTALL_ROOT':str(self.root)},capture_output=True,text=True)
  self.assertEqual(r.returncode,3)
if __name__=='__main__':unittest.main(verbosity=2)
