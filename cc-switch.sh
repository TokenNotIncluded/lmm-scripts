#!/usr/bin/env bash
set -euo pipefail
[[ $# = 0 ]] || { echo 'Usage: bash cc-switch.sh' >&2; exit 2; }
if [[ -n ${TERMUX_VERSION:-} || ${PREFIX:-} == */com.termux/files/usr ]]; then
  echo 'Desktop applications are not supported in Termux.' >&2; exit 1
fi
dir=$(dirname -- "${BASH_SOURCE[0]:-}")
if [[ -n ${BASH_SOURCE[0]:-} && -f $dir/desktop.sh ]]; then exec bash "$dir/desktop.sh" cc-switch; fi
script=$(curl -fsSL https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/0e13bd29c75df2bfd14bc1cfcce70c206464e5e2/desktop.sh)
bash -c "$script" -- cc-switch
