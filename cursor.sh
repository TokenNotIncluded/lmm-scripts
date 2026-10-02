#!/usr/bin/env bash
set -euo pipefail
case "${1:-install}" in
  help|--help) echo 'Usage: bash cursor.sh [install|help]'; exit 0;;
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
    if brew list --cask cursor >/dev/null 2>&1; then exec brew upgrade --cask cursor; fi
    exec brew install --cask cursor;;
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
case "$ext" in deb) field=debUrl;; rpm) field=rpmUrl;; *) field=downloadUrl;; esac
url=$(curl --proto '=https' --proto-redir '=https' -fsSL "https://cursor.com/api/download?platform=linux-$arch&releaseTrack=stable" | jq -er --arg field "$field" '.[$field]')
[[ $url == https://downloads.cursor.com/* ]] || { echo 'Unexpected Cursor download URL.' >&2; exit 1; }
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
curl --proto '=https' --proto-redir '=https' -fsSL "$url" -o "$work/package.$ext"
if [[ $ext = AppImage ]]; then
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$work/package.$ext" "$HOME/.local/bin/cursor"
  echo 'Launch ~/.local/bin/cursor; configure accounts and providers in the app settings.'
elif [[ $EUID = 0 ]]; then "${manager[@]}" "$work/package.$ext"
else sudo "${manager[@]}" "$work/package.$ext"; fi
