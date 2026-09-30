// Real isolated installation and host load. Never logs in or sends paid requests.
import {mkdtemp, mkdir, writeFile, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join, resolve} from 'node:path';
import {spawn, spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
import assert from 'node:assert/strict';
import {npmCli, LAST_TESTED_OPENCODE_VERSION} from './opencode.mjs';
const root = await mkdtemp(join(tmpdir(), 'lmm-opencode-install-'));
const env = {...process.env, OPENCODE_CONFIG_DIR:join(root,'config','opencode'), npm_config_prefix: join(root,'npm'), XDG_CONFIG_HOME:join(root,'config'), XDG_DATA_HOME:join(root,'data'), XDG_STATE_HOME:join(root,'state'), XDG_CACHE_HOME:join(root,'cache'), OPENCODE_DISABLE_DEFAULT_PLUGINS:'true'};
let host;
let logs = '';
try {
  const configPath = join(env.XDG_CONFIG_HOME,'opencode','opencode.jsonc');
  await mkdir(join(env.XDG_CONFIG_HOME,'opencode'), {recursive:true});
  await writeFile(configPath, '{\n// keep user comment\n"provider":{"fixture":{"npm":"@ai-sdk/openai-compatible","models":{}}}\n}\n');
  for (let attempt=0; attempt<2; attempt++) {
    const result = spawnSync(process.execPath, [resolve('opencode.mjs')], {env,stdio:'inherit',timeout:240000});
    assert.equal(result.status,0, `installation ${attempt+1} failed: ${result.error ?? ''}`);
  }
  const config = await readFile(configPath,'utf8');
  assert.ok(config.includes('// keep user comment'));
  assert.equal((config.match(/dist\/index\.js/g)||[]).length,1,'rerun duplicated plugin');
  assert.ok(config.includes('fixture'),'existing provider lost');
  if (process.env.TEST_OPENCODE_BASELINE === 'true') {
    const install = spawnSync(process.execPath,[npmCli(),'install','--global','--no-audit','--no-fund','--registry=https://registry.npmjs.org',`opencode-ai@${LAST_TESTED_OPENCODE_VERSION}`],{env,stdio:'inherit',timeout:240000});
    assert.equal(install.status,0,'baseline host installation failed');
  }
  const packageDir = process.platform === 'win32' ? join(root,'npm','node_modules','opencode-ai') : join(root,'npm','lib','node_modules','opencode-ai');
  const metadata = JSON.parse(await readFile(join(packageDir,'package.json'),'utf8'));
  const executable = resolve(packageDir, typeof metadata.bin === 'string' ? metadata.bin : metadata.bin.opencode);
  const argsPrefix = [];
  const version = spawnSync(executable,['--version'],{env,encoding:'utf8',timeout:15000});
  assert.equal(version.status,0);
  assert.match(version.stdout.trim(), /^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$/);
  if (process.env.TEST_OPENCODE_BASELINE === 'true') assert.equal(version.stdout.trim(),LAST_TESTED_OPENCODE_VERSION);
  const socket = createServer();
  await new Promise(resolve=>socket.listen(0,'127.0.0.1',resolve));
  const port = socket.address().port;
  await new Promise(resolve=>socket.close(resolve));
  host=spawn(executable,[...argsPrefix,'serve','--hostname','127.0.0.1','--port',String(port)],{env,cwd:root});
  host.stdout.on('data',chunk=>{logs+=chunk});host.stderr.on('data',chunk=>{logs+=chunk});
  const endpoint=`http://127.0.0.1:${port}`;
  const start=Date.now();
  while(true) {
    if(host.exitCode!==null)throw new Error(`host exited: ${logs.slice(-3000)}`);
    try{const response=await fetch(endpoint+'/global/health',{signal:AbortSignal.timeout(1500)});if(response.ok)break;}catch{}
    if(Date.now()-start>90000)throw new Error(`host startup timed out: ${logs.slice(-3000)}`);
    await new Promise(resolve=>setTimeout(resolve,200));
  }
  const methods=await fetch(endpoint+'/provider/auth',{signal:AbortSignal.timeout(90000)}).then(response=>response.json());
  assert.deepEqual(methods.lmm,[{type:'oauth',label:'Sign in with LMM (OAuth)'}]);
  const loaded=await fetch(endpoint+'/config',{signal:AbortSignal.timeout(90000)}).then(response=>response.json());
  assert.equal(loaded.provider.lmm.options.baseURL,'https://api.lmm.best/v1');
  assert.ok(loaded.provider.fixture);
  console.log('Real installation, repeat installation, config preservation and native OpenCode OAuth registration passed. No login or inference performed.');
} finally {
  if(host&&host.exitCode===null){host.kill('SIGTERM');await Promise.race([new Promise(resolve=>host.once('exit',resolve)),new Promise(resolve=>setTimeout(resolve,3000))]);if(host.exitCode===null)host.kill('SIGKILL');}
  await rm(root,{recursive:true,force:true});
}
