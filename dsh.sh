#!/usr/bin/env bash
set -euo pipefail
[[ $# -le 1 && ${1:-web} =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || { echo 'Usage: bash dsh.sh [profile]' >&2; exit 2; }
npm install -g @deepseek-ai/dsh@0.1.5-rc.2 pnpm@11.7.0
dsh plugin --profile "${1:-web}" add @tokennotincluded/dsh-lmm-provider@0.1.0-alpha.3 --ignore-scripts
