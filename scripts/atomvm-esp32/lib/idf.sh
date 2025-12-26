idf_run() {
  local workdir="$1"
  shift

  if [ ! -f "${IDF_PATH}/export.sh" ]; then
    fail "ESP-IDF export.sh not found: ${IDF_PATH}/export.sh"
  fi

  # shellcheck disable=SC1090
  (
    set -Eeuo pipefail
    source "${IDF_PATH}/export.sh" >/dev/null 2>&1
    cd "$workdir"
    "$@"
  )
}

preflight_basic() {
  require_cmd git
  require_cmd bash
  require_cmd cmake

  if [ ! -f "${IDF_PATH}/export.sh" ]; then
    fail "ESP-IDF export.sh not found: ${IDF_PATH}/export.sh"
  fi

  echo_heading "Preflight checks"
  idf_run "$(ESP32_DIR)" idf.py --version || fail "idf.py is not available (ESP-IDF not installed for ${TARGET}?)"
  idf_run "$(ESP32_DIR)" esptool.py version || fail "esptool.py is not available (ESP-IDF env issue?)"
  ok "Preflight complete."
}
