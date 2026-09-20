#!/usr/bin/env bash
# Complete function before execution: safe when downloaded through a pipe.
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

case "${1:-}" in
  --help|-h) printf 'LMM menu: bash menu.sh [--help]\nInteractive terminal required. Choose Pi, DSH or LMM CLI, then an action.\n'; exit 0;;
  '') ;;
  *) printf 'Unknown option. Use --help.\n' >&2; exit 2;;
esac
if ! { exec 3</dev/tty; } 2>/dev/null; then
  printf '需要交互终端。请在终端运行菜单；自动化请使用底层安装脚本。\n' >&2; exit 2
fi
command -v curl >/dev/null 2>&1 || { printf '请先安装 curl。\n' >&2; exit 2; }
expected_hash() { case "$1" in
pi.sh) printf '%s' '0dcc9f61ece125c9b0dacdcad28429b98e5d886ce8f2ef3b9f219faf4109282c';;
dsh.sh) printf '%s' '9ebfbc135329b9a1b2a0a36dd372456740ba961042494aec6ecaf9521df6ceb3';;
lmm.sh) printf '%s' 'bba6547ccb32f6cbafc9d63f662e32959089b448922c375d22931ed135b44d66';;
lmm-use.sh) printf '%s' '8f5cb27ef99bc3fd51a5b85e5aba0418f791e3cae03cd0ea624384b3dd50a06b';;
*) return 1;;
esac; }
ask() { printf '%s' "$1"; IFS= read -r answer <&3 || exit 0; }
umask 077
temp_root=$(lmm_temp_root)
lmm_check_storage "$temp_root" || exit 1
mkdir -p "$temp_root" || exit 1
work=$(mktemp -d "$temp_root/lmm-menu.XXXXXXXX") || exit 1
trap 'rm -rf -- "$work"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
network=auto
root=$(lmm_root)
fetch_script() {
  local name=$1 expected url
  expected=$(expected_hash "$name") || return 1
  if [ -f "$work/$name" ] && [ "$(sha256 "$work/$name")" = "$expected" ]; then return 0; fi
  printf '正在获取并校验安装程序（下载慢时会重试）…\n'
  for url in "https://api.lmm.best/scripts/$name" "https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/b21e36ecfdae2a1c97f86177f841635552ec40db/$name"; do
    if curl -q -fSL --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 120 --speed-limit 1024 --speed-time 20 --retry 2 --retry-delay 2 "$url" -o "$work/download"; then
      if [ "$(sha256 "$work/download")" = "$expected" ]; then mv "$work/download" "$work/$name"; return 0; fi
      printf '文件版本或校验不匹配，尝试固定版本备用地址。\n' >&2
    fi
  done
  printf '下载失败，未执行任何未校验的文件。请检查网络后重试。\n' >&2; return 1
}
run_script() {
  local name=$1 code; shift
  fetch_script "$name" || return 1
  bash "$work/$name" "$@" <&3; code=$?
  if [ "$code" -eq 0 ]; then printf '\n操作完成。\n'
  else printf '\n操作退出，状态码 %s；请查看上方提示。可切换网络后重试。\n' "$code"; fi
  return "$code"
}
help_tool() {
  case "$tool" in
    pi) printf '\nPi：安装后选择启动，输入 /login 并选择 LMM 完成浏览器授权，再用 /model 选模型。\n';;
    dsh) printf '\nDSH：启动后打开终端提示的网址，在 Settings → Models 的 LMM 卡片选择 Sign in with LMM。\n';;
    lmm) printf '\nLMM CLI 是开发预览版。支持目录、状态、诊断、登录和模型列表；setup 目前只提供计划，不会安装应用。\nLinux 登录需要 Secret Service；SSH 登录需浏览器能访问当前主机回调地址。\n';;
  esac
  printf '安装位置：%s\n默认不修改 PATH；关闭后可重新运行菜单启动。\n' "$root"
}
while :; do
  printf '\n━━━━━━━━ LMM 工具菜单 ━━━━━━━━\n1  Pi Coding Agent\n2  DSH + LMM 插件\n3  LMM CLI（开发预览）\n4  下载网络（当前：%s）\n0  退出\n' "$network"
  ask '输入数字：'
  case "$answer" in
    0) exit 0;;
    4) printf '\n1 自动选择  2 官方源  3 国内镜像\n'; ask '选择：'; case "$answer" in 1) network=auto;; 2) network=official;; 3) network=china;; *) printf '无效选择。\n';; esac; continue;;
    1) tool=pi;; 2) tool=dsh;; 3) tool=lmm;; *) printf '请输入菜单中的数字。\n'; continue;;
  esac
  while :; do
    printf '\n── %s ──\n1  安装 / 修复\n2  更新到菜单维护的版本\n3  检查安装环境\n4  启动 / 使用\n5  登录与使用说明\n0  返回\n' "$tool"
    ask '输入数字：'
    case "$answer" in
      0) break;;
      1) run_script "$tool.sh" --network "$network" || :;;
      2) run_script "$tool.sh" --network "$network" --update || :;;
      3) run_script "$tool.sh" --check || :;;
      5) help_tool;;
      4)
        if [ "$tool" = lmm ]; then
          printf '\n1 应用目录  2 状态  3 诊断  4 安装计划（不执行）\n5 登录 LMM  6 模型列表  7 退出登录  0 返回\n'
          ask '选择：'
          case "$answer" in 1) action=catalog;; 2) action=status;; 3) action=doctor;; 4) action=plan;; 5) action=login;; 6) action=models;; 7) action=logout;; 0) continue;; *) printf '无效选择。\n'; continue;; esac
          run_script lmm-use.sh "$action" || :
        elif [ -x "$root/bin/$tool" ]; then
          help_tool
          if [ "$tool" = dsh ]; then "$root/bin/dsh" --profile web <&3; else "$root/bin/pi" <&3; fi
          printf '\n已返回菜单。\n'
        else printf '尚未安装，请先选择 1。\n'; fi;;
      *) printf '请输入菜单中的数字。\n';;
    esac
  done
done
)
if true; then
  lmm_menu_main "$@"
fi
