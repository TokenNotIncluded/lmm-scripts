#!/usr/bin/env bash
set -euo pipefail
[[ $# = 0 ]] || { echo 'Usage: bash menu.sh' >&2; exit 2; }
tools=(pi dsh lmm codex claude-code cc-switch clash-verge-rev codewhale opencode cursor-cli grok-build gemini qwen-code kimi codebuddy hermes openclaw astrbot aider cursor cherry-studio ollama uv)
if [[ -n ${TERMUX_VERSION:-} || ${PREFIX:-} == */com.termux/files/usr ]]; then tools=(pi dsh lmm codex claude-code codewhale); fi
dir=$(dirname -- "${BASH_SOURCE[0]:-}")
while true; do
  printf '\nInstall / update\n'
  for i in "${!tools[@]}"; do printf '%s  %s\n' "$((i+1))" "${tools[i]}"; done
  printf '0  Exit\n> '
  read -r choice </dev/tty || exit 1
  [[ $choice = 0 ]] && exit 0
  [[ $choice =~ ^[1-9][0-9]?$ ]] || continue
  ((choice <= ${#tools[@]})) || continue
  tool=${tools[choice-1]}
  case "$tool" in
    cursor-cli|grok-build|gemini|qwen-code|kimi|codebuddy|hermes|openclaw|astrbot|aider)
      printf '1  Install / update\n2  Configure / login (already installed)\n0  Back\n> '
      read -r action </dev/tty || exit 1
      case "$action" in
        1) set -- install;;
        2)
          set -- setup
          if [[ $tool = astrbot ]]; then
            printf 'AstrBot instance directory:\n> '
            read -r instance_dir </dev/tty || exit 1
            [[ -n $instance_dir ]] || continue
            set -- setup "$instance_dir"
          fi;;
        *) continue;;
      esac;;
    codewhale) set -- menu;;
    *) set --;;
  esac
  # Positional parameters also work with empty arguments under Bash 3 + nounset.
  if [[ -n ${BASH_SOURCE[0]:-} && -f $dir/$tool.sh ]]; then
    bash "$dir/$tool.sh" "$@" </dev/tty || printf 'Installation failed.\n' >&2
  else
    revision=873bb8de2d9af00fb2a5fbb592b3da094e665271
    case "$tool" in pi|dsh|lmm|codex|claude-code|cc-switch|clash-verge-rev|codewhale|opencode) ;; *) revision=main;; esac
    script=$(curl -fsSL "https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/${LMM_SCRIPTS_REV:-$revision}/$tool.sh") || continue
    bash -c "$script" -- "$@" </dev/tty || printf 'Installation failed.\n' >&2
  fi
done
