import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync, symlinkSync, realpathSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, delimiter } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { parseArguments, npmCLI, parseModels, selectModel, nativeHost, command, PROVIDER_URL, PROVIDER_REV } from './codewhale.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const id = 'lmm:ZGVmYXVsdA:bW9kZWw';
const other = 'lmm:YW5vdGhlcg:bW9kZWw';
function fixture(t) {
  const home = mkdtempSync(join(tmpdir(), 'lmm scripts space-'));
  t.after(() => rmSync(home, { recursive: true, force: true }));
  const bin = join(home, 'bin');
  const root = join(home, 'global modules');
  const log = join(home, 'calls.jsonl');
  const npmFile = join(bin, 'node_modules/npm/bin/npm-cli.js');
  const adapter = join(root, '@tokennotincluded/codewhale-lmm-provider/src/cli.mjs');
  mkdirSync(dirname(npmFile), { recursive: true });
  mkdirSync(dirname(adapter), { recursive: true });
  writeFileSync(log, '');
  writeFileSync(npmFile, `
const fs = require('node:fs');
const args = process.argv.slice(2);
fs.appendFileSync(process.env.TEST_LOG, JSON.stringify(['npm', args])+'\\n');
if(args[0] === 'root') console.log(process.env.TEST_ROOT);
if(args[0] === 'install' && process.env.TEST_NPM_FAIL) process.exit(7);
`);
  if (process.platform === 'win32') writeFileSync(join(bin, 'npm.cmd'), '@exit /b 99');
  else symlinkSync(npmFile, join(bin, 'npm'));
  writeFileSync(adapter, `
import fs from 'node:fs';
const args = process.argv.slice(2);
fs.appendFileSync(process.env.TEST_LOG, JSON.stringify(['adapter', args, process.env.LMM_CODEWHALE_BIN || null])+'\\n');
if(process.env.TEST_ADAPTER_FAIL === args[0]) process.exit(9);
if(args[0] === 'models') console.log(process.env.TEST_MODELS);
if(args[0] === 'status') console.log('{"signed_in":true}');
`);
  // Test native invocation portably: the real Node executable supports --version/--help.
  const env = { ...process.env, PATH: bin + delimiter + process.env.PATH,
    TEST_ROOT: root, TEST_LOG: log, TEST_MODELS: JSON.stringify([{ id, name: 'model', group: 'default' }]),
    LMM_CODEWHALE_BIN: process.execPath };
  delete env.TEST_NPM_FAIL; delete env.TEST_ADAPTER_FAIL;
  return { home, bin, root, npmFile, adapter, env,
    calls: () => readFileSync(log, 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line)),
    run: (...args) => spawnSync(process.execPath, [join(here, 'codewhale.mjs'), ...args], { env, encoding: 'utf8', timeout: 10000 }),
  };
}

