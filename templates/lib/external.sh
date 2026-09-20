# shellcheck shell=bash
# Delegate CLI installation to upstream; share desktop package selection.
lmm_external_main() (
  set -euo pipefail
  local ROOT=${LMM_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/lmm-tools}
  local CHECK=0 UPDATE=0 LAUNCH=0 PLAN=0 DEPS=0 NETWORK=official VERSION=''
  local DISTRO=${LMM_PROOT_DISTRO:-ubuntu} STAGE='' MOUNT='' COMMAND='' KIND='' APP='' REPO=''
  local OS ARCH FAMILY='' LIBC=glibc ENTRY='' ASSET='' URL='' RUN_ARGS=()
  die() { printf '%s\n' "$*" >&2; exit 1; }
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --check) CHECK=1;; --update) UPDATE=1;; --launch) LAUNCH=1;;
      --dry-run) PLAN=1;; --install-deps) DEPS=1;;
      --root|--network|--version|--distro)
        [ "$#" -ge 2 ] && [ -n "$2" ] || die "$1 requires a value"
        case "$1" in --root) ROOT=$2;; --network) NETWORK=$2;; --version) VERSION=$2; UPDATE=1;; --distro) DISTRO=$2;; esac; shift;;
      --) shift; RUN_ARGS=("$@"); break;;
      *) die "Unknown option: $1 (use --help)";;
    esac; shift
  done
  case "$NETWORK" in auto|official|china) ;; *) die 'network: auto, official or china';; esac
  [[ $DISTRO =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || die 'Invalid proot distro name'
  case "$ROOT" in /*) ;; *) ROOT="$PWD/$ROOT";; esac
  [ "$ROOT" != / ] && [ "$ROOT" != "$HOME" ] && [ ! -L "$ROOT" ] || die 'Choose a dedicated install directory'
  case "$ROOT" in *$'\n'*|*$'\r'*) die 'Invalid install path';; esac
  case "$TARGET" in
    codex) COMMAND=codex; KIND=cli; URL=https://chatgpt.com/codex/install.sh;;
    claude-code) COMMAND=claude; KIND=cli; URL=https://claude.ai/install.sh; VERSION=${VERSION:-stable};;
    cc-switch) COMMAND=cc-switch; KIND=desktop; APP='CC Switch'; REPO=farion1231/cc-switch;;
    clash-verge-rev) COMMAND=clash-verge; KIND=desktop; APP='Clash Verge'; REPO=clash-verge-rev/clash-verge-rev;;
    *) die 'Unknown tool';;
  esac
  VERSION=${VERSION:-latest}
  [[ $VERSION =~ ^[a-zA-Z0-9][a-zA-Z0-9.+-]*$ ]] || die 'Invalid version'
  case "$(uname -s)" in Linux) OS=linux;; Darwin) OS=darwin;; *) die 'Use the .ps1 installer on Windows';; esac
  if lmm_is_termux; then OS=android; fi
  case "$(uname -m)" in x86_64|amd64) ARCH=x64;; aarch64|arm64) ARCH=arm64;; *) die 'This installer requires x64 or arm64';; esac
  if [ "$OS" = android ]; then
    [ "$KIND" = cli ] || die "$APP is a desktop application; Termux is not supported"
    lmm_check_storage "$ROOT" || exit 1
  elif [ "$OS" = linux ]; then
    local ID='' ID_LIKE=''
    if [ -f "${LMM_OS_RELEASE:-/etc/os-release}" ]; then
      # shellcheck disable=SC1090
      . "${LMM_OS_RELEASE:-/etc/os-release}"
    fi
    case " $ID $ID_LIKE " in
      *alpine*) FAMILY=alpine;; *debian*|*ubuntu*) FAMILY=debian;;
      *fedora*|*rhel*|*centos*|*rocky*|*almalinux*) FAMILY=fedora;; *suse*) FAMILY=suse;;
      *arch*) FAMILY=arch;; *void*) FAMILY=void;; *nixos*) FAMILY=nixos;;
    esac
    if [ "$FAMILY" = alpine ] || { ldd --version 2>&1 || :; } | grep -qi musl; then LIBC=musl; fi
  fi
  strategy() {
    if [ "$OS" = linux ] && [ "$FAMILY" = nixos ]; then die 'NixOS: use a Nix package/dev shell'; fi
    if [ "$KIND" = desktop ] && [ "$LIBC" = musl ]; then die 'No compatible musl desktop package'; fi
    if [ "$OS" = android ]; then printf 'proot:%s official:%s\n' "$DISTRO" "$URL"
    elif [ "$KIND" = cli ]; then printf 'official:%s libc:%s\n' "$URL" "$LIBC"
    elif [ "$OS" = darwin ]; then printf 'macOS:Homebrew-or-DMG\n'
    else case "$FAMILY" in debian) printf 'apt:deb\n';; fedora) printf 'dnf-or-yum:rpm\n';; suse) printf 'zypper:rpm\n';; arch) printf 'paru-or-yay:AUR\n';; *) [ "$TARGET" = cc-switch ] && printf 'AppImage\n' || die 'Clash Verge Rev requires a deb/rpm distro or an AUR helper';; esac; fi
  }
  if [ "$PLAN" = 1 ]; then printf '%s %s/%s ' "$TARGET" "$OS" "$ARCH"; strategy; exit 0; fi
  find_entry() {
    local candidate
    for candidate in "$ROOT/bin/$COMMAND" "${CODEX_INSTALL_DIR:-$HOME/.local/bin}/$COMMAND" "$HOME/.local/bin/$COMMAND"; do
      if [ -x "$candidate" ]; then ENTRY=$candidate; return; fi
    done
    if [ "$OS" = darwin ] && [ "$KIND" = desktop ]; then
      for candidate in "$HOME/Applications/$APP.app" "/Applications/$APP.app"; do
        if [ -d "$candidate" ]; then ENTRY=$candidate; return; fi
      done
    fi
    ENTRY=$(command -v "$COMMAND" || :)
  }
  find_entry
  if [ "$CHECK" = 1 ]; then
    [ -n "$ENTRY" ] || die "$COMMAND is not installed"
    if [ "$KIND" = cli ]; then "$ENTRY" --version; else printf 'Installed: %s\n' "$ENTRY"; fi
    exit 0
  fi
  cleanup() {
    if [ -n "$MOUNT" ]; then hdiutil detach "$MOUNT" >/dev/null 2>&1 || :; fi
    if [ -n "$STAGE" ]; then rm -rf -- "$STAGE"; fi
  }
  trap cleanup EXIT; trap 'exit 130' INT; trap 'exit 143' TERM
  admin() { if [ "$(id -u)" = 0 ]; then "$@"; else sudo "$@"; fi; }
  prerequisites() {
    local packages=(bash curl ca-certificates git)
    [ "$KIND" != desktop ] || packages+=(jq)
    case "$FAMILY" in
      alpine) [ "$TARGET" != claude-code ] || packages+=(libgcc libstdc++ ripgrep); admin apk add "${packages[@]}";;
      debian) admin apt-get update; admin apt-get install -y "${packages[@]}";;
      fedora) if command -v dnf >/dev/null; then admin dnf install -y "${packages[@]}"; else admin yum install -y "${packages[@]}"; fi;;
      suse) admin zypper --non-interactive install "${packages[@]}";;
      arch) admin pacman -S --needed --noconfirm "${packages[@]}";;
      void) admin xbps-install -y "${packages[@]}";;
      *) die 'Install bash, curl, CA certificates and git with your package manager (GUI release selection also needs jq)';;
    esac
  }
  fetch() {
    local source=$1 output=$2
    if [ "$NETWORK" = china ] && [[ $source == https://github.com/* ]]; then
      if curl -q -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 600 "https://ghfast.top/$source" -o "$output" && [ -s "$output" ]; then return; fi
    fi
    curl -q -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 600 --retry 2 "$source" -o "$output"
    [ -s "$output" ] || die "Empty download: $source"
  }
  shim() {
    local file="$ROOT/bin/$COMMAND"
    mkdir -p "$ROOT/bin"
    if [ -e "$file" ] || [ -L "$file" ]; then
      grep -Fq '# Managed by LMM installers.' "$file" || die "Refusing existing launcher: $file"
    fi
    { printf '#!%s\n# Managed by LMM installers.\n' "$BASH"; printf '%s\n' "$1"; } > "$STAGE/launcher"
    chmod +x "$STAGE/launcher"; mv -f -- "$STAGE/launcher" "$file"; ENTRY=$file
  }
  stage() {
    local tmp
    tmp=$(lmm_temp_root); lmm_check_storage "$tmp" || exit 1
    mkdir -p "$tmp"; STAGE=$(mktemp -d "$tmp/lmm-$TARGET.XXXXXXXX")
  }
  if [ -z "$ENTRY" ] || [ "$UPDATE" = 1 ]; then
    if [ "$OS" = linux ]; then
      [ "$FAMILY" != nixos ] || die 'NixOS: use a Nix package/dev shell; the upstream generic Linux installer is not compatible with its loader layout'
      [ "$DEPS" = 0 ] || prerequisites
    fi
    command -v curl >/dev/null || die 'Install curl first'
    stage
    if [ "$OS" = android ]; then
      if ! command -v proot-distro >/dev/null; then
        [ "$DEPS" = 1 ] || die 'Termux: pkg install proot-distro; proot-distro install ubuntu:24.04; then rerun'
        pkg install -y proot-distro
      fi
      proot-distro login "$DISTRO" -- /bin/true || die "Prepare an existing Linux guest first: proot-distro install ubuntu:24.04 (selected: $DISTRO)"
      if [ "$DEPS" = 1 ]; then
        proot-distro login "$DISTRO" -- /bin/sh -c 'command -v apt-get >/dev/null || { echo "Prepare guest dependencies with its package manager" >&2; exit 1; }; apt-get update && apt-get install -y bash curl ca-certificates git'
      fi
      proot-distro login "$DISTRO" -- /bin/sh -c 'command -v bash && command -v curl' >/dev/null || die 'Install bash, curl, ca-certificates and git inside the selected guest'
      fetch "$URL" "$STAGE/install.sh"
      local install_args=("$VERSION")
      [ "$TARGET" != codex ] || install_args=(--release "$VERSION")
      proot-distro login "$DISTRO" --bind "$STAGE:/mnt/lmm-install" -- /bin/bash -c 'unset CODEX_HOME CODEX_INSTALL_DIR; CODEX_NON_INTERACTIVE=true bash /mnt/lmm-install/install.sh "$@"' -- "${install_args[@]}"
      proot-distro login "$DISTRO" -- /bin/bash -c '"$HOME/.local/bin/$1" --version' -- "$COMMAND"
      shim "exec $(quote_sh "$(command -v proot-distro)") login $(quote_sh "$DISTRO") --bind \"\$PWD:/workspace\" --work-dir /workspace -- /bin/bash -c 'exec \"\$HOME/.local/bin/$COMMAND\" \"\$@\"' -- \"\$@\""
      printf 'Termux uses a PRoot Linux guest; native Android and sandbox parity are not implied.\n'
    elif [ "$KIND" = cli ]; then
      if [ "$TARGET" = claude-code ] && [ "$LIBC" = musl ]; then
        command -v rg >/dev/null || die 'musl: install libgcc, libstdc++ and ripgrep (Alpine: rerun with --install-deps)'
        export USE_BUILTIN_RIPGREP=0
      fi
      fetch "$URL" "$STAGE/install.sh"
      if [ "$TARGET" = codex ]; then CODEX_NON_INTERACTIVE=true bash "$STAGE/install.sh" --release "$VERSION"
      else bash "$STAGE/install.sh" "$VERSION"; fi
      ENTRY=''; find_entry
      if [ "$TARGET" = claude-code ] && [ "$LIBC" = musl ] && [ -x "$HOME/.local/bin/claude" ]; then ENTRY="$HOME/.local/bin/claude"; fi
      [ -n "$ENTRY" ] || die "Installer returned without a usable $COMMAND executable"
      "$ENTRY" --version
      if [ "$TARGET" = claude-code ] && [ "$LIBC" = musl ]; then
        [ "$ENTRY" != "$ROOT/bin/$COMMAND" ] || die 'Refusing a recursive Claude launcher; rerun the official installer'
        shim "export USE_BUILTIN_RIPGREP=0; exec $(quote_sh "$ENTRY") \"\$@\""
      fi
    else
      lmm_install_desktop
    fi
  fi
  printf 'Ready: %s\n' "$ENTRY"
  if [ "$LAUNCH" = 1 ]; then
    if [ "$OS" = darwin ] && [[ $ENTRY == *.app ]]; then open "$ENTRY" --args ${RUN_ARGS[@]+"${RUN_ARGS[@]}"}
    else "$ENTRY" ${RUN_ARGS[@]+"${RUN_ARGS[@]}"}; fi
  fi
)

# Called inside lmm_external_main; reuse its paths and download functions.
lmm_install_desktop() {
  local manager ext pattern metadata candidate target
  [ "$LIBC" != musl ] || die "No compatible musl desktop package"
  if [ "$OS" = darwin ] && command -v brew >/dev/null && [ "$VERSION" = latest ]; then
    if brew list --cask "$TARGET" >/dev/null 2>&1; then brew upgrade --cask "$TARGET"
    else brew install --cask "$TARGET"; fi
    ENTRY=''; find_entry; [ -n "$ENTRY" ] || die "Find $APP in Applications"; return
  fi
  if [ "$OS" = linux ] && [ "$FAMILY" = arch ]; then
    [ "$VERSION" = latest ] || die 'AUR tracks its packaged version; an exact upstream version is not supported here'
    manager=$(command -v paru || command -v yay || :)
    [ -n "$manager" ] || die "Install an AUR helper, then: paru -S $TARGET-bin"
    "$manager" -S --needed "$TARGET-bin"
    ENTRY=''; find_entry; [ -n "$ENTRY" ] || die 'Package installed but executable was not found'; return
  fi
  case "$OS:$FAMILY" in darwin:*) ext=dmg;; linux:debian) ext=deb;; linux:fedora|linux:suse) ext=rpm;; *)
    [ "$TARGET" = cc-switch ] && [ "$LIBC" = glibc ] || die 'No compatible desktop package for this distribution'
    ext=AppImage;;
  esac
  pattern=$(lmm_desktop_pattern "$TARGET" "$OS" "$ARCH" "$ext")
  metadata=latest; [ "$VERSION" = latest ] || metadata="tags/v${VERSION#v}"
  fetch "https://api.github.com/repos/$REPO/releases/$metadata" "$STAGE/release.json"
  if command -v jq >/dev/null; then
    candidate=$(jq -er --arg pattern "$pattern" '[.assets[] | select(.name | test($pattern; "i")) | .browser_download_url] | if length == 1 then .[0] else error("expected exactly one matching asset") end' "$STAGE/release.json") || die "No unique $OS/$ARCH $ext asset"
  elif [ "$OS" = darwin ]; then
    candidate=$(osascript -l JavaScript -e 'function run(a) {var f=Application.currentApplication(); f.includeStandardAdditions=true; var j=JSON.parse(f.read(Path(a[0]))); var r=j.assets.filter(x=>new RegExp(a[1],"i").test(x.name)); if(r.length!==1)throw Error("expected one asset"); return r[0].browser_download_url;}' "$STAGE/release.json" "$pattern")
  else die 'Install jq first (or rerun with --install-deps)'; fi
  ASSET="$STAGE/${candidate##*/}"; fetch "$candidate" "$ASSET"
  case "$ext" in
    deb) admin apt-get install -y "$ASSET";;
    rpm) case "$FAMILY" in suse) admin zypper --non-interactive install "$ASSET";; *) if command -v dnf >/dev/null; then admin dnf install -y "$ASSET"; else admin yum localinstall -y "$ASSET"; fi;; esac;;
    AppImage)
      target="$ROOT/apps/$TARGET/$(date +%s)-$$/${ASSET##*/}"; mkdir -p "$(dirname "$target")"
      chmod +x "$ASSET"; mv -- "$ASSET" "$target"; shim "exec $(quote_sh "$target") \"\$@\""; return;;
    dmg)
      MOUNT="$STAGE/mount"; mkdir "$MOUNT"; hdiutil attach "$ASSET" -readonly -nobrowse -mountpoint "$MOUNT" >/dev/null
      [ -d "$MOUNT/$APP.app" ] || die 'Application bundle missing in DMG'
      target="$HOME/Applications/$APP.app"; mkdir -p "$HOME/Applications"
      [ ! -e "$target" ] || mv "$target" "$target.backup-$(date +%s)-$$"
      ditto "$MOUNT/$APP.app" "$target"; ENTRY=$target; return;;
  esac
  ENTRY=''; find_entry; [ -n "$ENTRY" ] || die 'Package installed but executable was not found'
}

lmm_desktop_pattern() {
  local target=$1 os=$2 arch=$3 ext=$4 suffix
  if [ "$target" = cc-switch ]; then
    if [ "$os" = darwin ]; then printf '%s\n' '-macOS\.dmg$'; return; fi
    suffix=x86_64; [ "$arch" != arm64 ] || suffix=arm64
    printf '%s\n' "-Linux-$suffix\\.$ext$"
  else
    case "$ext:$arch" in
      deb:x64) suffix=amd64;; deb:arm64) suffix=arm64;;
      dmg:x64) suffix=x64;; *:arm64) suffix=aarch64;; *) suffix=x86_64;;
    esac
    printf '%s\n' "[._]$suffix\\.$ext$"
  fi
}
