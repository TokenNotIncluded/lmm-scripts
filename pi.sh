#!/usr/bin/env bash
set -e
[[ $# = 0 ]] || { echo 'Usage: bash pi.sh' >&2; exit 2; }
if [[ -n ${TERMUX_VERSION:-} || ${PREFIX:-} == */com.termux/files/usr ]]; then
  pkg install nodejs npm git
  export TMPDIR="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}"
fi
installer=$(curl -fsSL https://pi.dev/install.sh)
exec sh -c "$installer"'
pi=$(pi_installed_path); "$pi" --version
command -v npm >/dev/null 2>&1 || { echo "npm is required to install the LMM plugin and remove conflicting sources." >&2; exit 1; }
LMM_PI_BIN="$pi" npm exec --yes --package=@tokennotincluded/pi-lmm-provider@alpha -- lmm-pi-provider git:github.com/TokenNotIncluded/pi-lmm-provider'
