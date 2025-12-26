mkimage_cmd() {
  sync_cmd
  preflight_basic

  if [ ! -f "$(BOOT_AVM)" ]; then
    core_cmd
  fi

  echo_heading "Generating release image (mkimage)"
  idf_run "$(ESP32_DIR)" bash "./build/mkimage.sh" --boot "$(BOOT_AVM)"

  local img
  img="$(ls -t "$(ESP32_DIR)"/build/*.img 2>/dev/null | head -n1 || true)"
  if [ -z "$img" ]; then
    fail "No .img found under $(ESP32_DIR)/build."
  fi
  ok "Image ready: $img"
}
