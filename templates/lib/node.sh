compatible_node() {
  command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 &&
    node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit(((a===22&&b>=19)||a>=24)&&(process.argv[1]!=="android"||process.platform==="android")?0:1)' "$OS" >/dev/null 2>&1
}
ensure_node() {
  PHASE='Node.js runtime'
  if compatible_node; then NODE_BIN=$(dirname "$(command -v node)"); log "Using Node $(node --version)"; return; fi
  [ "$OS" != android ] || fail 'In Termux, run pkg install nodejs npm git; desktop Node archives are incompatible.'
  local dir="$ROOT/runtime/node-v$NODE_VERSION-$PLATFORM" hash archive
  if [ -x "$dir/bin/node" ]; then export PATH="$dir/bin:$PATH"; fi
  if compatible_node; then NODE_BIN="$dir/bin"; return; fi
  [ "$INSTALL_NODE" = 1 ] || fail 'Need Node 22.19+ (22.x) or Node 24+, including npm.'
  [ ! -f /etc/alpine-release ] || fail 'On Alpine install nodejs/npm with apk first; official Node archives require glibc.'
  hash=$(node_hash "$PLATFORM")
  [ -n "$hash" ] || fail "No verified Node archive for $PLATFORM"
  archive="$CACHE/node-v$NODE_VERSION-$PLATFORM.tar.gz"
  download "https://nodejs.org/dist/v$NODE_VERSION/${archive##*/}" "$archive" "$hash"
  mkdir -p "$STAGE/runtime"
  tar -xzf "$archive" -C "$STAGE/runtime"
  "$STAGE/runtime/node-v$NODE_VERSION-$PLATFORM/bin/node" --version >/dev/null || fail 'Node cannot run on this OS/libc. Install compatible Node using your OS package manager.'
  [ ! -e "$dir" ] || fail "Managed runtime exists but is unusable: $dir. Inspect it before replacing."
  mv -- "$STAGE/runtime/node-v$NODE_VERSION-$PLATFORM" "$dir"
  NODE_BIN="$dir/bin"; export PATH="$NODE_BIN:$PATH"
}
configure_npm() {
  if [ -z "${npm_config_cache:-}" ]; then
    npm_config_cache=$(npm config get cache 2>/dev/null || true)
    case "$npm_config_cache" in /*) ;; *) npm_config_cache="$CACHE/npm";; esac
    export npm_config_cache
  fi
  export npm_config_fetch_retries="$RETRIES" npm_config_fetch_timeout="$((STALL_TIMEOUT * 1000))"
  export npm_config_fetch_retry_mintimeout=2000 npm_config_fetch_retry_maxtimeout=30000
  export npm_config_strict_ssl=true
  if [ -n "${LMM_NPM_REGISTRY:-}" ]; then export npm_config_registry="$LMM_NPM_REGISTRY"; fi
  export npm_config_prefer_offline=true
  local current order first
  current=$(npm config get registry 2>/dev/null || true)
  if [ -n "${npm_config_registry:-}" ] || { [ -n "$current" ] && [ "$current" != https://registry.npmjs.org/ ]; }; then
    log 'Keeping your existing npm registry/proxy configuration.'; return
  fi
  NPM_SELECTED=1
  case "$NETWORK" in
    official) export npm_config_registry=https://registry.npmjs.org/;;
    china) export npm_config_registry=https://registry.npmmirror.com/;;
    auto)
      order=$(rank_urls https://registry.npmjs.org/ https://registry.npmmirror.com/)
      first=${order%%$'\n'*}
      if [ "$first" = 1 ]; then export npm_config_registry=https://registry.npmmirror.com/; else export npm_config_registry=https://registry.npmjs.org/; fi;;
  esac
  log 'Selected a registry for this installer process only; global npm settings are unchanged.'
}
bounded() {
  node - "$COMMAND_TIMEOUT" "$@" <<'JS'
const {spawn} = require('node:child_process');
const {signals} = require('node:os').constants;
const [seconds, command, ...args] = process.argv.slice(2);
const child = spawn(command, args, {stdio: 'inherit', detached: true});
let stopCode;
const start = Date.now();
const heartbeat = setInterval(() => {
  process.stderr.write(`[install] Still working: ${Math.floor((Date.now() - start) / 1000)}s elapsed.\n`);
}, 15000);
const timeout = setTimeout(() => {
  process.stderr.write('[install] Operation timed out; increase LMM_COMMAND_TIMEOUT for a slow connection.\n');
  stop(124);
}, Number(seconds) * 1000);
function clearTimers() {
  clearInterval(heartbeat);
  clearTimeout(timeout);
}
function signalGroup(signal) {
  if (!child.pid) return;
  try { process.kill(-child.pid, signal); }
  catch (error) {
    if (error.code !== 'ESRCH') process.stderr.write(`[install] Cannot send ${signal}: ${error.code}\n`);
  }
}
function stop(code) {
  if (stopCode !== undefined) return;
  stopCode = code;
  process.exitCode = code;
  clearTimers();
  signalGroup('SIGTERM');
  // Keep this timer referenced: the leader can exit while descendants survive.
  if (child.pid) setTimeout(() => signalGroup('SIGKILL'), 3000);
}
process.on('SIGINT', () => stop(130));
process.on('SIGTERM', () => stop(143));
child.on('error', error => {
  clearTimers();
  process.stderr.write(`[install] Cannot start ${command}: ${error.code}\n`);
  process.exitCode = stopCode ?? 1;
});
child.on('exit', (code, signal) => {
  clearTimers();
  process.exitCode = stopCode ?? code ?? (signal ? 128 + signals[signal] : 1);
});
JS
}
with_registry_retry() {
  local status=0
  bounded "$@" || status=$?
  # Cancellation is not a network failure. Preserve it without another install.
  case "$status" in 0) return;; 130|143) return "$status";; esac
  if [ "$NETWORK" = auto ] && [ "$NPM_SELECTED" = 1 ]; then
    if [ "$npm_config_registry" = https://registry.npmjs.org/ ]; then export npm_config_registry=https://registry.npmmirror.com/; else export npm_config_registry=https://registry.npmjs.org/; fi
    log 'Retrying the alternate registry with the same package cache.'
    bounded "$@"
  else fail 'Package installation failed. Check network/proxy settings or try another --network mode.'; fi
}
install_client() {
  local package=$1 version=$2 entry=$3 target="$ROOT/apps/$TARGET/$2" work="$STAGE/client" allow
  PHASE="$TARGET client"
  if [ "$FORCE" = 0 ] && [ -x "$target/bin/$entry" ] && [ -f "$target/.lmm-managed" ] && [ "$(cat "$target/.lmm-managed")" = "$version|$SCRIPT_VERSION" ]; then CLIENT="$target/bin/$entry"; log "Client $version already installed."; return; fi
  [ "$BOOTSTRAP" = 1 ] || fail 'Managed client is missing; rerun without --no-bootstrap.'
  mkdir -p "$work"
  INSTALL_ARGS=(install --global --prefix "$work" --no-audit --no-fund "$package@$version")
  if [ "$TARGET" = pi ]; then
    # https://pi.dev/docs/latest/quickstart: Pi ships a prebuilt CLI.
    INSTALL_ARGS+=(--ignore-scripts)
  else
    allow='@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs'
    if npm install --help 2>/dev/null | grep -q -- '--allow-scripts'; then INSTALL_ARGS+=("--allow-scripts=$allow"); fi
    [ "$(npm config get ignore-scripts 2>/dev/null || true)" != true ] || fail 'DSH needs native build scripts. Review your package-specific build policy; this installer will not override ignore-scripts=true.'
  fi
  with_registry_retry npm "${INSTALL_ARGS[@]}"
  node "$work/bin/$entry" --version >/dev/null
  printf '%s\n' "$version|$SCRIPT_VERSION" > "$work/.lmm-managed"
  mkdir -p "$(dirname "$target")"
  if [ -e "$target" ]; then
    [ -f "$target/.lmm-managed" ] || fail "Not replacing an unowned directory: $target"
    target="$target-reinstall-$(date +%s)-$$"
  fi
  mv -- "$work" "$target"
  CLIENT="$target/bin/$entry"
}
