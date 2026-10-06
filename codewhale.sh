#!/usr/bin/env bash
set -euo pipefail
command -v node >/dev/null 2>&1 || { echo 'Install Node.js 22+ with npm first. Termux: pkg install nodejs npm' >&2; exit 1; }
node -e 'if(Number(process.versions.node.split(".")[0])<22){console.error("Node.js 22+ is required.");process.exit(1)}'
dir=$(dirname -- "${BASH_SOURCE[0]:-}")
if [[ -n ${BASH_SOURCE[0]:-} && -f $dir/codewhale.mjs ]]; then
  exec node "$dir/codewhale.mjs" "$@"
fi
temp_root=${TMPDIR:-/tmp}
if [[ -n ${TERMUX_VERSION:-} || ${PREFIX:-} == */com.termux/files/usr ]]; then temp_root=${TMPDIR:-${PREFIX:-/data/data/com.termux/files/usr}/tmp}; fi
work=$(mktemp -d "$temp_root/lmm-codewhale.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
curl --proto '=https' --proto-redir '=https' -fsSL 'https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/319d9790ba026583ea226fb92b13b366b738c3ef/codewhale.mjs' -o "$work/codewhale.mjs"
node -e 'const fs=require("node:fs"),crypto=require("node:crypto");if(crypto.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex")!==process.argv[2]){console.error("Codewhale setup script checksum mismatch; nothing was executed.");process.exit(1)}' "$work/codewhale.mjs" '91dcff456f04abb0ef0ff7f95742ff3d332bfb2c93b4b067f4d778008556f69c'
node "$work/codewhale.mjs" "$@"
