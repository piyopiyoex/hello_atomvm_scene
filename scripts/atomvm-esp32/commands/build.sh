build_cmd() {
  sync_cmd
  preflight_basic

  echo_heading "Building AtomVM for ESP32 (${TARGET})"
  idf_run "$(ESP32_DIR)" idf.py set-target "$TARGET"
  idf_run "$(ESP32_DIR)" idf.py reconfigure
  idf_run "$(ESP32_DIR)" idf.py build
  ok "ESP32 build complete."
}
