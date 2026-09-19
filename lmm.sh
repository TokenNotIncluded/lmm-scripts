#!/usr/bin/env bash
lmm_install_main() {
# Generated from templates/install.sh.in and versions.json. No sudo, no API keys.
set -euo pipefail
set +x
TARGET=lmm
SCRIPT_VERSION=2026.09.19.1
NODE_VERSION=24.21.0
PI_VERSION=0.85.1
PI_PROVIDER_VERSION=0.1.0-alpha.1
DSH_VERSION=0.1.5-rc.2
DSH_PROVIDER_URL=https://github.com/TokenNotIncluded/dsh-lmm-provider/releases/download/v0.1.0-alpha.2/tokennotincluded-dsh-lmm-provider-0.1.0-alpha.2.tgz
DSH_PROVIDER_SHA256=609eba9f1516cadf7086e44d290752d1361ac607eb1d1cb5682abfa5e806304d
LMM_VERSION=0.1.0
LMM_RELEASE_BASE=https://github.com/TokenNotIncluded/api.lmm.best/releases/download/lmm-cli-v0.1.0
node_hash() { case "$1" in
  linux-x64) printf '%s\n' 6e1db87ef58b8819e5d5402eff1536491b18edd8eb7bee5ef7897876e88dc5ff;;
  linux-arm64) printf '%s\n' 724282c3b43aec998aa9527380465b45d229e021b58035f5f4f63095eabfe5d5;;
  darwin-x64) printf '%s\n' 1462cb3b3046b815cf8ea436d3da450ec1a9f11dac7e5a46b0ada5305d7e8097;;
  darwin-arm64) printf '%s\n' bed7eea5325e1108f32ce5228ddd6a5f0f08a499ee42aa7442aea583702f6057;;
  win-x64) printf '%s\n' 158f7685b44de51f6c0df1d153526cbcd3e1bc739a8dfc607721cef75de9e541;;
  win-arm64) printf '%s\n' 8779b1bde1d39f8d420e3b57aa657b39891af434d3de44a919044cec06785921;;
  *) printf '\n';;
esac; }
lmm_hash() { case "$1" in
  linux-x64) printf '%s\n' 292a1ff8b599466f52747867a0b14bd14860faefaa085cc60746040cd7eba9b7;;
  darwin-arm64) printf '%s\n' 8f6b3a2d08500566b528b7089664420d3395e464c172e3a43dfcb73d37f57b3f;;
  win-x64) printf '%s\n' d0eb3c3d3fe695eaa8a85de7c3161d0f7f17153064db5c20b8ced09defc574a9;;
  *) printf '\n';;
esac; }

ROOT=${LMM_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/lmm-tools}
NETWORK=auto PROFILE=web CHECK=0 FORCE=0 LAUNCH=0 ADD_PATH=0 SOURCE=0 INSTALL_NODE=1
STAGE='' LOCKED=0 PHASE=arguments BOOTSTRAP=1
RUN_ARGS=()
NPM_SELECTED=0
log() { printf '[lmm %s] %s\n' "$TARGET" "$*" >&2; }
fail() { log "ERROR: $*"; exit 1; }
usage() {
  cat <<USAGE
LMM $TARGET installer $SCRIPT_VERSION
Usage: bash $TARGET.sh [options] [-- launch arguments]
  --check              Read-only environment/installation check
  --update             Reinstall the versions tested by this script
  --root PATH          User-owned install directory (default: $ROOT)
  --network MODE       auto (latency probes), official, or china
  --profile NAME       DSH: web or headless (default: web)
  --no-install-node    Require an existing compatible Node/npm
  --add-path           Opt in to adding a backed-up shell PATH entry
  --no-path            Keep startup files unchanged (default)
  --install-only       Compatibility alias: do not launch
  --no-bootstrap       Require existing compatible Node and managed client
  --from-source        LMM CLI: build the pinned crate using existing Rust 1.88+
  --launch             Start the installed tool (DSH starts the chosen profile)
  --help               Show this help
Installs in user space. Existing system Node, npm configuration and login data
are not replaced. Downloads are cached, resumed and SHA-256 checked. Proxy/CA
settings are inherited. No login, paid call or OS package install is automatic.
USAGE
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0;;
    --check) CHECK=1;; --update) FORCE=1;; --launch) LAUNCH=1;;
    --add-path) ADD_PATH=1;; --no-path) ADD_PATH=0;; --install-only) LAUNCH=0;; --no-bootstrap) INSTALL_NODE=0; BOOTSTRAP=0;; --from-source) SOURCE=1;; --no-install-node) INSTALL_NODE=0;;
    --root|--network|--profile)
      if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then fail "$1 requires a value"; fi
      case "$1" in --root) ROOT=$2;; --network) NETWORK=$2;; --profile) PROFILE=$2;; esac; shift;;
    --) shift; RUN_ARGS=("$@"); break;;
    *) fail "Unknown option: $1 (use --help)";;
  esac
  shift
