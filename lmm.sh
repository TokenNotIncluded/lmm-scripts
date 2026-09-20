#!/usr/bin/env bash
set -euo pipefail
if [[ $# = 1 && $1 = --from-source ]]; then exec cargo install lmm-cli --version 0.1.0 --locked; fi
[[ $# = 0 ]] || { echo 'Usage: bash lmm.sh [--from-source]' >&2; exit 2; }
if [[ -n ${TERMUX_VERSION:-} || ${PREFIX:-} == */com.termux/files/usr ]]; then
  echo 'No Android binary. Source builds require a working Rust toolchain.' >&2; exit 1
fi
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) platform=linux-x64;;
  Darwin/arm64) platform=darwin-arm64;;
  *) echo 'No prebuilt LMM CLI for this platform; use --from-source.' >&2; exit 1;;
esac
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
curl -fsSL "https://github.com/TokenNotIncluded/api.lmm.best/releases/download/lmm-cli-v0.1.0/lmm-v0.1.0-$platform.tar.gz" -o "$work/lmm.tar.gz"
tar -xzf "$work/lmm.tar.gz" -C "$work"
"$work/lmm" --version
mkdir -p "$HOME/.local/bin"
install -m 755 "$work/lmm" "$HOME/.local/bin/lmm"
echo "$HOME/.local/bin/lmm"
