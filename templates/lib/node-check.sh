  if [ "$TARGET" != lmm ]; then
    if compatible_node; then log 'Current PATH has compatible Node/npm.'
    elif [ -x "$ROOT/runtime/node-v$NODE_VERSION-$PLATFORM/bin/node" ]; then log 'Managed Node runtime is available.'
    else fail 'No compatible Node runtime found'; fi
  fi
