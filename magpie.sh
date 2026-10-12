#!/usr/bin/env bash
set -euo pipefail
case "${1:-install}" in
  install|update) if [[ $# -gt 0 ]]; then shift; fi;;
  help|-h|--help)
    printf '%s\n' 'Usage: bash magpie.sh [install|update] [official installer options]' \
      'Linux, macOS and Termux: use the official installer.' \
      'MAGPIE_CLI=1 selects the terminal build on Linux.' \
      'MAGPIE_BIN_DIR changes the command directory. No login or configuration is performed.'
    exit 0;;
  -*) ;; # Let the official installer validate its own options.
  *) echo 'Usage: bash magpie.sh [install|update] [official installer options]' >&2; exit 2;;
esac
# Finish the download before executing anything; never execute a partial response.
script=$(curl -fsSL https://usemagpie.ai/install.sh)
sh -c "$script" -- "$@"
