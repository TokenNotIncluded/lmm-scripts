#!/usr/bin/env bash
lmm_entry() {
set -euo pipefail
# shellcheck disable=SC2034
TARGET=codex
LIB_REVISION=60692bd80622a0d3d80ee501eacb8db139641a3e
for arg in "$@"; do
  case "$arg" in --) break;; --help|-h)
    printf '%s\n' "Install $TARGET" 'Options: --check --update --launch --dry-run --install-deps' '         --root PATH --version VERSION --network auto|official|china' '         --distro NAME (Termux Linux guest; default ubuntu) -- [launch arguments]' 'Uses upstream locations and update policies. LMM_LIB_DIR selects local helpers.'
    return 0;;
  esac
done
# Fetch completely before sourcing: process substitution alone hides curl errors.
lmm_source_lib() {
  local lmm_name=$1 lmm_text='' lmm_attempt
  if [ -n "${LMM_LIB_DIR:-}" ]; then
    lmm_text=$(cat -- "$LMM_LIB_DIR/$lmm_name") || {
      printf 'Cannot read local library: %s/%s\n' "$LMM_LIB_DIR" "$lmm_name" >&2; return 1;
    }
  else
    for lmm_attempt in 1 2 3; do
      if lmm_text=$(curl -q -fsSL --proto '=https' --proto-redir '=https' \
          --connect-timeout 10 --max-time 60 \
          "https://raw.githubusercontent.com/TokenNotIncluded/lmm-scripts/$LIB_REVISION/templates/lib/$lmm_name"); then
        break
      fi
      if [ "$lmm_attempt" = 3 ]; then
        printf 'Cannot load library %s at %s. Check the network or set LMM_LIB_DIR.\n' "$lmm_name" "$LIB_REVISION" >&2
        return 1
      fi
    done
  fi
  if [[ $lmm_text != *[![:space:]]* ]]; then
    printf 'Cannot load library %s at %s. Check the network or set LMM_LIB_DIR.\n' "$lmm_name" "$LIB_REVISION" >&2
    return 1
  fi
  # macOS Bash 3.2 needs a here-string when sourcing buffered text.
  if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
    # shellcheck disable=SC1091
    source /dev/stdin <<< "$lmm_text"
  else
    # shellcheck disable=SC1090
    source <(printf '%s\n' "$lmm_text")
  fi
}

for library in termux.sh quote.sh external.sh; do lmm_source_lib "$library" || exit $?; done
lmm_external_main "$@"
}
if true; then
  lmm_entry "$@"
fi
