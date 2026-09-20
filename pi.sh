#!/usr/bin/env bash
set -euo pipefail
[[ $# = 0 ]] || { echo 'Usage: bash pi.sh' >&2; exit 2; }
# Pin the host version required by the LMM alpha plugin.
npm install -g --ignore-scripts @earendil-works/pi-coding-agent@0.85.1
pi install npm:@tokennotincluded/pi-lmm-provider@0.1.0-alpha.1
