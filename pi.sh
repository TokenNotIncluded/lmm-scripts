#!/usr/bin/env bash
set -e
[[ $# = 0 ]] || { echo 'Usage: bash pi.sh' >&2; exit 2; }
if [[ -n ${TERMUX_VERSION:-} || ${PREFIX:-} == */com.termux/files/usr ]]; then
  pkg install nodejs npm git
  export TMPDIR="${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}"
fi
installer=$(curl -fsSL https://pi.dev/install.sh)
exec sh -c "$installer"'
pi=$(pi_installed_path); version=$("$pi" --version)
case "$version" in 0.86.[1-9]*|0.87.*) ;; *) echo "Pi $version installed; LMM alpha supports 0.86.1 through 0.87.x, plugin skipped." >&2; exit 0;; esac
command -v npm >/dev/null 2>&1 || { echo "npm is required to install the LMM plugin and remove conflicting sources." >&2; exit 1; }
LMM_PI_BIN="$pi" npm exec --yes --package=@tokennotincluded/pi-lmm-provider@0.1.0-alpha.2 -- lmm-pi-provider npm:@tokennotincluded/pi-lmm-provider@0.1.0-alpha.2'