test('help and default setup parse without loading installed packages', () => {
  assert.equal(parseArguments([]).action, 'setup');
  assert.equal(parseArguments(['--help']).action, 'help');
  assert.deepEqual(parseArguments(['login', '--no-browser']), { action: 'login', noBrowser: true, model: undefined, forwarded: [] });
});
test('run preserves literal shell metacharacters after the separator', () => {
  const task = 'literal $(touch SHOULD_NOT_EXIST); & | "hello"';
  assert.deepEqual(parseArguments(['run', '--model', id, '--', 'exec', task]).forwarded, ['exec', task]);
});
test('unknown commands/options, missing values and cross-action flags fail closed', () => {
  for (const args of [['delete'], ['install', '--local-only'], ['run', '--model'], ['run', '--model', '--help'],
    ['run', '--model', id, '--model', other], ['status', '--no-browser'], ['install', '--model', id], ['login', '--', 'exec']]) {
    assert.throws(() => parseArguments(args));
  }
});
test('provider, credential and config overrides cannot be forwarded', () => {
  for (const flag of ['--api-key=secret', '--provider', '--config-path', '--model=other', '--base-url=x']) {
    assert.throws(() => parseArguments(['run', '--', flag]));
  }
});
test('catalog accepts separate groups with exact synthetic IDs', () => {
  assert.deepEqual(parseModels(JSON.stringify([{ id }, { id: other }])), [{ id }, { id: other }]);
  assert.equal(selectModel([{ id }, { id: other }], '2'), other);
});
test('catalog rejects malformed, duplicate and control-character IDs', () => {
  for (const json of ['{}', 'null', 'bad', JSON.stringify([{ id }, { id }]), JSON.stringify([{ id: 'raw-upstream' }]),
    JSON.stringify([{ id: 'lmm:a:b\n' }])]) assert.throws(() => parseModels(json));
});
test('out-of-range and nonnumeric choices never silently select a model', () => {
  for (const choice of ['0', '-1', '2', '01', '1x', '', '1;exit', '99999999999999999999']) {
    assert.throws(() => selectModel([{ id }], choice));
  }
});
test('npm CLI is resolved as JS rather than executing a Windows command shim', t => {
  const f = fixture(t);
  assert.equal(npmCLI(f.env), realpathSync(f.npmFile));
  writeFileSync(join(f.bin, 'npm.cmd'), '@exit /b 99');
  assert.equal(npmCLI({ PATH: f.bin }, 'win32'), realpathSync(f.npmFile));
});
test('missing npm has an actionable error', () => {
  assert.throws(() => npmCLI({ PATH: '' }), /npm was not found/);
});
test('headless setup/menu stops before npm, installation or authorization', t => {
  const f = fixture(t);
  for (const action of ['setup', 'menu']) {
    const result = f.run(action);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /interactive terminal/);
  }
  assert.deepEqual(f.calls(), []);
});
test('help needs no npm and never accesses account data', t => {
  const f = fixture(t); f.env.PATH = '';
  const result = f.run('--help');
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /install.*Install\/update/);
  assert.deepEqual(f.calls(), []);
});
test('install uses official npm and pinned adapter; never logs in', t => {
  const f = fixture(t);
  const result = f.run('install');
  assert.equal(result.status, 0, result.stderr);
  assert.match(PROVIDER_REV, /^[0-9a-f]{40}$/);
  assert.deepEqual(f.calls().map(call => call.slice(0, 2)), [
    ['npm', ['root', '--global']],
    ['npm', ['install', '--global', 'codewhale@latest']],
    ['npm', ['install', '--global', '--ignore-scripts', PROVIDER_URL]],
    ['adapter', ['--help']],
  ]);
});
test('failed host installation stops before adapter install and account access', t => {
  const f = fixture(t); f.env.TEST_NPM_FAIL = '1';
  const result = f.run('install');
  assert.equal(result.status, 7, result.stderr);
  assert.equal(f.calls().length, 2);
  assert.match(result.stderr, /No later step/);
});
test('login forwards no-browser, without installing or running inference', t => {
  const f = fixture(t);
  const result = f.run('login', '--no-browser');
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(f.calls().map(call => call.slice(0, 2)), [['npm', ['root', '--global']], ['adapter', ['login', '--no-browser']]]);
});
test('failed login retains its failure code and never prints ready', t => {
  const f = fixture(t); f.env.TEST_ADAPTER_FAIL = 'login';
  const result = f.run('login');
  assert.equal(result.status, 9);
  assert.doesNotMatch(result.stdout, /Ready/);
});
test('headless run with an exact ID forwards arguments literally and selects the native file', t => {
  const f = fixture(t);
  const task = 'literal $(echo no); "x" & |';
  const result = f.run('run', '--model', id, '--', 'exec', task);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(f.calls().at(-1), ['adapter', ['run', '--model', id, '--', 'exec', task], process.execPath]);
});
test('a single catalog model may be selected without inventing a default group', t => {
  const f = fixture(t);
  assert.equal(f.run('run').status, 0);
  assert.equal(f.calls().at(-1)[1][2], id);
});
test('multiple models without a TTY fail before starting Codewhale', t => {
  const f = fixture(t); f.env.TEST_MODELS = JSON.stringify([{ id }, { id: other }]);
  assert.notEqual(f.run('run').status, 0);
  assert.ok(!f.calls().some(call => call[0] === 'adapter' && call[1][0] === 'run'));
});
test('empty or unauthorized catalog selection never launches inference', t => {
  const f = fixture(t);
  for (const models of ['[]', JSON.stringify([{ id: other }])]) {
    f.env.TEST_MODELS = models;
    assert.notEqual(f.run('run', '--model', id).status, 0);
  }
  assert.ok(!f.calls().some(call => call[0] === 'adapter' && call[1][0] === 'run'));
});
test('queries and logout only invoke their corresponding adapter action', t => {
  const f = fixture(t);
  for (const action of ['models', 'status', 'balance', 'usage', 'logout']) {
    assert.equal(f.run(action).status, 0);
    assert.equal(f.calls().at(-1)[1][0], action);
  }
  assert.ok(!f.calls().some(call => call[0] === 'npm' && call[1][0] === 'install'));
});
test('doctor checks native executable and adapter without credentials', t => {
  const f = fixture(t);
  const result = f.run('doctor');
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /not a live OAuth test/);
  assert.deepEqual(f.calls().at(-1)[1], ['--help']);
});
test('native resolver delegates to official getBinaryPath, not guessed download paths', async t => {
  const f = fixture(t);
  mkdirSync(join(f.root, 'codewhale/scripts'), { recursive: true });
  writeFileSync(join(f.root, 'codewhale/scripts/install.js'), `exports.getBinaryPath = async name => { if(name !== 'codewhale') throw Error('wrong binary'); return ${JSON.stringify(process.execPath)}; };`);
  assert.equal(await nativeHost(f.root, {}), process.execPath);
});
test('native resolver fails closed when upstream resolver contract is absent', async t => {
  const f = fixture(t);
  mkdirSync(join(f.root, 'codewhale/scripts'), { recursive: true });
  writeFileSync(join(f.root, 'codewhale/scripts/install.js'), 'exports.changed = true;');
  await assert.rejects(nativeHost(f.root, {}), /contract changed/);
});
test('Windows npm shims, relative paths and missing binaries are not accepted', async t => {
  const f = fixture(t);
  const cmd = join(f.home, 'codewhale.cmd'); writeFileSync(cmd, 'exit 0');
  for (const value of [cmd, 'codewhale', join(f.home, 'missing')]) {
    await assert.rejects(nativeHost(f.root, { LMM_CODEWHALE_BIN: value }), /native Codewhale executable/);
  }
});
test('child failure code is preserved without leaking arguments', () => {
  assert.throws(() => command(process.execPath, ['-e', 'process.exit(17)', 'SENSITIVE']), error => error.exitCode === 17 && !error.message.includes('SENSITIVE'));
});
test('installation and launch leave caller-owned configuration untouched', t => {
  const f = fixture(t);
  const config = join(f.home, 'config.toml'); const contents = 'provider = "existing"\n';
  writeFileSync(config, contents); f.env.CODEWHALE_CONFIG_PATH = config;
  assert.equal(f.run('install').status, 0);
  assert.equal(f.run('run', '--model', id).status, 0);
  assert.equal(readFileSync(config, 'utf8'), contents);
});

