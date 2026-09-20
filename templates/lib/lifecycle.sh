release_setup() {
  if [ -n "$STAGE" ] && [ -d "$STAGE" ]; then rm -rf -- "$STAGE"; fi
  STAGE=''
  if [ "$LOCKED" = 1 ] && [ "$(cat "$ROOT/.setup-lock/pid" 2>/dev/null || true)" = "$$" ]; then
    rm -f -- "$ROOT/.setup-lock/pid" "$ROOT/.setup-lock/owner"
    rmdir "$ROOT/.setup-lock" 2>/dev/null || true
  fi
  LOCKED=0
}

cleanup() {
  rc=$?
  trap - EXIT
  release_setup
  if [ "$rc" -ne 0 ]; then
    log "Stopped during $PHASE. Existing launchers were preserved unless installation already completed."
    log 'Check disk space, HTTPS proxy/CA settings, or retry --network official / --network china. Do not disable TLS validation.'
  fi
  exit "$rc"
}

write_launcher() {
  local launcher="$ROOT/bin/$TARGET" temp="$STAGE/launcher"
  {
    if [ "$OS" = android ]; then printf '#!%s\n' "$BASH"
    else printf '#!/usr/bin/env bash\n'; fi
    printf '# Managed by LMM installers.\n' 
    # The launcher must expand PATH when it runs, not while it is generated.
    # shellcheck disable=SC2016
    if [ "$TARGET" != lmm ]; then printf 'export PATH=%s:"$PATH"\n' "$(quote_sh "$NODE_BIN${PNPM_BIN:+:$PNPM_BIN}")"; fi
    if [ "$TARGET" = lmm ]; then printf 'exec %s "$@"\n' "$(quote_sh "$CLIENT")"
    else printf 'exec %s %s "$@"\n' "$(quote_sh "$NODE_BIN/node")" "$(quote_sh "$CLIENT")"; fi
  } > "$temp"
  chmod +x "$temp"
  if [ -e "$launcher" ] && ! grep -q '# Managed by LMM installers.' "$launcher"; then fail "Refusing to overwrite your existing launcher: $launcher"; fi
  mv -f -- "$temp" "$launcher"
}

add_path() {
  [ "$ADD_PATH" = 1 ] || return 0
  local file marker='# >>> LMM tools PATH >>>' line
  line="export PATH=$(quote_sh "$ROOT/bin"):\"\$PATH\""
  PATH_FILES=("$HOME/.profile")
  case "${SHELL:-}" in */zsh) PATH_FILES+=("$HOME/.zshrc");; */bash) PATH_FILES+=("$HOME/.bashrc"); [ "$OS" != darwin ] || PATH_FILES+=("$HOME/.bash_profile");; */fish) log 'Fish users: add the printed bin directory with fish_add_path.';; esac
  for file in "${PATH_FILES[@]}"; do
    if [ -f "$file" ] && grep -Fq "$marker" "$file"; then
      grep -Fq "$line" "$file" || log "PATH marker already exists in $file; use the printed full command or adjust that entry manually."
      continue
    fi
    [ ! -L "$file" ] || { log "Not editing symlinked startup file: $file"; continue; }
    if [ -f "$file" ]; then cp -p -- "$file" "$file.lmm-backup-$(date +%Y%m%d%H%M%S)-$$"; fi
    printf '\n%s\n%s\n# <<< LMM tools PATH <<<\n' "$marker" "$line" >> "$file"
  done
}
