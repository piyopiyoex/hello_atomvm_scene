flash_cmd() {
  sync_cmd
  preflight_basic
  resolve_port

  echo_heading "Flashing image"
  idf_run "$(ESP32_DIR)" bash "./build/flashimage.sh" -p "$PORT"
  ok "Flash complete."
}
