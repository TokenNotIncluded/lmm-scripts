#!/usr/bin/env bash
set -euo pipefail
[[ $# = 1 ]] || { echo 'Usage: bash desktop.sh cc-switch|clash-verge-rev' >&2; exit 2; }
tool=$1
case "$tool" in
  cc-switch) repo=farion1231/cc-switch;;
  clash-verge-rev) repo=clash-verge-rev/clash-verge-rev;;
  *) echo "Unknown tool: $tool" >&2; exit 2;;
esac
if [[ -n ${TERMUX_VERSION:-} || ${PREFIX:-} == */com.termux/files/usr ]]; then
  echo 'Desktop applications are not supported in Termux.' >&2; exit 1
fi
case "$(uname -s)" in
  Darwin)
    if brew list --cask "$tool" >/dev/null 2>&1; then exec brew upgrade --cask "$tool"; fi
    exec brew install --cask "$tool";;
  Linux) ;;
  *) echo 'Use the PowerShell installer on Windows.' >&2; exit 1;;
esac
if [[ -f /etc/arch-release ]]; then
  for helper in paru yay; do
    if command -v "$helper" >/dev/null; then exec "$helper" -S "$tool-bin"; fi
  done
  echo 'Install paru or yay first.' >&2; exit 1
fi
case "$(uname -m)" in
  x86_64|amd64) arch='(amd64|x86_64)';;
  aarch64|arm64) arch='(arm64|aarch64)';;
  armv7l) arch='(armhf|armhfp|armv7)';;
  *) echo 'No official package for this architecture.' >&2; exit 1;;
esac
if command -v apt-get >/dev/null; then ext=deb; manager=(apt-get install)
elif command -v dnf >/dev/null; then ext=rpm; manager=(dnf install)
elif command -v yum >/dev/null; then ext=rpm; manager=(yum localinstall)
elif command -v zypper >/dev/null; then ext=rpm; manager=(zypper install)
elif [[ $tool = cc-switch ]]; then ext=AppImage
else echo 'Clash Verge Rev needs a deb/rpm distribution or an AUR helper.' >&2; exit 1; fi
url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | jq -er --arg pattern "$arch\\.$ext$" '
  [.assets[] | select(.name | test($pattern)) | .browser_download_url]
  | if length == 1 then .[0] else error("No unique official package for this platform") end')
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
curl -fsSL "$url" -o "$work/package.$ext"
if [[ $ext = AppImage ]]; then
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$work/package.$ext" "$HOME/.local/bin/cc-switch"
  echo "$HOME/.local/bin/cc-switch"
elif [[ $EUID = 0 ]]; then "${manager[@]}" "$work/package.$ext"
else sudo "${manager[@]}" "$work/package.$ext"; fi
