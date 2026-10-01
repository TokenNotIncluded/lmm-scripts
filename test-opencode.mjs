import {test, after} from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {createRequire} from 'node:module';
import {mergePlugin, selectConfig, configDirectory, resolveRelease, resolveReleaseRedirect, releaseMetadata, npmCli} from './opencode.mjs';
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
  assert.equal(configDirectory({OPENCODE_CONFIG_DIR:'', XDG_CONFIG_HOME:'/custom'}, '/home/user'), path.join('/custom','opencode'));
  assert.equal(configDirectory({XDG_CONFIG_HOME:''}, '/home/user'), path.join('/home/user','.config','opencode'));
});

test('official latest release validates repository, full commit, assets and checksum', () => {
  const base = 'https://github.com/TokenNotIncluded/opencode-lmm-auth/releases';
  const name = 'opencode-lmm-auth-'+'a'.repeat(40)+'.tgz';
  const release = {draft:false,prerelease:false,tag_name:'v3.2.1',target_commitish:'a'.repeat(40),html_url:base+'/tag/v3.2.1',assets:[name,'SHA256SUMS'].map(name=>({name,browser_download_url:base+'/download/v3.2.1/'+name}))};
  const manifest = 'b'.repeat(64)+'  '+name+'\n';
  assert.equal(resolveRelease(release,manifest).commit, 'a'.repeat(40));
  assert.equal(resolveRelease(release,manifest).sha256, 'b'.repeat(64));
  for(const invalid of [{...release,target_commitish:'main'}, {...release,prerelease:true}, {...release,html_url:'https://evil.test/tag/v3.2.1'}, {...release,assets:[...release.assets,{...release.assets[0]}]}, {...release,assets:[{...release.assets[0],browser_download_url:'https://evil.test/plugin.tar.gz'},release.assets[1]]}]) assert.throws(()=>resolveRelease(invalid,manifest));
  assert.throws(()=>resolveRelease(release,manifest+manifest));
  assert.throws(()=>resolveRelease(release,'bad  '+name));
});

test('latest public asset redirect requires official repository and tagged manifest', () => {
  const base='https://github.com/TokenNotIncluded/opencode-lmm-auth/releases/download/';
  assert.equal(resolveReleaseRedirect(base+'v2.5.0/release.json').tag,'v2.5.0');
  for(const url of ['https://evil.test/releases/download/v2.5.0/release.json',base+'v2.5.0/release.json?override=1',base+'../other/release.json',base+'v2.5.0/evil.json','https://user@github.com/TokenNotIncluded/opencode-lmm-auth/releases/download/v2.5.0/release.json',base+'v2.5.0/release.json#wrong']) assert.throws(()=>resolveReleaseRedirect(url));
  const doc={schema_version:1,repository:'TokenNotIncluded/opencode-lmm-auth',tag:'v2.5.0',source_sha:'a'.repeat(40),filename:'opencode-lmm-auth-'+'a'.repeat(40)+'.tgz',sha256:'b'.repeat(64)};
  assert.equal(releaseMetadata(doc,'v2.5.0').target_commitish,doc.source_sha);
  for(const invalid of [{...doc,repository:'Other/repo'},{...doc,tag:'v9.0.0'},{...doc,filename:'../evil.tgz'},{...doc,source_sha:'main'},{...doc,sha256:'bad'}]) assert.throws(()=>releaseMetadata(invalid,'v2.5.0'));
});
