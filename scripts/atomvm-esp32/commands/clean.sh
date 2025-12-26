clean_cmd() {
  echo_heading "Cleaning build artifacts"

  local esp32_build
  esp32_build="$(ESP32_DIR)/build"

  if [ -d "$esp32_build" ]; then
    run rm -rf "$esp32_build"
    ok "Removed: $esp32_build"
  else
    ok "Nothing to remove: $esp32_build"
  fi

  if [ "$CLEAN_ALL" -eq 1 ]; then
    local generic_build
    generic_build="${ATOMVM_DIR}/build"

    if [ -d "$generic_build" ]; then
      run rm -rf "$generic_build"
      ok "Removed: $generic_build"
    else
      ok "Nothing to remove: $generic_build"
    fi
  else
    ok "Kept: ${ATOMVM_DIR}/build (use 'clean --all' to remove)"
  fi
}
