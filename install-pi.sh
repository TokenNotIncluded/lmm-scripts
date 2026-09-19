#!/usr/bin/env bash
set -Eeuo pipefail

command -v node >/dev/null || { echo 'Node.js 20+ is required.' >&2; exit 1; }
command -v npm >/dev/null || { echo 'npm is required.' >&2; exit 1; }
node -e 'process.exit(Number(process.versions.node.split(".")[0]) < 20 ? 1 : 0)' || { echo 'Node.js 20+ is required.' >&2; exit 1; }
npm install --global --ignore-scripts @mariozechner/pi-coding-agent
if [[ -n "${LMM_PI_PLUGIN:-}" ]]; then npm install --global --ignore-scripts "$LMM_PI_PLUGIN"; fi
echo 'Pi installed. Run: pi'
