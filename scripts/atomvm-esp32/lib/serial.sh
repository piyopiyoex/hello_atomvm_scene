resolve_port() {
  if [ -n "$PORT" ]; then
    if [ ! -e "$PORT" ]; then
      fail "Port not found: $PORT"
    fi
    ok "Using port: $PORT"
    return 0
  fi

  local ports=()
  shopt -s nullglob
  ports=(/dev/ttyACM* /dev/ttyUSB*)
  shopt -u nullglob

  if [ "${#ports[@]}" -eq 0 ]; then
    fail "Could not auto-detect a serial port. Pass --port (e.g. /dev/ttyACM0)."
  fi

  mapfile -t ports < <(printf "%s\n" "${ports[@]}" | sort -u)

  if [ "${#ports[@]}" -eq 1 ]; then
    PORT="${ports[0]}"
    ok "Auto-detected port: $PORT"
    return 0
  fi

  echo_heading "Multiple serial ports detected"
  printf "  %s\n" "${ports[@]}"
  fail "Please specify --port."
}
