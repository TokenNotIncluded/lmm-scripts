#!/usr/bin/env bash
set -euo pipefail
command -v node >/dev/null 2>&1 || { echo 'Install Node.js 22+ with npm first. Termux: pkg install nodejs npm' >&2; exit 1; }
node -e 'if(Number(process.versions.node.split(".")[0])<22){console.error("Node.js 22+ is required.");process.exit(1)}'
dir=$(dirname -- "${BASH_SOURCE[0]:-}")
if [[ -n ${BASH_SOURCE[0]:-} && -f $dir/opencode.mjs ]]; then
  exec node "$dir/opencode.mjs" "$@"
fi
temp_root=${TMPDIR:-/tmp}
if [[ -n ${TERMUX_VERSION:-} || ${PREFIX:-} == */com.termux/files/usr ]]; then temp_root=${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}; fi
work=$(mktemp -d "$temp_root/lmm-opencode.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
curl --proto '=https' --proto-redir '=https' -fsSL 'https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/e2efbe13fd4e8c0cb9d31ed95ae6d432415aed25/opencode.mjs' -o "$work/opencode.mjs"
node -e 'const fs=require("node:fs"),crypto=require("node:crypto");if(crypto.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex")!==process.argv[2]){console.error("OpenCode setup script checksum mismatch; nothing was executed.");process.exit(1)}' "$work/opencode.mjs" 'ded76c114f7c8a692c9d7fa7828828b86ad7d0591aa01fd19be1c2ceecfd95a4'
node "$work/opencode.mjs" "$@"
