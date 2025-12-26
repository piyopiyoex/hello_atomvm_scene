erase_cmd() {
  sync_cmd
  preflight_basic
  resolve_port

  echo_heading "Erasing flash"
  idf_run "$(ESP32_DIR)" esptool.py --chip auto --port "$PORT" --baud "$BAUD" erase_flash
  ok "Erase complete."
}
