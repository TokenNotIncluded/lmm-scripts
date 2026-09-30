import {test, after} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {mergePlugin, selectConfig, configDirectory, npmCli} from './opencode.mjs';
const work = await fs.mkdtemp(path.join(os.tmpdir(), 'lmm-jsonc-test-'));
// Use the npm CLI through Node, including Windows paths with spaces.
const executable = npmCli();
const install = spawnSync(process.execPath, [executable, 'install', '--prefix', work, '--ignore-scripts', '--no-audit', '--no-fund', '--package-lock=false', 'jsonc-parser@3.3.1'], {stdio: 'inherit'});
assert.equal(install.status, 0);
const jsonc = createRequire(path.join(work, 'package.json'))('jsonc-parser');
after(() => fs.rm(work, {recursive: true, force: true}));
const entry = 'file:///home/user/.config/opencode/lmm-auth/' + 'a'.repeat(40) + '/dist/index.js';
test('preserves comments, existing providers and unrelated plugins', () => {
  const original = '{\n// user comment\n"plugin": ["other",],\n"provider": {"custom": {"options":{"apiKey":"fixture"}}},\n}\n';
  const changed = mergePlugin(original, entry, jsonc);
  assert.ok(changed.includes('// user comment'));
  const config = jsonc.parse(changed);
  assert.deepEqual(config.plugin, ['other', entry]);
  assert.deepEqual(config.provider, jsonc.parse(original).provider);
  assert.equal(mergePlugin(changed, entry, jsonc), changed);
});
test('replaces only managed plugin source while preserving tuple options', () => {
  const old = entry.replace('a'.repeat(40), 'b'.repeat(40));
  const original = JSON.stringify({plugin: ['other', [old, {issuer: 'https://custom.example'}]], provider:{lmm:{models:{configured:{}}}}});
  const changed = jsonc.parse(mergePlugin(original, entry, jsonc));
  assert.deepEqual(changed.plugin, ['other', [entry, {issuer:'https://custom.example'}]]);
  assert.deepEqual(changed.provider, jsonc.parse(original).provider);
});
test('refuses duplicate manually installed LMM plugin sources', () => {
  for (const source of ['@tokennotincluded/opencode-lmm-auth', 'file:///custom/opencode-lmm-auth/dist/index.js']) {
    const original = JSON.stringify({plugin: [source, 'file:///custom/index.js']});
    assert.throws(() => mergePlugin(original, entry, jsonc), /unmanaged LMM plugin/);
  }
  assert.throws(() => mergePlugin(JSON.stringify({plugin:[entry, entry.replace('a'.repeat(40), 'b'.repeat(40))]}), entry, jsonc), /Multiple managed/);
});
test('rejects malformed config and invalid plugin list', () => {
  for (const text of ['{oops}', '[]', '{"plugin": "other"}', 'null']) assert.throws(() => mergePlugin(text, entry, jsonc));
});
test('adds plugin array to fresh and commented empty configurations', () => {
  for (const text of ['{}\n', '{\n// retain me\n}\n']) assert.deepEqual(jsonc.parse(mergePlugin(text, entry, jsonc)).plugin, [entry]);
});

test('updates the config owning the previous LMM plugin without duplicating across json/jsonc', () => {
  const managed = JSON.stringify({plugin:[entry]});
  assert.equal(selectConfig(managed, '{// keep comment\n"provider":{}}', jsonc), 'json');
  assert.equal(selectConfig('{}', managed, jsonc), 'jsonc');
  assert.throws(() => selectConfig(managed, managed, jsonc), /both OpenCode configs/);
  assert.throws(() => selectConfig('{bad}', '{}', jsonc), /invalid/);
});

test('uses the same config directory override as the OpenCode host', () => {
  assert.equal(configDirectory({OPENCODE_CONFIG_DIR:'/custom/opencode', XDG_CONFIG_HOME:'/other'}, '/home/user'), '/custom/opencode');
  assert.equal(configDirectory({OPENCODE_CONFIG_DIR:'', XDG_CONFIG_HOME:'/custom'}, '/home/user'), '/custom/opencode');
  assert.equal(configDirectory({XDG_CONFIG_HOME:''}, '/home/user'), '/home/user/.config/opencode');
});
