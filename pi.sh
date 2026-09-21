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
[ "$version" = 0.85.1 ] || { echo "Pi $version installed; LMM alpha requires 0.85.1, plugin skipped." >&2; exit 0; }
"$pi" install npm:@tokennotincluded/pi-lmm-provider@0.1.0-alpha.1'
