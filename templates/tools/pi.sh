install_tool() {
  ensure_node; configure_npm
  install_client @earendil-works/pi-coding-agent "$PI_VERSION" pi
  PHASE='Pi LMM provider'
  with_registry_retry node "$CLIENT" install "npm:@tokennotincluded/pi-lmm-provider@$PI_PROVIDER_VERSION"
  if [ "$OS" = android ]; then log 'Optional clipboard: install the Termux:API app and pkg install termux-api. Open login links with termux-open-url.'; fi
}
