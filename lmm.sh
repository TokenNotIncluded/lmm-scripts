#!/usr/bin/env bash
lmm_install_main() {
# Generated from templates/ and versions.json. Edit the source, not this file.
set -euo pipefail
set +x
TARGET=lmm
SCRIPT_VERSION=2026.09.20.2
LMM_VERSION=0.1.0
LMM_RELEASE_BASE=https://github.com/TokenNotIncluded/api.lmm.best/releases/download/lmm-cli-v0.1.0
lmm_hash() { case "$1" in
  linux-x64) printf '%s\n' 292a1ff8b599466f52747867a0b14bd14860faefaa085cc60746040cd7eba9b7;;
  darwin-arm64) printf '%s\n' 8f6b3a2d08500566b528b7089664420d3395e464c172e3a43dfcb73d37f57b3f;;
  win-x64) printf '%s\n' d0eb3c3d3fe695eaa8a85de7c3161d0f7f17153064db5c20b8ced09defc574a9;;
  *) printf '\n';;
esac; }

lmm_root() {
  printf '%s\n' "${LMM_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/lmm-tools}"
}
sha256() {
  local digest
  if command -v sha256sum >/dev/null 2>&1; then digest=$(sha256sum "$1") || return; printf '%s\n' "${digest%% *}"
  elif command -v shasum >/dev/null 2>&1; then digest=$(shasum -a 256 "$1") || return; printf '%s\n' "${digest%% *}"
  elif command -v openssl >/dev/null 2>&1; then digest=$(openssl dgst -sha256 "$1") || return; printf '%s\n' "${digest##* }"
  else printf 'Install a SHA-256 tool.\n' >&2; return 1; fi
}
# Native Termux uses Android/bionic, not desktop Linux/glibc.
lmm_is_termux() {
  [ -n "${TERMUX_VERSION:-}${TERMUX_APP__PACKAGE_NAME:-}" ] ||
    case "${PREFIX:-}" in */com.termux/files/usr) true;; *) false;; esac
}
lmm_temp_root() {
  if [ -n "${TMPDIR:-}" ]; then printf '%s\n' "$TMPDIR"
  elif lmm_is_termux; then printf '%s/tmp\n' "${PREFIX:-$HOME/.cache/lmm-tools}"
  else printf '/tmp\n'; fi
}
lmm_check_storage() {
  lmm_is_termux || return 0
  local resolved
  # realpath -m also resolves missing paths and symlinked storage aliases.
  command -v realpath >/dev/null 2>&1 || {
    printf 'Termux needs coreutils: pkg install coreutils\n' >&2; return 1;
  }
  resolved=$(realpath -m -- "$1") || return 1
  case "$resolved/" in
    /sdcard/*|/storage/*|/mnt/sdcard/*|/mnt/media_rw/*|/mnt/runtime/*|/mnt/user/*|/mnt/pass_through/*)
      printf 'Use Termux private storage under HOME, not shared storage: %s\n' "$1" >&2
      return 1;;
  esac
}
quote_sh() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
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
  cat "$probe_dir"/* | sort -n -k1,1 -k2,2 | while read -r elapsed index; do printf '%s\n' "$index"; done
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
    if [ "$OS" = android ]; then
      fail 'No Android LMM CLI binary is provided. The Linux archive is not compatible with Termux.'
    fi
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
install_tool() { install_lmm; }

ROOT=$(lmm_root)
NETWORK=auto PROFILE=web CHECK=0 FORCE=0 LAUNCH=0 ADD_PATH=0 SOURCE=0
STAGE='' LOCKED=0 PHASE=arguments
RUN_ARGS=()

PNPM_BIN=''
log() { printf '[lmm %s] %s\n' "$TARGET" "$*" >&2; }
fail() { log "ERROR: $*"; exit 1; }
usage() {
  cat <<USAGE
LMM $TARGET installer $SCRIPT_VERSION
Usage: bash $TARGET.sh [options] [-- launch arguments]
  --check              Read-only environment/installation check
  --update             Reinstall the versions pinned in versions.json
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
No automatic login or PATH changes. Versions and platform notes: README.md.
USAGE
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0;;
    --check) CHECK=1;; --update) FORCE=1;; --launch) LAUNCH=1;;
    --add-path) ADD_PATH=1;; --no-path) ADD_PATH=0;; --install-only) LAUNCH=0;; --no-bootstrap) :;; --from-source) SOURCE=1;; --no-install-node) :;;
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
case "$ROOT" in /*) ;; *) ROOT="$PWD/$ROOT";; esac
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
case "$(uname -s)" in Linux|Android) OS=linux;; Darwin) OS=darwin;; *) fail 'Use the .ps1 script on Windows.';; esac
if lmm_is_termux; then OS=android; fi
case "$(uname -m)" in
  x86_64|amd64) ARCH=x64;; arm64|aarch64) ARCH=arm64;;
  armv7l|armv8l|arm) [ "$OS" = android ] || fail '32-bit desktop Linux is not supported'; ARCH=arm;;
  i386|i686) [ "$OS" = android ] || fail '32-bit desktop Linux is not supported'; ARCH=ia32;;
  *) fail 'Unsupported CPU';;
esac
PLATFORM="$OS-$ARCH"
lmm_check_storage "$ROOT" || exit 1
lmm_check_storage "$CACHE" || exit 1
if [ "$OS" = android ] && [ "$TARGET" != lmm ]; then
  compatible_node || fail 'In Termux, install native Node/npm: pkg install nodejs npm git; then rerun. Desktop Node cannot run on Android.'
  command -v git >/dev/null 2>&1 || fail 'Pi/DSH need git: pkg install git'
fi
# --check never creates directories, downloads, edits PATH or touches credentials.
if [ "$CHECK" = 1 ]; then
  log "Platform: $PLATFORM; install root: $ROOT"
  if [ -x "$ROOT/bin/$TARGET" ]; then "$ROOT/bin/$TARGET" --version
  elif command -v "$TARGET" >/dev/null 2>&1; then "$TARGET" --version
  else log "$TARGET is not installed in this root or PATH"; exit 1; fi

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
if [ "$OS" = android ]; then
  TMPDIR=$(lmm_temp_root); lmm_check_storage "$TMPDIR" || exit 1
  mkdir -p "$TMPDIR"; export TMPDIR
  if [ "$TARGET" = dsh ]; then log 'DSH native dependencies have not been validated on Android.'; fi
fi
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
write_launcher() {
  local launcher="$ROOT/bin/$TARGET" temp="$STAGE/launcher"
  {
    if [ "$OS" = android ]; then printf '#!%s\n' "$BASH"
    else printf '#!/usr/bin/env bash\n'; fi
    printf '# Managed by LMM installers.\n' 
    # The launcher must expand PATH when it runs, not while it is generated.
    # shellcheck disable=SC2016
    if [ "$TARGET" != lmm ]; then printf 'export PATH=%s:"$PATH"\n' "$(quote_sh "$NODE_BIN${PNPM_BIN:+:$PNPM_BIN}")"; fi
    if [ "$TARGET" = lmm ]; then printf 'exec %s "$@"\n' "$(quote_sh "$CLIENT")"
    else printf 'exec %s %s "$@"\n' "$(quote_sh "$NODE_BIN/node")" "$(quote_sh "$CLIENT")"; fi
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
install_tool
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
