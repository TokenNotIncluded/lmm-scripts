#!/usr/bin/env bash
set -euo pipefail
case "${1:-install}" in
  help|--help) echo 'Usage: bash cherry-studio.sh [install|help]'; exit 0;;
  install) ;;
  *) echo 'Configure this desktop application in its settings after launch.' >&2; exit 2;;
esac
[[ $# -le 1 ]] || exit 2
if [[ -n ${TERMUX_VERSION:-} || ${PREFIX:-} == */com.termux/files/usr ]]; then
  echo 'Desktop applications are not supported in Termux.' >&2; exit 1
fi
case "$(uname -s)" in
  Darwin)
    command -v brew >/dev/null || { echo 'Install Homebrew first.' >&2; exit 1; }
    if brew list --cask cherry-studio >/dev/null 2>&1; then exec brew upgrade --cask cherry-studio; fi
    exec brew install --cask cherry-studio;;
  Linux) ;;
  *) echo 'Use the PowerShell entry on Windows.' >&2; exit 1;;
esac
command -v jq >/dev/null || { echo 'Install jq first.' >&2; exit 1; }
case "$(uname -m)" in
  x86_64|amd64) arch=x64;;
  aarch64|arm64) arch=arm64;;
  *) echo 'Only x64 and arm64 packages are available.' >&2; exit 1;;
esac
if command -v apt-get >/dev/null; then ext=deb; manager=(apt-get install)
elif command -v dnf >/dev/null; then ext=rpm; manager=(dnf install)
elif command -v yum >/dev/null; then ext=rpm; manager=(yum localinstall)
elif command -v zypper >/dev/null; then ext=rpm; manager=(zypper install)
else ext=AppImage; fi
url=$(curl --proto '=https' --proto-redir '=https' -fsSL https://api.github.com/repos/CherryHQ/cherry-studio/releases/latest | jq -er --arg pattern "^Cherry-Studio-[0-9].*-linux-$arch\\.$ext$" '
  [.assets[] | select(.name | test($pattern)) | .browser_download_url]
  | if length == 1 then .[0] else error("No unique official package for this platform") end')
[[ $url == https://github.com/CherryHQ/cherry-studio/releases/download/* ]] || { echo 'Unexpected Cherry Studio download URL.' >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
curl --proto '=https' --proto-redir '=https' -fsSL "$url" -o "$work/package.$ext"
if [[ $ext = AppImage ]]; then
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$work/package.$ext" "$HOME/.local/bin/cherry-studio"
  echo 'Launch ~/.local/bin/cherry-studio; configure accounts and providers in the app settings.'
elif [[ $EUID = 0 ]]; then "${manager[@]}" "$work/package.$ext"
else sudo "${manager[@]}" "$work/package.$ext"; fi
