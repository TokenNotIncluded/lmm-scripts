#!/usr/bin/env bash
set -euo pipefail
[[ $# -le 1 && ${1:-web} =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || { echo 'Usage: bash dsh.sh [profile]' >&2; exit 2; }
npm install -g @deepseek-ai/dsh@latest pnpm@latest
# Resolve the current built release rather than installing an unbuilt Git checkout
# or a cached npm preview package. A versioned asset URL also refreshes pnpm's source.
plugin_url=$(curl -fsSL https://api.github.com/repos/TokenNotIncluded/dsh-lmm-provider/releases/latest | node --input-type=module -e '
let input=""; for await (const chunk of process.stdin) input+=chunk;
const release=JSON.parse(input), asset=release.assets?.find(a=>a.name==="dsh-lmm-provider.tgz");
if(release.draft || release.prerelease || !asset) throw Error("No published DSH LMM plugin release found");
const url=new URL(asset.browser_download_url);
if(url.origin!=="https://github.com" || url.username || url.password || url.search || url.hash || !/^\/TokenNotIncluded\/dsh-lmm-provider\/releases\/download\/[^/]+\/dsh-lmm-provider\.tgz$/.test(url.pathname)) throw Error("Unexpected plugin release URL");
console.log(url.href);
')
dsh plugin --profile "${1:-web}" add "$plugin_url" --ignore-scripts
