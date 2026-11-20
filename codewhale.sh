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
curl --proto '=https' --proto-redir '=https' -fsSL 'https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/8665a115c1b985804f03bd7c4570e74a9ab1f244/codewhale.mjs' -o "$work/codewhale.mjs"
node -e 'const fs=require("node:fs"),crypto=require("node:crypto");if(crypto.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex")!==process.argv[2]){console.error("Codewhale setup script checksum mismatch; nothing was executed.");process.exit(1)}' "$work/codewhale.mjs" '24cdb19db5b3ddc3187a6deaa59265e18a710e19b94170d34a361a0bf5fb0b16'
node "$work/codewhale.mjs" "$@"
