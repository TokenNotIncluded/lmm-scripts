rank_urls() {
  local i=0 url response code elapsed probe_dir
  if ! command -v curl >/dev/null 2>&1; then for url in "$@"; do printf '%s\n' "$i"; i=$((i+1)); done; return; fi
  probe_dir=$(mktemp -d "$STAGE/probes.XXXXXX")
  for url in "$@"; do
    (
      response=$(curl -q --proto '=https' --proto-redir '=https' -ILs --connect-timeout 3 --max-time 5 -o /dev/null -w '%{http_code} %{time_starttransfer}' "$url" 2>/dev/null || true)
      code=${response%% *}; elapsed=${response#* }
      case "$code" in 2??|3??) ;; *) elapsed=999;; esac
      case "$elapsed" in ''|*[!0-9.]*) elapsed=999;; esac
      printf '%s %s\n' "$elapsed" "$i" > "$probe_dir/$i"
    ) &
    i=$((i+1))
  done
  wait
  cat "$probe_dir"/* | sort -n -k1,1 -k2,2 | while read -r elapsed index; do printf '%s\n' "$index"; done
}
urls_for() {
  URLS=("$1")
  case "$1" in
    https://nodejs.org/dist/*) MIRRORS=("https://npmmirror.com/mirrors/node/${1#https://nodejs.org/dist/}");;
    https://github.com/*) MIRRORS=("https://ghfast.top/$1" "https://ghproxy.net/$1");;
    *) MIRRORS=();;
  esac
  case "$NETWORK" in
    auto) URLS+=("${MIRRORS[@]}");;
    china) URLS=("${MIRRORS[@]}" "$1");;
  esac
}
download() {
  local official=$1 destination=$2 expected=$3 index url part attempt actual order transfer_status
  part="$destination.part"
  if [ -L "$destination" ] || [ -L "$part" ] || [ -L "$part.url" ]; then fail 'Refusing symlink cache entries'; fi
  if [ "$FORCE" = 0 ] && [ -f "$destination" ] && [ "$(sha256 "$destination")" = "$expected" ]; then log "Cached: ${destination##*/}"; return; fi
  if [ -f "$part" ] && [ "$(sha256 "$part")" = "$expected" ]; then mv -f -- "$part" "$destination"; rm -f -- "$part.url"; return; fi
  command -v curl >/dev/null 2>&1 || fail 'curl is required for downloads. Install it with your OS package manager.'
  if [[ $official == https://nodejs.org/dist/* && -n ${LMM_NODE_BASE_URL:-} ]]; then official="${LMM_NODE_BASE_URL%/}/${official#https://nodejs.org/dist/}"; fi
  urls_for "$official"
  if [ "$NETWORK" = auto ]; then order=$(rank_urls "${URLS[@]}"); else order=$(printf '%s\n' "${!URLS[@]}"); fi
  for index in $order; do
    url=${URLS[$index]}
    if [ -f "$part" ] && [ "$(cat "$part.url" 2>/dev/null || true)" != "$url" ]; then rm -f -- "$part"; fi
    printf '%s\n' "$url" > "$part.url"
    for ((attempt=1; attempt<=RETRIES; attempt++)); do
      log "Downloading ${destination##*/} (source $((index+1)), attempt $attempt; low-speed cutoff ${STALL_TIMEOUT}s)"
      if curl -q --proto '=https' --proto-redir '=https' -fL --connect-timeout "$CONNECT_TIMEOUT" --max-time "$DOWNLOAD_TIMEOUT" --speed-time "$STALL_TIMEOUT" --speed-limit "$MIN_SPEED" --continue-at - --output "$part" "$url"; then
        actual=$(sha256 "$part")
        if [ "$actual" = "$expected" ]; then mv -f -- "$part" "$destination"; rm -f -- "$part.url"; return; fi
        log 'Checksum mismatch: discarded the download; it will not be executed.'
        rm -f -- "$part"
        break
      else transfer_status=$?; fi
      # A server may reject Range; retry once from a clean file. Retain a
      # partial transfer after final failure for the next invocation.
      if [ "$attempt" = 1 ]; then case "$transfer_status" in 22|33|36) rm -f -- "$part";; esac; fi
    done
  done
  fail "Download failed: ${destination##*/}. Rerun to resume, or choose another --network mode."
}
