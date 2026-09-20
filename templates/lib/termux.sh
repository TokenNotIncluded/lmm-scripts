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
