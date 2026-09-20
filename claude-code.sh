#!/usr/bin/env bash
set -euo pipefail
runner=(bash)
if [[ -n ${TERMUX_VERSION:-} || ${PREFIX:-} == */com.termux/files/usr ]]; then
  runner=(proot-distro login "${LMM_DISTRO:-ubuntu}" -- bash)
fi
script=$(curl -fsSL https://claude.ai/install.sh)
"${runner[@]}" -c "$script" -- "$@"
