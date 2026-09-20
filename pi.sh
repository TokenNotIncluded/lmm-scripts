#!/usr/bin/env bash
# State is consumed by fetched modules.
# shellcheck disable=SC2034
lmm_install_main() {
# Generated from templates/ and versions.json. Edit the source, not this file.
set -euo pipefail
set +x
TARGET=pi
SCRIPT_VERSION=2026.09.20.4
LIB_REVISION=60692bd80622a0d3d80ee501eacb8db139641a3e
NODE_VERSION=24.21.0
PI_VERSION=0.85.1
PI_PROVIDER_VERSION=0.1.0-alpha.1
node_hash() { case "$1" in
  linux-x64) printf '%s\n' 6e1db87ef58b8819e5d5402eff1536491b18edd8eb7bee5ef7897876e88dc5ff;;
  linux-arm64) printf '%s\n' 724282c3b43aec998aa9527380465b45d229e021b58035f5f4f63095eabfe5d5;;
  darwin-x64) printf '%s\n' 1462cb3b3046b815cf8ea436d3da450ec1a9f11dac7e5a46b0ada5305d7e8097;;
  darwin-arm64) printf '%s\n' bed7eea5325e1108f32ce5228ddd6a5f0f08a499ee42aa7442aea583702f6057;;
  win-x64) printf '%s\n' 158f7685b44de51f6c0df1d153526cbcd3e1bc739a8dfc607721cef75de9e541;;
  win-arm64) printf '%s\n' 8779b1bde1d39f8d420e3b57aa657b39891af434d3de44a919044cec06785921;;
  *) printf '\n';;
esac; }

# Fetch completely before sourcing: process substitution alone hides curl errors.
lmm_source_lib() {
  local lmm_name=$1 lmm_text='' lmm_attempt
  if [ -n "${LMM_LIB_DIR:-}" ]; then
    lmm_text=$(cat -- "$LMM_LIB_DIR/$lmm_name") || {
      printf 'Cannot read local library: %s/%s\n' "$LMM_LIB_DIR" "$lmm_name" >&2; return 1;
    }
  else
    for lmm_attempt in 1 2 3; do
      if lmm_text=$(curl -q -fsSL --proto '=https' --proto-redir '=https' \
          --connect-timeout 10 --max-time 60 \
          "https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/$LIB_REVISION/templates/lib/$lmm_name"); then
        break
      fi
      if [ "$lmm_attempt" = 3 ]; then
        printf 'Cannot load library %s at %s. Check the network or set LMM_LIB_DIR.\n' "$lmm_name" "$LIB_REVISION" >&2
        return 1
      fi
    done
  fi
  if [[ $lmm_text != *[![:space:]]* ]]; then
    printf 'Cannot load library %s at %s. Check the network or set LMM_LIB_DIR.\n' "$lmm_name" "$LIB_REVISION" >&2
    return 1
  fi
  # macOS Bash 3.2 needs a here-string when sourcing buffered text.
  if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    # shellcheck disable=SC1091
    source /dev/stdin <<< "$lmm_text"
  else
    # shellcheck disable=SC1090
    source <(printf '%s\n' "$lmm_text")
  fi
}

install_tool() {
  ensure_node; configure_npm
  install_client @earendil-works/pi-coding-agent "$PI_VERSION" pi
  PHASE='Pi LMM provider'
  with_registry_retry node "$CLIENT" install "npm:@tokennotincluded/pi-lmm-provider@$PI_PROVIDER_VERSION"
  if [ "$OS" = android ]; then log 'Optional clipboard: install the Termux:API app and pkg install termux-api. Open login links with termux-open-url.'; fi
}

ROOT=${LMM_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/lmm-tools}
NETWORK=auto PROFILE=web CHECK=0 FORCE=0 LAUNCH=0 ADD_PATH=0 SOURCE=0
STAGE='' LOCKED=0 PHASE=arguments
RUN_ARGS=()
# State is consumed by dynamically imported helpers.
# shellcheck disable=SC2034
INSTALL_NODE=1 BOOTSTRAP=1 NPM_SELECTED=0
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
Common functions load from GitHub. LMM_LIB_DIR selects local libraries (no fetch).
No automatic login or PATH changes. See README.md.
USAGE
}
# State is consumed by dynamically imported helpers.
# shellcheck disable=SC2034
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
for library in hash.sh termux.sh quote.sh download.sh lifecycle.sh node.sh; do
  lmm_source_lib "$library" || exit $?
done
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
# --check does not write files; common modules may be fetched into memory.
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
