#!/usr/bin/env bash
set -euo pipefail
case "${1:-install}" in
  help|--help) echo 'Usage: bash astrbot.sh [install|setup DIRECTORY|help]'; exit 0;;
  setup)
    [[ $# = 2 && -n $2 ]] || { echo 'Specify an AstrBot instance directory: bash astrbot.sh setup DIRECTORY' >&2; exit 2; }
    command -v astrbot >/dev/null || { echo 'Install AstrBot first and reopen your terminal.' >&2; exit 1; }
    mkdir -p -- "$2"
    cd -- "$2"
    if [[ -e data || -L data ]]; then
      echo 'This directory already has AstrBot data. Use astrbot run here and configure it in the WebUI.'
      exit 0
    fi
    astrbot init
    echo 'Instance initialized. Run astrbot run in this directory; configure providers and chat platforms in the WebUI.'
    exit 0;;
  install) ;;
  *) echo "Unknown action: $1" >&2; exit 2;;
esac
[[ $# -le 1 ]] || exit 2
command -v uv >/dev/null || { echo 'Install uv first: bash uv.sh (or https://docs.astral.sh/uv/).' >&2; exit 1; }
uv tool install --upgrade astrbot --python 3.12
echo 'Reopen your terminal; initialize an instance with: bash astrbot.sh setup DIRECTORY'