done
RETRIES=${LMM_RETRIES:-3}
CONNECT_TIMEOUT=${LMM_CONNECT_TIMEOUT:-10}
STALL_TIMEOUT=${LMM_STALL_TIMEOUT:-20}
DOWNLOAD_TIMEOUT=${LMM_DOWNLOAD_TIMEOUT:-600}
COMMAND_TIMEOUT=${LMM_COMMAND_TIMEOUT:-1800}
MIN_SPEED=${LMM_MIN_SPEED_BYTES:-16384}
for setting in "$RETRIES" "$CONNECT_TIMEOUT" "$STALL_TIMEOUT" "$DOWNLOAD_TIMEOUT" "$COMMAND_TIMEOUT" "$MIN_SPEED"; do
  [[ $setting =~ ^[1-9][0-9]*$ && ${#setting} -le 8 ]] || fail 'Timeouts, retry counts and minimum speed must be positive integers.'
done
((RETRIES <= 10 && CONNECT_TIMEOUT <= 300 && STALL_TIMEOUT <= 86400 && DOWNLOAD_TIMEOUT <= 86400 && COMMAND_TIMEOUT <= 86400 && MIN_SPEED <= 10485760)) || fail 'Network setting exceeds supported limits.'
CACHE=${LMM_CACHE_ROOT:-$ROOT/cache}
case "$CACHE" in /*) ;; *) fail 'LMM_CACHE_ROOT must be an absolute path';; esac
if [ "$CACHE" = / ] || [ -L "$ROOT" ] || [ -L "$CACHE" ]; then fail 'Refusing root or symlink installation/cache paths.'; fi
for custom in "${LMM_NODE_BASE_URL:-}" "${LMM_NPM_REGISTRY:-}"; do
  if [ -n "$custom" ]; then case "$custom" in https://*) ;; *) fail 'Custom mirrors must use HTTPS';; esac
    case "$custom" in *'@'*|*$'\n'*|*$'\r'*) fail 'Custom mirrors must not contain embedded credentials or newlines';; esac
  fi
done
case "$NETWORK" in auto|official|china) ;; *) fail 'network must be auto, official or china';; esac
case "$PROFILE" in web|headless) ;; *) fail 'profile must be web or headless';; esac
[ "$TARGET" = lmm ] || [ "$SOURCE" = 0 ] || fail '--from-source is only for lmm'
case "$ROOT" in *$'\n'*|*$'\r'*) fail 'Install path must not contain newlines';; /*) ;; *) ROOT="$PWD/$ROOT";; esac
if [ "$ROOT" = / ] || [ "$ROOT" = "$HOME" ]; then fail 'Choose a dedicated installation directory'; fi
case "$(uname -s)" in Linux) OS=linux;; Darwin) OS=darwin;; *) fail 'This script supports Linux/macOS. On Windows use the .ps1 script.';; esac
case "$(uname -m)" in x86_64|amd64) ARCH=x64;; arm64|aarch64) ARCH=arm64;; *) fail 'Unsupported CPU; use the documented source build on this platform.';; esac
PLATFORM="$OS-$ARCH"
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$1" | awk '{print $NF}'
  else fail 'Install a SHA-256 tool (sha256sum, shasum or openssl)'; fi
}
compatible_node() {
  command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 &&
    node -e 'const [a,b]=process.versions.node.split(".").map(Number);process.exit((a===22&&b>=19)||a>=24?0:1)' >/dev/null 2>&1
}
# --check never creates directories, downloads, edits PATH or touches credentials.
if [ "$CHECK" = 1 ]; then
  log "Platform: $PLATFORM; install root: $ROOT"
  if [ -x "$ROOT/bin/$TARGET" ]; then "$ROOT/bin/$TARGET" --version
  elif command -v "$TARGET" >/dev/null 2>&1; then "$TARGET" --version
  else log "$TARGET is not installed in this root or PATH"; exit 1; fi
  if [ "$TARGET" != lmm ]; then
    if compatible_node; then log 'Current PATH has compatible Node/npm.'
    elif [ -x "$ROOT/runtime/node-v$NODE_VERSION-$PLATFORM/bin/node" ]; then log 'Managed Node runtime is available.'
    else fail 'No compatible Node runtime found'; fi
  fi
  log 'Executable check complete; login and model access are not inferred.'
  exit 0
fi
release_setup() {
  if [ -n "$STAGE" ] && [ -d "$STAGE" ]; then rm -rf -- "$STAGE"; fi
  STAGE=''
  if [ "$LOCKED" = 1 ] && [ "$(cat "$ROOT/.setup-lock/pid" 2>/dev/null || true)" = "$$" ]; then
    rm -f -- "$ROOT/.setup-lock/pid" "$ROOT/.setup-lock/owner"
    rmdir "$ROOT/.setup-lock" 2>/dev/null || true
  fi
  LOCKED=0
}
cleanup() {
  rc=$?
  trap - EXIT
  release_setup
  if [ "$rc" -ne 0 ]; then
    log "Stopped during $PHASE. Existing launchers were preserved unless installation already completed."
    log 'Check disk space, HTTPS proxy/CA settings, or retry --network official / --network china. Do not disable TLS validation.'
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
umask 077
mkdir -p "$ROOT" "$CACHE" "$ROOT/bin" "$ROOT/apps" "$ROOT/runtime"
ROOT=$(cd "$ROOT" && pwd -P)
if ! mkdir "$ROOT/.setup-lock" 2>/dev/null; then
  oldpid=$(cat "$ROOT/.setup-lock/pid" 2>/dev/null || true)
  case "$oldpid" in ''|*[!0-9]*) fail "Unknown lock at $ROOT/.setup-lock; inspect it before removing";; esac
  if kill -0 "$oldpid" 2>/dev/null; then fail "Another installer is running (PID $oldpid)"; fi
  [ "$(cat "$ROOT/.setup-lock/owner" 2>/dev/null || true)" = lmm-installer-v1 ] || fail 'Unknown lock owner'
  rm -- "$ROOT/.setup-lock/pid" "$ROOT/.setup-lock/owner"
  rmdir "$ROOT/.setup-lock" || fail 'Lock contains unexpected files; left it untouched'
  mkdir "$ROOT/.setup-lock"
fi
printf '%s\n' "$$" > "$ROOT/.setup-lock/pid"
printf '%s\n' lmm-installer-v1 > "$ROOT/.setup-lock/owner"
LOCKED=1
STAGE=$(mktemp -d "$ROOT/.setup.XXXXXX")
# Probe only public, credential-free artifact URLs. Slow transfers are still
# interrupted independently of the latency ranking below.
rank_urls() {
  local i=0 url response code elapsed probe_dir
  if ! command -v curl >/dev/null 2>&1; then for url in "$@"; do printf '%s\n' "$i"; i=$((i+1)); done; return; fi
  probe_dir=$(mktemp -d "$STAGE/probes.XXXXXX")
  for url in "$@"; do
    (
      response=$(curl -q --proto '=https' --proto-redir '=https' -ILs --connect-timeout 3 --max-time 5 -o /dev/null -w '%{http_code} %{time_starttransfer}' "$url" 2>/dev/null || true)
      code=${response%% *}; elapsed=${response#* }
      case "$code" in 2??|3??) ;; *) elapsed=999;; esac
      case "$elapsed" in ''|*[!0-9.]*) elapsed=999;; esac
      printf '%s %s\n' "$elapsed" "$i" > "$probe_dir/$i"
    ) &
    i=$((i+1))
  done
  wait
  cat "$probe_dir"/* | sort -n -k1,1 -k2,2 | awk '{print $2}'
}
urls_for() {
  URLS=("$1")
  case "$1" in
    https://nodejs.org/dist/*) MIRRORS=("https://npmmirror.com/mirrors/node/${1#https://nodejs.org/dist/}");;
    https://github.com/*) MIRRORS=("https://ghfast.top/$1" "https://ghproxy.net/$1");;
    *) MIRRORS=();;
  esac
  case "$NETWORK" in
    auto) URLS+=("${MIRRORS[@]}");;
    china) URLS=("${MIRRORS[@]}" "$1");;
  esac
}
download() {
  local official=$1 destination=$2 expected=$3 index url part attempt actual order transfer_status
  part="$destination.part"
  if [ -L "$destination" ] || [ -L "$part" ] || [ -L "$part.url" ]; then fail 'Refusing symlink cache entries'; fi
  if [ "$FORCE" = 0 ] && [ -f "$destination" ] && [ "$(sha256 "$destination")" = "$expected" ]; then log "Cached: ${destination##*/}"; return; fi
  if [ -f "$part" ] && [ "$(sha256 "$part")" = "$expected" ]; then mv -f -- "$part" "$destination"; rm -f -- "$part.url"; return; fi
  command -v curl >/dev/null 2>&1 || fail 'curl is required for downloads. Install it with your OS package manager.'
  if [[ $official == https://nodejs.org/dist/* && -n ${LMM_NODE_BASE_URL:-} ]]; then official="${LMM_NODE_BASE_URL%/}/${official#https://nodejs.org/dist/}"; fi
  urls_for "$official"
  if [ "$NETWORK" = auto ]; then order=$(rank_urls "${URLS[@]}"); else order=$(printf '%s\n' "${!URLS[@]}"); fi
  for index in $order; do
    url=${URLS[$index]}
    if [ -f "$part" ] && [ "$(cat "$part.url" 2>/dev/null || true)" != "$url" ]; then rm -f -- "$part"; fi
    printf '%s\n' "$url" > "$part.url"
    for ((attempt=1; attempt<=RETRIES; attempt++)); do
      log "Downloading ${destination##*/} (source $((index+1)), attempt $attempt; low-speed cutoff ${STALL_TIMEOUT}s)"
      if curl -q --proto '=https' --proto-redir '=https' -fL --connect-timeout "$CONNECT_TIMEOUT" --max-time "$DOWNLOAD_TIMEOUT" --speed-time "$STALL_TIMEOUT" --speed-limit "$MIN_SPEED" --continue-at - --output "$part" "$url"; then
        actual=$(sha256 "$part")
        if [ "$actual" = "$expected" ]; then mv -f -- "$part" "$destination"; rm -f -- "$part.url"; return; fi
        log 'Checksum mismatch: discarded the download; it will not be executed.'
        rm -f -- "$part"
        break
      else transfer_status=$?; fi
      # A server may reject Range; retry once from a clean file. Retain a
      # partial transfer after final failure for the next invocation.
      if [ "$attempt" = 1 ]; then case "$transfer_status" in 22|33|36) rm -f -- "$part";; esac; fi
    done
  done
  fail "Download failed: ${destination##*/}. Rerun to resume, or choose another --network mode."
}
ensure_node() {
  PHASE='Node.js runtime'
  if compatible_node; then NODE_BIN=$(dirname "$(command -v node)"); log "Using Node $(node --version)"; return; fi
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
const {spawn}=require('node:child_process');
const [seconds,command,...args]=process.argv.slice(2);
const child=spawn(command,args,{stdio:'inherit',detached:true});
let timedOut=false,stopping=false;
function stop(code){if(stopping)return;stopping=true;timedOut=code===124;try{process.kill(-child.pid,'SIGTERM')}catch{};const hard=setTimeout(()=>{try{process.kill(-child.pid,'SIGKILL')}catch{}},3000);hard.unref()}
const start=Date.now();const heartbeat=setInterval(()=>process.stderr.write(`[install] Still working: ${Math.floor((Date.now()-start)/1000)}s elapsed.\n`),15000);
const timeout=setTimeout(()=>{process.stderr.write('[install] Operation timed out; increase LMM_COMMAND_TIMEOUT for a slow connection.\n');stop(124)},Number(seconds)*1000);
process.on('SIGINT',()=>stop(130));process.on('SIGTERM',()=>stop(143));
child.on('error',e=>{clearInterval(heartbeat);clearTimeout(timeout);process.stderr.write(`[install] Cannot start ${command}: ${e.code}\n`);process.exitCode=1});
child.on('exit',(code,signal)=>{clearInterval(heartbeat);clearTimeout(timeout);process.exitCode=timedOut?124:signal?130:code??1});
JS
}
with_registry_retry() {
  if bounded "$@"; then return; fi
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
  case "$TARGET" in
    pi) allow='esbuild,@google/genai,protobufjs';;
    dsh) allow='@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs';;
  esac
  INSTALL_ARGS=(install --global --prefix "$work" --no-audit --no-fund "$package@$version")
  if npm install --help 2>/dev/null | grep -q -- '--allow-scripts'; then INSTALL_ARGS+=("--allow-scripts=$allow"); fi
  [ "$(npm config get ignore-scripts 2>/dev/null || true)" != true ] || fail 'Your npm configuration disables required native build scripts. Configure a package-specific build policy before installing this client.'
  with_registry_retry npm "${INSTALL_ARGS[@]}"
  "$work/bin/$entry" --version >/dev/null
  printf '%s\n' "$version|$SCRIPT_VERSION" > "$work/.lmm-managed"
  mkdir -p "$(dirname "$target")"
  if [ -e "$target" ]; then
    [ -f "$target/.lmm-managed" ] || fail "Not replacing an unowned directory: $target"
    target="$target-reinstall-$(date +%s)-$$"
  fi
  mv -- "$work" "$target"
  CLIENT="$target/bin/$entry"
}
install_lmm() {
  PHASE='LMM CLI'
  local hash target="$ROOT/apps/lmm/$LMM_VERSION-$PLATFORM" archive
  if [ "$FORCE" = 0 ] && [ -x "$target/lmm" ] && [ -f "$target/.lmm-managed" ]; then CLIENT="$target/lmm"; return; fi
  mkdir -p "$STAGE/lmm"
  if [ "$SOURCE" = 1 ]; then
    command -v cargo >/dev/null 2>&1 || fail 'Source builds need Rust 1.88+ and OS build tools. Install them first, then rerun --from-source.'
    log 'Building the pinned crate; Cargo reuses its existing dependency/build caches. This can take several minutes.'
    export CARGO_HTTP_TIMEOUT="$STALL_TIMEOUT" CARGO_NET_RETRY="$RETRIES"
    export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$CACHE/cargo-target}
    cargo install lmm-cli --version "$LMM_VERSION" --locked --root "$STAGE/cargo" </dev/null
    cp -- "$STAGE/cargo/bin/lmm" "$STAGE/lmm/lmm"
  else
    hash=$(lmm_hash "$PLATFORM")
    [ -n "$hash" ] || fail "No prebuilt CLI for $PLATFORM yet. With Rust 1.88+ and build tools, use --from-source."
    archive="$CACHE/lmm-v$LMM_VERSION-$PLATFORM.tar.gz"
    download "$LMM_RELEASE_BASE/${archive##*/}" "$archive" "$hash"
    tar -xzf "$archive" -C "$STAGE/lmm"
  fi
  chmod +x "$STAGE/lmm/lmm"
  "$STAGE/lmm/lmm" --version >/dev/null || fail 'CLI cannot run here. Linux x64 preview binaries need glibc 2.39+; use --from-source on older Linux.'
  printf '%s\n' "$LMM_VERSION" > "$STAGE/lmm/.lmm-managed"
  mkdir -p "$(dirname "$target")"
  if [ -e "$target" ]; then [ -f "$target/.lmm-managed" ] || fail "Unowned path: $target"; target="$target-reinstall-$(date +%s)-$$"; fi
  mv -- "$STAGE/lmm" "$target"; CLIENT="$target/lmm"
}
quote_sh() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
write_launcher() {
  local launcher="$ROOT/bin/$TARGET" temp="$STAGE/launcher"
  {
    printf '#!/usr/bin/env bash\n# Managed by LMM installers.\n'
    # The launcher must expand PATH when it runs, not while it is generated.
    # shellcheck disable=SC2016
    if [ "$TARGET" != lmm ]; then printf 'export PATH=%s:"$PATH"\n' "$(quote_sh "$NODE_BIN")"; fi
    printf 'exec %s "$@"\n' "$(quote_sh "$CLIENT")"
  } > "$temp"
  chmod +x "$temp"
  if [ -e "$launcher" ] && ! grep -q '# Managed by LMM installers.' "$launcher"; then fail "Refusing to overwrite your existing launcher: $launcher"; fi
  mv -f -- "$temp" "$launcher"
}
add_path() {
  [ "$ADD_PATH" = 1 ] || return 0
  local file marker='# >>> LMM tools PATH >>>' line
  line="export PATH=$(quote_sh "$ROOT/bin"):\"\$PATH\""
  PATH_FILES=("$HOME/.profile")
  case "${SHELL:-}" in */zsh) PATH_FILES+=("$HOME/.zshrc");; */bash) PATH_FILES+=("$HOME/.bashrc"); [ "$OS" != darwin ] || PATH_FILES+=("$HOME/.bash_profile");; */fish) log 'Fish users: add the printed bin directory with fish_add_path.';; esac
  for file in "${PATH_FILES[@]}"; do
    if [ -f "$file" ] && grep -Fq "$marker" "$file"; then
      grep -Fq "$line" "$file" || log "PATH marker already exists in $file; use the printed full command or adjust that entry manually."
      continue
    fi
    [ ! -L "$file" ] || { log "Not editing symlinked startup file: $file"; continue; }
    if [ -f "$file" ]; then cp -p -- "$file" "$file.lmm-backup-$(date +%Y%m%d%H%M%S)-$$"; fi
    printf '\n%s\n%s\n# <<< LMM tools PATH <<<\n' "$marker" "$line" >> "$file"
  done
}
if [ "$TARGET" = lmm ]; then install_lmm
else
  ensure_node; configure_npm
  if [ "$TARGET" = pi ]; then
    install_client @earendil-works/pi-coding-agent "$PI_VERSION" pi
    PHASE='Pi LMM provider'; with_registry_retry "$CLIENT" install "npm:@tokennotincluded/pi-lmm-provider@$PI_PROVIDER_VERSION"
  else
    install_client @deepseek-ai/dsh "$DSH_VERSION" dsh
    PHASE='DSH LMM provider'
    artifact="$CACHE/${DSH_PROVIDER_URL##*/}"
    download "$DSH_PROVIDER_URL" "$artifact" "$DSH_PROVIDER_SHA256"
    with_registry_retry "$CLIENT" plugin --profile "$PROFILE" add "$artifact" --ignore-scripts --store-dir "$CACHE/pnpm"
  fi
