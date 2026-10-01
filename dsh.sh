#!/usr/bin/env bash
set -euo pipefail
[[ $# -le 1 && ${1:-web} =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || { echo 'Usage: bash dsh.sh [profile]' >&2; exit 2; }
npm install -g @deepseek-ai/dsh@latest pnpm@latest
# Resolve the current built release rather than installing an unbuilt Git checkout
# or a cached npm preview package. A versioned asset URL also refreshes pnpm's source.
release_url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/TokenNotIncluded/dsh-lmm-provider/releases/latest)
plugin_url=$(node --input-type=module -e '
const url=new URL(process.argv[1]);
const prefix="/TokenNotIncluded/dsh-lmm-provider/releases/tag/", tag=url.pathname.slice(prefix.length);
if(url.origin!=="https://github.com" || url.username || url.password || url.search || url.hash || !url.pathname.startsWith(prefix) || !/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(tag)) throw Error("Unexpected plugin release URL");
console.log("https://github.com/TokenNotIncluded/dsh-lmm-provider/releases/download/"+tag+"/dsh-lmm-provider.tgz");
' "$release_url")
dsh plugin --profile "${1:-web}" add "$plugin_url" --ignore-scripts
