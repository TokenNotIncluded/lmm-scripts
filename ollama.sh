#!/usr/bin/env bash
set -euo pipefail
case "${1:-install}" in
  help|--help) echo 'Usage: bash ollama.sh [install|help]'; exit 0;;
  install) ;;
  *) echo 'Use ollama serve to start the server, then ollama run MODEL to download and run a model.' >&2; exit 2;;
esac
[[ $# -le 1 ]] || exit 2
if [[ -n ${TERMUX_VERSION:-} || ${PREFIX:-} == */com.termux/files/usr ]]; then
  echo 'Use a supported Linux environment; this entry does not install Android binaries.' >&2; exit 1
fi
case "$(uname -s)" in
  Darwin)
    command -v brew >/dev/null || { echo 'Install Homebrew first.' >&2; exit 1; }
    if brew list --formula ollama >/dev/null 2>&1; then brew upgrade ollama; else brew install ollama; fi;;
  Linux)
    installer=$(curl --proto '=https' --proto-redir '=https' -fsSL https://ollama.com/install.sh)
    sh -c "$installer";;
  *) echo 'Use the PowerShell entry on Windows.' >&2; exit 1;;
esac
echo 'Run ollama serve if the service is not already running. Use ollama run MODEL to choose a model; this script does not download models.'
