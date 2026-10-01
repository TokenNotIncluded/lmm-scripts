#!/usr/bin/env node
import fs from 'node:fs/promises';
import {existsSync, realpathSync} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {spawnSync} from 'node:child_process';

export const LAST_TESTED_OPENCODE_VERSION = '1.18.34';
const REPOSITORY = 'TokenNotIncluded/opencode-lmm-auth';
export function resolveRelease(release, checksums) {
  if (!release || release.draft !== false || release.prerelease !== false || !/^v[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$/.test(release.tag_name ?? '') || !/^[a-f0-9]{40}$/.test(release.target_commitish ?? '')) throw new Error('Official plugin release metadata is invalid.');
  const base = `https://github.com/${REPOSITORY}/releases`;
  if (release.html_url !== `${base}/tag/${release.tag_name}` || !Array.isArray(release.assets)) throw new Error('Plugin release is outside the official repository.');
  const name = `opencode-lmm-auth-${release.target_commitish}.tgz`;
  const asset = file => {
    const entries = release.assets.filter(value => value.name === file);
    const expected = `${base}/download/${release.tag_name}/${file}`;
    if (entries.length !== 1 || entries[0].browser_download_url !== expected) throw new Error('Plugin release assets are missing or outside the official repository.');
    return expected;
  };
  const url = asset(name);
  const checksumUrl = asset('SHA256SUMS');
  if (checksums === undefined) return {commit:release.target_commitish, url, checksumUrl};
  const matches = checksums.split(/\r?\n/).filter(line => line.endsWith('  '+name));
  if (matches.length !== 1 || !/^[a-f0-9]{64}  /.test(matches[0]) || matches[0].length !== 66 + name.length) throw new Error('Plugin release checksum manifest is invalid.');
  return {commit:release.target_commitish, url, checksumUrl, sha256:matches[0].slice(0,64)};
}
export function resolveReleaseRedirect(location) {
  let url;
  try { url = new URL(location, `https://github.com/${REPOSITORY}/releases/latest/download/release.json`); }
  catch { throw new Error('Official plugin release redirect is invalid.'); }
  const prefix = `/${REPOSITORY}/releases/download/`;
  if (url.origin !== 'https://github.com' || url.username || url.password || url.search || url.hash || !url.pathname.startsWith(prefix) || !url.pathname.endsWith('/release.json')) throw new Error('Plugin release redirect is outside the official repository.');
  const tag = decodeURIComponent(url.pathname.slice(prefix.length, -'/release.json'.length));
  if (!/^v[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$/.test(tag)) throw new Error('Official plugin release tag is invalid.');
  return {tag,url:url.href};
}
export function releaseMetadata(document, tag) {
  if (!document || document.schema_version !== 1 || document.repository !== REPOSITORY || document.tag !== tag || !/^[a-f0-9]{40}$/.test(document.source_sha ?? '') || !/^[a-f0-9]{64}$/.test(document.sha256 ?? '') || document.filename !== `opencode-lmm-auth-${document.source_sha}.tgz`) throw new Error('Official plugin release document is invalid.');
  const base = `https://github.com/${REPOSITORY}/releases`;
  return {draft:false,prerelease:false,tag_name:tag,target_commitish:document.source_sha,html_url:`${base}/tag/${tag}`,assets:[document.filename,'SHA256SUMS'].map(name=>({name,browser_download_url:`${base}/download/${tag}/${name}`}))};
}
async function latestRelease() {
  // The public download redirect avoids GitHub's anonymous API rate limit.
  const response = await fetch(`https://github.com/${REPOSITORY}/releases/latest/download/release.json`, {redirect:'manual',signal:AbortSignal.timeout(30000)});
  if (![301,302,303,307,308].includes(response.status)) throw new Error(`Official plugin release lookup failed: HTTP ${response.status}`);
  const redirect = resolveReleaseRedirect(response.headers.get('location'));
  const metadataResponse = await fetch(redirect.url,{signal:AbortSignal.timeout(30000)});
  if (!metadataResponse.ok) throw new Error(`Official plugin release document download failed: HTTP ${metadataResponse.status}`);
  const text = await metadataResponse.text();
  if (text.length > 131072) throw new Error('Plugin release document is too large.');
  let document;
  try { document = JSON.parse(text); } catch { throw new Error('Plugin release document is invalid JSON.'); }
  const release = releaseMetadata(document,redirect.tag);
  const source = resolveRelease(release);
  const manifest = await fetch(source.checksumUrl,{signal:AbortSignal.timeout(30000)});
  if (!manifest.ok) throw new Error(`Official plugin checksum download failed: HTTP ${manifest.status}`);
  const checksums = await manifest.text();
  if (checksums.length > 131072) throw new Error('Plugin checksum manifest is too large.');
  const verified = resolveRelease(release,checksums);
  if (verified.sha256 !== document.sha256) throw new Error('Plugin release document and checksum manifest disagree.');
  return verified;
}

function run(command, args) {
  const result = spawnSync(command, args, {stdio: 'inherit', windowsHide: true});
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${path.basename(command)} exited with ${result.status}`);
}
export function npmCli() {
  for (const cli of [path.resolve(path.dirname(process.execPath), "../lib/node_modules/npm/bin/npm-cli.js"), path.join(path.dirname(process.execPath), "node_modules/npm/bin/npm-cli.js")]) {
    if (existsSync(cli)) return cli;
  }
  for (const dir of (process.env.PATH || '').split(path.delimiter)) {
    const executable = path.join(dir, process.platform === 'win32' ? 'npm.cmd' : 'npm');
    if (!existsSync(executable)) continue;
    const real = realpathSync(executable);
    if (path.basename(real) === "npm-cli.js") return real;
    const cli = path.join(path.dirname(real), process.platform === 'win32' ? 'node_modules/npm/bin/npm-cli.js' : '../lib/node_modules/npm/bin/npm-cli.js');
    if (existsSync(cli)) return cli;
  }
  throw new Error('npm is required. Install Node.js with npm first.');
}

export function mergePlugin(text, entry, jsonc) {
  const errors = [];
  const config = jsonc.parse(text, errors, {allowTrailingComma: true});
  if (errors.length || !config || typeof config !== 'object' || Array.isArray(config)) {
    throw new Error('Existing OpenCode configuration is invalid; it was not changed.');
  }
  if (config.plugin !== undefined && !Array.isArray(config.plugin)) throw new Error('OpenCode plugin must be an array; configuration was not changed.');
  const plugins = config.plugin || [];
  if (plugins.some(value => { const source = Array.isArray(value) ? value[0] : value; return typeof source === "string" && source.includes("opencode-lmm-auth"); })) throw new Error("An unmanaged LMM plugin source already exists. Remove that duplicate entry manually before using this installer.");
  // Replace only our previously managed entry. Other plugin entries remain intact.
  const managed = value => typeof value === 'string' && value.startsWith('file:') && /\/lmm-auth\/[a-f0-9]{40}\/dist\/index\.js$/.test(value);
  if (plugins.filter(value => managed(Array.isArray(value) ? value[0] : value)).length > 1) throw new Error('Multiple managed LMM plugin entries exist; remove duplicates before installing.');
  const matching = plugins.findIndex(value => managed(Array.isArray(value) ? value[0] : value));
  if (matching >= 0) {
    const old = plugins[matching];
    const updated = Array.isArray(old) ? [entry, ...old.slice(1)] : entry;
    return jsonc.applyEdits(text, jsonc.modify(text, ['plugin', matching], updated, {formattingOptions: {insertSpaces: true, tabSize: 2}}));
  }
  if (plugins.some(value => value === entry || (Array.isArray(value) && value[0] === entry))) return text;
  const location = config.plugin === undefined ? ['plugin'] : ['plugin', -1];
  return jsonc.applyEdits(text, jsonc.modify(text, location, config.plugin === undefined ? [entry] : entry, {formattingOptions: {insertSpaces: true, tabSize: 2}}));
}

export function selectConfig(json, jsoncText, jsonc) {
  const sources = [json, jsoncText].map(text => {
    if (text === undefined) return false;
    const errors = [];
    const config = jsonc.parse(text.replace(/^\uFEFF/, ''), errors, {allowTrailingComma:true});
    if (errors.length || !config || typeof config !== 'object' || Array.isArray(config)) throw new Error('Existing OpenCode configuration is invalid; it was not changed.');
    if (config.plugin !== undefined && !Array.isArray(config.plugin)) throw new Error('OpenCode plugin must be an array; configuration was not changed.');
    return (config.plugin ?? []).some(value => {const source = Array.isArray(value) ? value[0] : value; return typeof source === 'string' && (/\/lmm-auth\/[a-f0-9]{40}\/dist\/index\.js$/.test(source) || source.includes('opencode-lmm-auth'));});
  });
  if (sources[0] && sources[1]) throw new Error('LMM plugin entries exist in both OpenCode configs; remove the duplicate before installing.');
  return sources[0] ? 'json' : jsoncText === undefined ? 'json' : 'jsonc';
}

export function configDirectory(env = process.env, home = os.homedir()) {
  return env.OPENCODE_CONFIG_DIR || path.join(env.XDG_CONFIG_HOME || path.join(home, '.config'), 'opencode');
}

async function main() {
  if (process.argv.slice(2).join(' ') === '--help') { console.log('OpenCode + LMM: installs the latest official OpenCode and the latest official OAuth plugin. Usage: node opencode.mjs'); return; }
  if (process.argv.length > 2) throw new Error('Usage: node opencode.mjs');
  const [major, minor] = process.versions.node.split('.').map(Number);
  if (major < 22 || (major === 22 && minor < 19)) throw new Error('Node.js 22.19+ with npm is required.');
  const source = await latestRelease();
  const configDir = configDirectory();
  await fs.mkdir(configDir, {recursive: true});
  const jsonPath = path.join(configDir, 'opencode.json');
  const jsoncPath = path.join(configDir, 'opencode.jsonc');
  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'lmm-opencode-'));
  try {
    run(process.execPath, [npmCli(), 'install', '--prefix', work, '--ignore-scripts', '--no-audit', '--no-fund', '--package-lock=false', '--registry=https://registry.npmjs.org', 'jsonc-parser@3.3.1']);
    const require = createRequire(path.join(work, 'package.json'));
    const jsonc = require('jsonc-parser');
    const selected = selectConfig(existsSync(jsonPath) ? await fs.readFile(jsonPath, 'utf8') : undefined, existsSync(jsoncPath) ? await fs.readFile(jsoncPath, 'utf8') : undefined, jsonc);
    let configPath = selected === 'json' ? jsonPath : jsoncPath;
    const hadConfig = existsSync(configPath);
    if (hadConfig) configPath = await fs.realpath(configPath);
    const original = hadConfig ? await fs.readFile(configPath, 'utf8') : '{}\n';
    const installDir = path.join(configDir, 'lmm-auth', source.commit);
    const entry = pathToFileURL(path.join(installDir, 'dist/index.js')).href;
    // Validate the original before installing or writing anything to the config.
    const changed = mergePlugin(original.replace(/^\uFEFF/, ''), entry, jsonc);
    run(process.execPath, [npmCli(), 'install', '--global', '--no-audit', '--no-fund', '--registry=https://registry.npmjs.org', 'opencode-ai@latest']);
    const npmRoot = spawnSync(process.execPath, [npmCli(), 'root', '--global'], {encoding:'utf8', windowsHide:true});
    if (npmRoot.status !== 0) throw new Error('Cannot locate the installed OpenCode package.');
    const packageDir = path.join(npmRoot.stdout.trim(), 'opencode-ai');
    const metadata = JSON.parse(await fs.readFile(path.join(packageDir, 'package.json'), 'utf8'));
    const bin = typeof metadata.bin === 'string' ? metadata.bin : metadata.bin?.opencode;
    if (typeof bin !== 'string') throw new Error('Official OpenCode package has no opencode executable.');
    const installedBinary = path.resolve(packageDir, bin);
    const installedVersion = spawnSync(installedBinary, ['--version'], {encoding:'utf8', timeout:15000, windowsHide:true});
    if (installedVersion.status !== 0 || !/^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$/.test(installedVersion.stdout.trim())) throw new Error('Installed OpenCode failed version verification; configuration was not changed.');
    if (!existsSync(path.join(installDir, 'dist/index.js'))) {
      const response = await fetch(source.url, {signal: AbortSignal.timeout(120000)});
      if (!response.ok) throw new Error(`Plugin download failed: HTTP ${response.status}`);
      const archive = Buffer.from(await response.arrayBuffer());
      if (createHash('sha256').update(archive).digest('hex') !== source.sha256) throw new Error('Plugin source checksum mismatch; plugin configuration was not changed.');
      const archivePath = path.join(work, 'plugin.tar.gz');
      const extracted = path.join(work, 'plugin');
      await fs.writeFile(archivePath, archive);
      await fs.mkdir(extracted);
      run('tar', ['-xzf', archivePath, '--strip-components=1', '-C', extracted]);
      if (!existsSync(path.join(extracted, 'dist/index.js'))) throw new Error('Plugin archive does not contain dist/index.js.');
      await fs.mkdir(path.dirname(installDir), {recursive: true});
      // Work can be on another drive, so copy into a same-directory staging path.
      const stage = await fs.mkdtemp(path.join(path.dirname(installDir), '.install-'));
      try { await fs.cp(extracted, stage, {recursive: true}); await fs.rename(stage, installDir); }
      finally { await fs.rm(stage, {recursive: true, force: true}); }
    }
    if (changed !== original) {
      if (existsSync(configPath) !== hadConfig) throw new Error("OpenCode configuration changed during installation; rerun the installer.");
      if (hadConfig) {
        if (await fs.readFile(configPath, 'utf8') !== original) throw new Error('OpenCode configuration changed during installation; rerun the installer.');
        await fs.copyFile(configPath, `${configPath}.lmm-backup-${Date.now()}`, 1);
      }
      const staged = path.join(path.dirname(configPath), `.lmm-config-${process.pid}.tmp`);
      try { await fs.writeFile(staged, changed, {mode: 0o600, flag: 'wx'}); await fs.rename(staged, configPath); }
      finally { await fs.rm(staged, {force: true}); }
    }
    console.log('LMM OpenCode plugin installed. Run opencode auth login --provider lmm, complete Sign in with LMM (OAuth), then restart OpenCode.');
    console.log('OpenCode version: ' + installedVersion.stdout.trim() + '. Login is explicit; no API keys or OAuth tokens were written by this installer.');
  } finally { await fs.rm(work, {recursive: true, force: true}); }
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
