ensure_pnpm() {
  PHASE='DSH package manager'
  local directory="$ROOT/tools/pnpm/$PNPM_VERSION" work="$STAGE/pnpm"
  if [ -x "$directory/bin/pnpm" ] && [ -f "$directory/.lmm-managed" ]; then PNPM_BIN="$directory/bin"
  elif [ "$BOOTSTRAP" = 0 ]; then
    command -v pnpm >/dev/null 2>&1 || fail 'pnpm is missing; rerun without --no-bootstrap.'
    bounded pnpm --version
    PNPM_BIN=$(dirname "$(command -v pnpm)")
  else
    mkdir -p "$work" "$(dirname "$directory")"
    with_registry_retry npm install --global --prefix "$work" --ignore-scripts --no-audit --no-fund "pnpm@$PNPM_VERSION"
    bounded node "$work/bin/pnpm" --version
    printf '%s\n' "$PNPM_VERSION" > "$work/.lmm-managed"
    if [ -e "$directory" ]; then
      [ -f "$directory/.lmm-managed" ] || fail "Unowned package-manager directory: $directory"
      directory="$directory-reinstall-$(date +%s)-$$"
    fi
    mv -- "$work" "$directory"; PNPM_BIN="$directory/bin"
  fi
  export PATH="$PNPM_BIN:$PATH"
}
install_tool() {
  ensure_node; configure_npm; ensure_pnpm
  install_client @deepseek-ai/dsh "$DSH_VERSION" dsh
  PHASE='DSH LMM provider'
  local artifact="$CACHE/${DSH_PROVIDER_URL##*/}"
  download "$DSH_PROVIDER_URL" "$artifact" "$DSH_PROVIDER_SHA256"
  with_registry_retry node "$CLIENT" plugin --profile "$PROFILE" add "$artifact" --ignore-scripts --store-dir "$CACHE/pnpm"
}
