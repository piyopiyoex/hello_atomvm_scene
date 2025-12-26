sync_cmd() {
  echo_heading "Syncing repositories"
  ensure_repo "AtomVM" "$ATOMVM_DIR" "$ATOMVM_URL" "$ATOMVM_REF"
  ensure_repo "AtomGL" "$(ATOMGL_DIR)" "$ATOMGL_URL" "$ATOMGL_REF"
  patch_sdkconfig_defaults
  ok "Repos ready."
}
