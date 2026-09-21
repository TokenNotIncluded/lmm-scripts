#!/usr/bin/env node
// Shared by the Bash and PowerShell entrypoints; no credentials or host config are written here.
import { spawnSync } from 'node:child_process';
import { existsSync, realpathSync, statSync } from 'node:fs';
import { basename, delimiter, dirname, isAbsolute, join } from 'node:path';
import { createRequire } from 'node:module';
import { createInterface } from 'node:readline/promises';
import { pathToFileURL } from 'node:url';

export const PROVIDER_REV = '8c78be0f936fb8f508badabc0195cdb21442a75d';
export const PROVIDER_URL = `https://github.com/TokenNotIncluded/codewhale-lmm-provider/archive/${PROVIDER_REV}.tar.gz`;
const require = createRequire(import.meta.url);
const actions = ['setup', 'install', 'login', 'run', 'models', 'status', 'balance', 'usage', 'logout', 'doctor', 'menu', 'help'];
const help = `Codewhale + LMM (Node.js 22+, npm)

  bash codewhale.sh [action] [options]
  .\\codewhale.ps1 [action] [options]
  node codewhale.mjs [action] [options]

  setup    Install, authorize in your browser, optionally choose a model and start (default)
  install  Install/update only; never log in (also suitable for CI)
  login    Authorize LMM; use --no-browser to open the URL yourself
  run      Choose a catalog model, or pass --model <exact-id>
  models | status | balance | usage | logout
  doctor   Verify the selected native executable and adapter, without logging in
  menu     Installation, login, model selection, account queries and revocation

  run --model <exact-id> -- exec "your task"   (arguments are forwarded without a shell)

Uses official npm codewhale@latest and a pinned LMM adapter. Does not install Node,
change npm's registry, overwrite Codewhale config, or enable unsafe/auto-approve modes.
The server must deploy the lmm-codewhale registration (api.lmm.best PR #440).
Termux/Android remains preview. Windows adapter ACL hardening is not implemented;
use a private OS account, not a shared Windows account.
`;

export function parseArguments(argv) {
  const result = { action: 'setup', noBrowser: false, model: undefined, forwarded: [] };
  const args = [...argv];
  if (args[0] && !args[0].startsWith('-')) result.action = args.shift();
  while (args.length) {
    const arg = args.shift();
    if (arg === '--') { result.forwarded = args.splice(0); break; }
    if (arg === '--help' || arg === '-h') result.action = 'help';
    else if (arg === '--no-browser') result.noBrowser = true;
    else if (arg === '--model' && !result.model && args[0] && !args[0].startsWith('-')) result.model = args.shift();
    else throw new Error('Invalid arguments. Use --help.');
  }
  if (!actions.includes(result.action)) throw new Error('Unknown action. Use --help.');
  if (result.noBrowser && !['login', 'setup'].includes(result.action)) throw new Error('--no-browser is only valid with login/setup.');
  if ((result.model || result.forwarded.length) && result.action !== 'run') throw new Error('--model and forwarded arguments are only valid with run.');
  if (result.forwarded.some(arg => /^--(?:provider|model|base-url|api-key|config|config-path)(?:=|$)/.test(arg))) {
    throw new Error('Do not override the LMM provider, model, configuration or credentials after --.');
  }
  return result;
}

export function npmCLI(env = process.env, platform = process.platform) {
  // Run npm's JS entrypoint with Node: never interpolate arguments into cmd.exe on Windows.
  for (const dir of (env.PATH || env.Path || '').split(delimiter).filter(Boolean)) {
    const entry = join(dir, platform === 'win32' ? 'npm.cmd' : 'npm');
    if (!existsSync(entry)) continue;
    const resolved = realpathSync(entry);
    const candidates = [
      ...(basename(resolved) === 'npm-cli.js' ? [resolved] : []),
      join(dirname(resolved), 'node_modules/npm/bin/npm-cli.js'),
      join(dirname(resolved), '../lib/node_modules/npm/bin/npm-cli.js'),
    ];
    const found = candidates.find(path => existsSync(path) && statSync(path).isFile());
    if (found) return realpathSync(found);
  }
  throw new Error('npm was not found with this Node installation. Install Node.js 22+ with npm; then reopen the terminal.');
}