test('Bash and PowerShell bootstrap pin the same verified helper', async () => {
  const { createHash } = await import('node:crypto');
  const digest = createHash('sha256').update(readFileSync(join(here, 'codewhale.mjs'))).digest('hex');
  for (const ext of ['sh', 'ps1']) {
    const source = readFileSync(join(here, `codewhale.${ext}`), 'utf8');
    assert.ok(source.includes(digest));
    assert.match(source, /lmm-scripts\/[a-f0-9]{40}\/codewhale\.mjs/);
  }
});

if (process.platform !== 'win32') {
  function shellFixture(t) {
    const f = fixture(t);
    const launch = join(f.home, 'launcher'); mkdirSync(launch);
    const wrapper = join(launch, 'codewhale.sh');
    writeFileSync(wrapper, readFileSync(join(here, 'codewhale.sh')));
    f.env.TEST_HELPER = join(here, 'codewhale.mjs');
    f.env.TMPDIR = f.home;
    const curl = `#!${process.execPath}\nimport fs from 'node:fs';
const args=process.argv.slice(2), dest=args[args.indexOf('-o')+1];
fs.appendFileSync(process.env.TEST_LOG,JSON.stringify(['curl',args])+'\\n');
fs.writeFileSync(dest,process.env.TEST_BAD_DOWNLOAD ? 'throw Error("MALICIOUS_EXECUTED")' : fs.readFileSync(process.env.TEST_HELPER));
process.exit(Number(process.env.TEST_CURL_EXIT||0));\n`;
    writeFileSync(join(f.bin, 'curl'), curl, { mode: 0o755 });
    return { ...f, launch, runShell: (...args) => spawnSync('bash', [wrapper, ...args], { env: f.env, encoding: 'utf8', timeout: 10000 }) };
  }
  test('standalone Bash download verifies and executes the pinned helper', t => {
    const f = shellFixture(t);
    const result = f.runShell('--help');
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /Codewhale \+ LMM/);
    assert.ok(f.calls()[0][1].some(arg => /354a0e7e8597957b33f5d4f4afcf9ac7ebfe8693\/codewhale.mjs/.test(arg)));
  });
  test('truncated downloads fail before execution even when bytes were written', t => {
    const f = shellFixture(t); f.env.TEST_BAD_DOWNLOAD = '1'; f.env.TEST_CURL_EXIT = '18';
    const result = f.runShell('--help');
    assert.equal(result.status, 18);
    assert.doesNotMatch(result.stderr, /MALICIOUS_EXECUTED/);
  });
  test('checksum mismatch fails before downloaded code executes', t => {
    const f = shellFixture(t); f.env.TEST_BAD_DOWNLOAD = '1';
    const result = f.runShell('--help');
    assert.equal(result.status, 1);
    assert.match(result.stderr, /checksum mismatch/);
    assert.doesNotMatch(result.stderr, /MALICIOUS_EXECUTED/);
  });
  test('local Bash helper preserves exact task arguments and child failure', t => {
    const f = shellFixture(t);
    writeFileSync(join(f.launch, 'codewhale.mjs'), `import fs from 'node:fs';fs.appendFileSync(process.env.TEST_LOG,JSON.stringify(['local',process.argv.slice(2)])+'\\n');process.exit(17);`);
    const task = 'spaces "quoted" $(touch unwanted); & |';
    const result = f.runShell('run', '--model', id, '--', 'exec', task);
    assert.equal(result.status, 17);
    assert.deepEqual(f.calls(), [['local', ['run', '--model', id, '--', 'exec', task]]]);
  });
}
