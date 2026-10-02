#!/usr/bin/env bash
set -euo pipefail
case "${1:-install}" in
  help|--help) echo "Usage: bash hermes.sh [install|setup|help]"; exit 0;;
  setup) [[ $# = 1 ]] || { echo "Usage: bash hermes.sh [install|setup|help]" >&2; exit 2; }; exec hermes setup;;
  install) ;;
  *) echo "Unknown action: $1" >&2; exit 2;;
esac
[[ $# -le 1 ]] || { echo "Too many arguments" >&2; exit 2; }
if [[ -n ${TERMUX_VERSION:-} || ${PREFIX:-} == */com.termux/files/usr ]]; then
  echo 'Use a supported Linux environment (WSL2 / PRoot); Android native installation is not supported by this entry.' >&2; exit 1
fi
installer=$(curl --proto "=https" --proto-redir "=https" -fsSL https://hermes-agent.nousresearch.com/install.sh)
bash -c "$installer" -- --skip-setup
echo "Installed via the official installer. Reopen your terminal, then run: hermes; configure: bash hermes.sh setup"
