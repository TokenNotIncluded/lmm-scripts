lmm_root() {
  printf '%s\n' "${LMM_INSTALL_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/lmm-tools}"
}
