install_lmm() {
  PHASE='LMM CLI'
  local hash target="$ROOT/apps/lmm/$LMM_VERSION-$PLATFORM" archive
  if [ "$FORCE" = 0 ] && [ -x "$target/lmm" ] && [ -f "$target/.lmm-managed" ]; then CLIENT="$target/lmm"; return; fi
  mkdir -p "$STAGE/lmm"
  if [ "$SOURCE" = 1 ]; then
    command -v cargo >/dev/null 2>&1 || fail 'Source builds need Rust 1.88+ and OS build tools. Install them first, then rerun --from-source.'
    log 'Building the pinned crate; Cargo reuses its existing dependency/build caches. This can take several minutes.'
    export CARGO_HTTP_TIMEOUT="$STALL_TIMEOUT" CARGO_NET_RETRY="$RETRIES"
    export CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$CACHE/cargo-target}
    cargo install lmm-cli --version "$LMM_VERSION" --locked --root "$STAGE/cargo" </dev/null
    cp -- "$STAGE/cargo/bin/lmm" "$STAGE/lmm/lmm"
  else
    if [ "$OS" = android ]; then
      fail 'No Android LMM CLI binary is provided. The Linux archive is not compatible with Termux.'
    fi
    hash=$(lmm_hash "$PLATFORM")
    [ -n "$hash" ] || fail "No prebuilt CLI for $PLATFORM yet. With Rust 1.88+ and build tools, use --from-source."
    archive="$CACHE/lmm-v$LMM_VERSION-$PLATFORM.tar.gz"
    download "$LMM_RELEASE_BASE/${archive##*/}" "$archive" "$hash"
    tar -xzf "$archive" -C "$STAGE/lmm"
  fi
  chmod +x "$STAGE/lmm/lmm"
  "$STAGE/lmm/lmm" --version >/dev/null || fail 'CLI cannot run here. Linux x64 preview binaries need glibc 2.39+; use --from-source on older Linux.'
  printf '%s\n' "$LMM_VERSION" > "$STAGE/lmm/.lmm-managed"
  mkdir -p "$(dirname "$target")"
  if [ -e "$target" ]; then [ -f "$target/.lmm-managed" ] || fail "Unowned path: $target"; target="$target-reinstall-$(date +%s)-$$"; fi
  mv -- "$STAGE/lmm" "$target"; CLIENT="$target/lmm"
}
install_tool() { install_lmm; }
