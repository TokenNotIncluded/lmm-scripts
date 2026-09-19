#!/usr/bin/env bash
set -Eeuo pipefail

command -v npm >/dev/null || { echo 'npm is required.' >&2; exit 1; }
npm install --global --ignore-scripts @openai/codex claude-code
echo 'AI command-line tools installed: codex, claude.'