fi
PHASE='launchers and PATH'; write_launcher; add_path
log "Ready: $ROOT/bin/$TARGET"
log "Use the full command above, or for this terminal: export PATH=$(quote_sh "$ROOT/bin"):\"\$PATH\""
case "$TARGET" in
  pi) log 'Run pi, then /login -> LMM -> browser approval -> /model.';;
  dsh) log 'Run dsh web -> Settings -> Models -> LMM -> Sign in with LMM -> Open LMM sign-in.'; log 'For headless use, first sign in through a Web profile sharing the same DSH_HOME.';;
  lmm) log 'Preview: lmm catalog; lmm status; lmm doctor --report; lmm login; lmm models --json.'; log 'Linux login needs a running Secret Service. Application setup is still dry-run only.';;
esac
if [ "$LAUNCH" = 1 ]; then
  PHASE='launch'
  if [ "$TARGET" = lmm ] && [ "${#RUN_ARGS[@]}" = 0 ]; then RUN_ARGS=(--help); fi
  release_setup
  trap - EXIT INT TERM
  if [ "$TARGET" = dsh ]; then exec "$ROOT/bin/dsh" --profile "$PROFILE" ${RUN_ARGS[@]+"${RUN_ARGS[@]}"}
  elif [ "$TARGET" = pi ] && [ ! -t 0 ] && [ "${#RUN_ARGS[@]}" = 0 ]; then
    if { true </dev/tty; } 2>/dev/null; then exec "$ROOT/bin/pi" </dev/tty; else fail 'Pi needs an interactive terminal; use the printed command.'; fi
  else exec "$ROOT/bin/$TARGET" ${RUN_ARGS[@]+"${RUN_ARGS[@]}"}; fi
fi

}
if true; then
  lmm_install_main "$@"
fi
