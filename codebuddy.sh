#!/usr/bin/env bash
set -euo pipefail
case "${1:-install}" in
  help|--help) echo 'Usage: bash codebuddy.sh [install|setup|help]'; exit 0;;
  setup) [[ $# = 1 ]] || exit 2; exec codebuddy;;
  install) ;;
  *) echo "Unknown action: $1" >&2; exit 2;;
esac
[[ $# -le 1 ]] || exit 2
if ! command -v npm >/dev/null || ! command -v node >/dev/null; then echo 'Install Node.js 20+ and npm first.' >&2; exit 1; fi
node -e 'if(Number(process.versions.node.split(".")[0])<20){console.error("Node.js 20+ is required.");process.exit(1)}'
npm install -g @tencent-ai/codebuddy-code@latest
echo 'Reopen your terminal; configure with: bash codebuddy.sh setup (starts codebuddy and its login screen).'
