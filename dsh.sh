#!/usr/bin/env bash
set -euo pipefail
[[ $# -le 1 && ${1:-web} =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || { echo 'Usage: bash dsh.sh [profile]' >&2; exit 2; }
npm install -g @deepseek-ai/dsh@latest pnpm@latest
cache=$(node -e '
const fs=require("node:fs"),os=require("node:os"),p=require("node:path");let h=process.env.DSH_HOME;if(!h?.trim())h=p.join(os.homedir(),".dsh");else if(/^~(?:[\\/]|$)/.test(h))h=p.join(os.homedir(),h.slice(2));
const dir=p.resolve(h,"lmm-provider-packages");fs.mkdirSync(dir,{recursive:true,mode:0o700});const s=fs.lstatSync(dir);if(!s.isDirectory()||s.isSymbolicLink()||s.uid!==process.getuid()||(s.mode&0o022))throw Error("Unsafe DSH cache");console.log(fs.realpathSync(dir));
')
sha='21bc853b321906550cf529cecc83719e6d14fd70041cc7cb92e4aecd6316d3f1'
plugin="$cache/$sha.tgz"
work=$(mktemp -d "$cache/.download.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
curl --proto '=https' --proto-redir '=https' -fsSL 'https://github.com/TokenNotIncluded/dsh-lmm-provider/releases/download/v0.1.0-alpha.9/dsh-lmm-provider.tgz' -o "$work/plugin.tgz"
node -e '
const fs=require("node:fs"),crypto=require("node:crypto"),[source,target,sha]=process.argv.slice(1);const check=path=>{const s=fs.lstatSync(path);if(!s.isFile()||s.isSymbolicLink()||s.uid!==process.getuid()||(s.mode&0o022)||crypto.createHash("sha256").update(fs.readFileSync(path)).digest("hex")!==sha)throw Error("DSH checksum mismatch.");};
check(source);fs.chmodSync(source,0o600);try{fs.linkSync(source,target);}catch(error){if(error.code!=="EEXIST")throw error;}check(target);
' "$work/plugin.tgz" "$plugin" "$sha"
dsh plugin --profile "${1:-web}" add "$plugin" --ignore-scripts
