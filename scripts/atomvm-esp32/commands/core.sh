core_cmd() {
  echo_heading "Building core libraries (Generic UNIX)"
  mkdir -p "${ATOMVM_DIR}/build"
  (
    cd "${ATOMVM_DIR}/build"
    run cmake ..
    run cmake --build .
  )

  if [ ! -f "$(BOOT_AVM)" ]; then
    fail "Missing: $(BOOT_AVM)"
  fi
  ok "Generated: $(BOOT_AVM)"
}
