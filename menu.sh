#!/usr/bin/env bash
lmm_menu_main() (
set -u
lmm_root() {
  printf '%s\n' "${LMM_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/lmm-tools}"
}
sha256() {
  local digest
  if command -v sha256sum >/dev/null 2>&1; then digest=$(sha256sum "$1") || return; printf '%s\n' "${digest%% *}"
  elif command -v shasum >/dev/null 2>&1; then digest=$(shasum -a 256 "$1") || return; printf '%s\n' "${digest%% *}"
  elif command -v openssl >/dev/null 2>&1; then digest=$(openssl dgst -sha256 "$1") || return; printf '%s\n' "${digest##* }"
  else printf 'Install a SHA-256 tool.\n' >&2; return 1; fi
}
# Native Termux uses Android/bionic, not desktop Linux/glibc.
lmm_is_termux() {
  [ -n "${TERMUX_VERSION:-}${TERMUX_APP__PACKAGE_NAME:-}" ] ||
    case "${PREFIX:-}" in */com.termux/files/usr) true;; *) false;; esac
}
lmm_temp_root() {
  if [ -n "${TMPDIR:-}" ]; then printf '%s\n' "$TMPDIR"
  elif lmm_is_termux; then printf '%s/tmp\n' "${PREFIX:-$HOME/.cache/lmm-tools}"
  else printf '/tmp\n'; fi
}
lmm_check_storage() {
  lmm_is_termux || return 0
  local resolved
  # realpath -m also resolves missing paths and symlinked storage aliases.
  command -v realpath >/dev/null 2>&1 || {
    printf 'Termux needs coreutils: pkg install coreutils\n' >&2; return 1;
  }
  resolved=$(realpath -m -- "$1") || return 1
  case "$resolved/" in
    /sdcard/*|/storage/*|/mnt/sdcard/*|/mnt/media_rw/*|/mnt/runtime/*|/mnt/user/*|/mnt/pass_through/*)
      printf 'Use Termux private storage under HOME, not shared storage: %s\n' "$1" >&2
      return 1;;
  esac
}

tools=(pi dsh lmm codex claude-code cc-switch clash-verge-rev)
labels=('Pi + LMM' 'DSH + LMM' 'LMM CLI (preview)' 'Codex CLI' 'Claude Code' 'CC Switch' 'Clash Verge Rev')
kinds=(managed managed managed external external desktop desktop)
root=$(lmm_root); network=auto
show_tools() {
  local i
  for i in "${!tools[@]}"; do
    if lmm_is_termux && [ "${kinds[$i]}" = desktop ]; then continue; fi
    printf '%s  %s\n' "$((i+1))" "${labels[$i]}"
  done
}
case "${1:-}" in
  --help|-h) printf 'LMM menu: bash menu.sh [--list]\n'; exit 0;;
  --list) show_tools; exit 0;;
  '') ;;
  *) printf 'Unknown option. Use --help.\n' >&2; exit 2;;
esac
if ! { exec 3</dev/tty; } 2>/dev/null; then printf '需要交互终端；自动化请直接运行工具脚本。\n' >&2; exit 2; fi
command -v curl >/dev/null 2>&1 || { printf '请先安装 curl。\n' >&2; exit 2; }
expected_hash() { case "$1" in
pi.sh) printf '%s' 'da34fe287699808d1f1ebac0dbb4e16ddf91c7c32f351b89f6d9ba6fe9a57288';;
dsh.sh) printf '%s' '9198b7b0cea47a2fe26717ec42466ff332539dec617740ef400c21a6fe4c4807';;
lmm.sh) printf '%s' 'f8b5f76f16786c600fc1d0c67475d04527af4cdad2f246b205e5318e1ade6da9';;
codex.sh) printf '%s' '624bef260481f86fa87b4f2cbd072db5aedd611a418e8b981aca82e73dc80ec7';;
claude-code.sh) printf '%s' '616e5715fa11e029c1501d66058436f58cc79d92dd550018f46d6231a95ca555';;
cc-switch.sh) printf '%s' '1e52aa4be0d47af1d3ddb89cf85a643d373910da3eeb11aecb0389a67f6d0d97';;
clash-verge-rev.sh) printf '%s' '9f807a11bcf1271cf449889abf75a70389ef4cc0e6b1520cd9427cadf045a91b';;
lmm-use.sh) printf '%s' '8f5cb27ef99bc3fd51a5b85e5aba0418f791e3cae03cd0ea624384b3dd50a06b';;
*) return 1;;
esac; }
ask() { printf '%s' "$1"; IFS= read -r answer <&3 || exit 0; }
tmp=$(lmm_temp_root); lmm_check_storage "$tmp" || exit 1
mkdir -p "$tmp" || exit 1
work=$(mktemp -d "$tmp/lmm-menu.XXXXXXXX") || exit 1
trap 'rm -rf -- "$work"' EXIT
trap 'exit 130' INT; trap 'exit 143' TERM
fetch_script() {
  local name=$1 expected url
  expected=$(expected_hash "$name") || return 1
  if [ -f "$work/$name" ] && [ "$(sha256 "$work/$name")" = "$expected" ]; then return 0; fi
  for url in "https://api.lmm.best/scripts/$name" "https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/b715e644bb665d841f59e063e14b0fc81c6d72bc/$name"; do
    if curl -q -fsSL --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 120 --retry 2 "$url" -o "$work/download"; then
      if [ "$(sha256 "$work/download")" = "$expected" ]; then mv "$work/download" "$work/$name"; return 0; fi
    fi
  done
  printf '下载失败或版本不匹配：%s\n' "$name" >&2; return 1
}
run_script() {
  local name=$1 code; shift
  fetch_script "$name" || return 1
  bash "$work/$name" "$@" <&3; code=$?
  [ "$code" -eq 0 ] || printf '\n退出码 %s，请查看上方错误。\n' "$code"
  return "$code"
}
help_tool() {
  case "$tool" in
    pi) printf 'pi → /login → LMM → /model。\n';;
    dsh) printf 'dsh web → Settings → Models → LMM。\n';;
    lmm) printf 'LMM CLI 是预览版；setup 仅生成计划。Linux 登录需要 Secret Service。\n';;
    codex) printf '运行 codex，按官方提示登录。Termux 使用已有 PRoot guest。\n';;
    claude-code) printf '运行 claude，按官方提示登录。Termux 使用已有 PRoot guest。\n';;
    *) printf '桌面应用按系统安装；不会自动配置账号、订阅或启用代理。\n';;
  esac
  if [ "$kind" = managed ]; then printf '受管目录：%s\n' "$root"
  else printf '使用官方安装位置；预览可查看安装方式。\n'; fi
}
while :; do
  printf '\nLMM 工具\n'; show_tools
  printf 'n  下载网络（%s）\n0  退出\n' "$network"
  ask '选择：'
  case "$answer" in
    0) exit 0;;
    n|N) printf '1 自动  2 官方  3 国内镜像\n'; ask '选择：'; case "$answer" in 1) network=auto;; 2) network=official;; 3) network=china;; esac; continue;;
  esac
  if ! [[ $answer =~ ^[1-9][0-9]*$ ]] || [ "${#answer}" -gt 2 ] || [ "$answer" -gt "${#tools[@]}" ]; then printf '无效选择。\n'; continue; fi
  index=$((answer-1)); tool=${tools[$index]}; kind=${kinds[$index]}
  if lmm_is_termux && [ "$kind" = desktop ]; then printf '此工具不支持 Termux。\n'; continue; fi
  while :; do
    printf '\n%s\n1 安装  2 更新  3 检查  4 启动  5 使用说明\n' "${labels[$index]}"
    [ "$kind" = managed ] || printf '6 预览安装方案\n'
    printf '0 返回\n'; ask '选择：'
    case "$answer" in
      0) break;;
      1) run_script "$tool.sh" --network "$network" || :;;
      2) run_script "$tool.sh" --network "$network" --update || :;;
      3) run_script "$tool.sh" --check || :;;
      5) help_tool;;
      6) if [ "$kind" != managed ]; then run_script "$tool.sh" --dry-run || :; fi;;
      4)
        if [ "$tool" = lmm ]; then
          printf '1 目录  2 状态  3 诊断  4 安装计划\n5 登录  6 模型  7 退出登录  0 返回\n'; ask '选择：'
          case "$answer" in 1) action=catalog;; 2) action=status;; 3) action=doctor;; 4) action=plan;; 5) action=login;; 6) action=models;; 7) action=logout;; *) continue;; esac
          run_script lmm-use.sh "$action" || :
        elif [ "$kind" != managed ]; then run_script "$tool.sh" --network "$network" --launch || :
        elif [ -x "$root/bin/$tool" ]; then
          if [ "$tool" = dsh ]; then "$root/bin/dsh" --profile web <&3; else "$root/bin/pi" <&3; fi
        else printf '请先安装。\n'; fi;;
      *) printf '无效选择。\n';;
    esac
  done
done
)
if true; then
  lmm_menu_main "$@"
fi
