#!/usr/bin/env bash
set -euo pipefail
case "${1:-install}" in
  help|--help) echo "Usage: bash openclaw.sh [install|setup|help]"; exit 0;;
  setup) [[ $# = 1 ]] || { echo "Usage: bash openclaw.sh [install|setup|help]" >&2; exit 2; }; exec openclaw onboard;;
  install) ;;
  *) echo "Unknown action: $1" >&2; exit 2;;
esac
[[ $# -le 1 ]] || { echo "Too many arguments" >&2; exit 2; }
if [[ -n ${TERMUX_VERSION:-} || ${PREFIX:-} == */com.termux/files/usr ]]; then
  echo 'Use a supported Linux environment (WSL2 / PRoot); Android native installation is not supported by this entry.' >&2; exit 1
fi
installer=$(curl --proto "=https" --proto-redir "=https" -fsSL https://openclaw.ai/install.sh)
bash -c "$installer" -- --no-onboard
echo "Installed via the official installer. Reopen your terminal, then run: openclaw; configure: bash openclaw.sh setup"
