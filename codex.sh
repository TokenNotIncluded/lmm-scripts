#!/usr/bin/env bash
set -euo pipefail
runner=(sh)
if [[ -n ${TERMUX_VERSION:-} || ${PREFIX:-} == */com.termux/files/usr ]]; then
  runner=(proot-distro login "${LMM_DISTRO:-ubuntu}" -- sh)
fi
script=$(curl -fsSL https://chatgpt.com/codex/install.sh)
"${runner[@]}" -c "$script" -- "$@"