export function command(binary, args, { capture = false, env = process.env } = {}) {
  const child = spawnSync(binary, args, { env, shell: false, windowsHide: true,
    stdio: capture ? ['inherit', 'pipe', 'inherit'] : 'inherit', encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
  if (child.error || child.signal || child.status !== 0) {
    const error = new Error(`${basename(binary)} failed${child.signal ? ` (${child.signal})` : ` (exit ${child.status ?? 'unknown'})`}. No later step was run.`);
    error.exitCode = child.signal === 'SIGINT' ? 130 : child.status || 1;
    throw error;
  }
  return child.stdout || '';
}

export function parseModels(text) {
  const models = JSON.parse(text);
  if (!Array.isArray(models) || models.length > 10000 || models.some(m =>
    !m || typeof m.id !== 'string' || !/^lmm:[A-Za-z0-9_-]+:[A-Za-z0-9_-]+$/.test(m.id))) {
    throw new Error('Invalid model catalog; no model was selected.');
  }
  if (new Set(models.map(m => m.id)).size !== models.length) throw new Error('Duplicate catalog model IDs.');
  return models;
}
export function selectModel(models, choice) {
  if (!/^[1-9][0-9]{0,4}$/.test(choice) || Number(choice) > models.length) throw new Error('Invalid model number.');
  return models[Number(choice) - 1].id;
}
const display = value => String(value ?? '').replace(/[\x00-\x1f\x7f-\x9f]/g, '').slice(0, 180);

export async function nativeHost(root, env = process.env) {
  let binary = env.LMM_CODEWHALE_BIN;
  if (!binary) {
    const installer = join(root, 'codewhale/scripts/install.js');
    if (!existsSync(installer)) throw new Error('Codewhale is not installed by npm. Run the install action first.');
    const { getBinaryPath } = require(installer);
    if (typeof getBinaryPath !== 'function') throw new Error('The official npm launcher contract changed. Stop here and update lmm-scripts.');
    // Use the official resolver and checksum verification, including Android assets.
    binary = await getBinaryPath('codewhale');
  }
  if (typeof binary !== 'string' || !isAbsolute(binary) || /\.(?:cmd|bat|ps1|js|mjs)$/i.test(binary) ||
      !existsSync(binary) || !statSync(binary).isFile()) {
    throw new Error('Expected an absolute native Codewhale executable, not an npm .cmd shim.');
  }
  return binary;
}

export async function main(argv = process.argv.slice(2)) {
  const options = parseArguments(argv);
  if (options.action === 'help') { console.log(help); return; }
  if (Number(process.versions.node.split('.')[0]) < 22) throw new Error('Node.js 22+ is required.');
  const interactive = Boolean(process.stdin.isTTY && process.stdout.isTTY);
  if (['setup', 'menu'].includes(options.action) && !interactive) {
    throw new Error('An interactive terminal is required. Use install for unattended installation; login/run are separate actions.');
  }
  const npm = npmCLI();
  const root = command(process.execPath, [npm, 'root', '--global'], { capture: true }).trim();
  if (!isAbsolute(root) || /[\r\n]/.test(root)) throw new Error('npm returned an invalid global package directory.');
  const adapter = join(root, '@tokennotincluded/codewhale-lmm-provider/src/cli.mjs');
  const call = (args, settings = {}) => {
    if (!existsSync(adapter)) throw new Error('LMM adapter is missing. Run the install action first.');
    return command(process.execPath, [adapter, ...args], settings);
  };
  const ask = async prompt => {
    if (!interactive) throw new Error('Choose a model with run --model <exact-id> outside an interactive terminal.');
    const input = createInterface({ input: process.stdin, output: process.stdout });
    try { return (await input.question(prompt)).trim(); } finally { input.close(); }
  };
  const doctor = async () => {
    const binary = await nativeHost(root);
    console.log(`Native executable: ${binary}`);
    command(binary, ['--version']);
    // The official npm wrapper may return zero for --version even without a binary.
    // Invoke the resolved native binary, and check --help too.
    command(binary, ['--help'], { capture: true });
    call(['--help'], { capture: true });
    console.log('Native executable and LMM adapter are available. This is not a live OAuth test.');
  };
  const install = async () => {
    console.log('Installing official Codewhale and the pinned LMM adapter; existing login/configuration files are left alone.');
    command(process.execPath, [npm, 'install', '--global', 'codewhale@latest']);
    command(process.execPath, [npm, 'install', '--global', '--ignore-scripts', PROVIDER_URL]);
    await doctor();
    console.log('Next: login, then run. The server must include the lmm-codewhale registration (PR #440).');
    if (process.platform === 'android') console.log('Android/Termux support is preview; no Linux binary fallback is used.');
    if (process.platform === 'win32') console.log('Use a private Windows account: the alpha adapter does not implement Windows ACL hardening.');
  };
  const run = async () => {
    const models = parseModels(call(['models'], { capture: true }));
    if (!models.length) throw new Error('No authorized Chat Completions models. Check the LMM account/groups; no fallback was selected.');
    let id = options.model;
    if (id && !models.some(m => m.id === id)) throw new Error('The model ID is not in the authorized catalog.');
    if (!id && models.length === 1) id = models[0].id;
    if (!id) {
      models.forEach((m, i) => console.log(`${i + 1}  ${display(m.name || m.id)}  [${display(m.group)}]\n   ${m.id}`));
      const choice = await ask('Model number (0 cancels): ');
      if (choice === '0') return;
      id = selectModel(models, choice);
    }
    const binary = await nativeHost(root);
    call(['run', '--model', id, ...(options.forwarded.length ? ['--', ...options.forwarded] : [])],
      { env: { ...process.env, LMM_CODEWHALE_BIN: binary } });
  };
  const login = () => call(['login', ...(options.noBrowser ? ['--no-browser'] : [])]);
  const setup = async () => {
    await install();
    const status = JSON.parse(call(['status'], { capture: true }));
    if (!status.signed_in) login();
    else console.log('Keeping the existing LMM authorization; it was not overwritten.');
    if ((await ask('Choose a model and start Codewhale now? [y/N] ')).toLowerCase() === 'y') await run();
    else console.log('Ready. Use the run action to choose a model later.');
  };
  const execute = async action => {
    if (action === 'install') await install();
    else if (action === 'setup') await setup();
    else if (action === 'doctor') await doctor();
    else if (action === 'run') await run();
    else if (action === 'login') login();
    else call([action]);
  };
  if (options.action !== 'menu') { await execute(options.action); return; }
  const entries = ['setup', 'install', 'login', 'run', 'models', 'status', 'balance', 'usage', 'logout', 'doctor'];
  const labels = ['Install + OAuth setup', 'Install / update only', 'Log in', 'Choose model and start', 'Models', 'Login status', 'Balance', 'Usage', 'Revoke authorization and log out', 'Check installation'];
  while (true) {
    console.log('\nCodewhale + LMM');
    entries.forEach((_, i) => console.log(`${i + 1}  ${labels[i]}`));
    const choice = await ask('0  Back\n> ');
    if (choice === '0') return;
    if (!/^(?:[1-9]|10)$/.test(choice)) continue;
    const action = entries[Number(choice) - 1];
    if (action === 'logout' && (await ask('Revoke LMM authorization? [y/N] ')).toLowerCase() !== 'y') continue;
    try { await execute(action); }
    catch (error) { if (error.exitCode === 130) throw error; console.error(error.message); }
  }
}

try {
  if (process.argv[1] && import.meta.url === pathToFileURL(realpathSync(process.argv[1])).href) {
    await main().catch(error => { console.error(error.message); process.exitCode = error.exitCode || 1; });
  }
} catch (error) { console.error(error.message); process.exitCode = 1; }
