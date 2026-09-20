sha256() {
  local digest
  if command -v sha256sum >/dev/null 2>&1; then digest=$(sha256sum "$1") || return; printf '%s\n' "${digest%% *}"
  elif command -v shasum >/dev/null 2>&1; then digest=$(shasum -a 256 "$1") || return; printf '%s\n' "${digest%% *}"
  elif command -v openssl >/dev/null 2>&1; then digest=$(openssl dgst -sha256 "$1") || return; printf '%s\n' "${digest##* }"
  else printf 'Install a SHA-256 tool.\n' >&2; return 1; fi
}
