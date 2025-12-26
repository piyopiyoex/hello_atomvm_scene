patch_sdkconfig_defaults() {
  local path
  path="$(SDKCONFIG_DEFAULTS)"
  if [ ! -f "$path" ]; then
    fail "Expected sdkconfig.defaults at: $path"
  fi

  local want_ipv6='CONFIG_LWIP_IPV6=y'
  local want_partitions='CONFIG_PARTITION_TABLE_CUSTOM_FILENAME="partitions-elixir.csv"'
  local missing=0

  grep -qF "$want_ipv6" "$path" || missing=1
  grep -qF "$want_partitions" "$path" || missing=1

  if [ "$missing" -eq 0 ]; then
    ok "sdkconfig.defaults already contains required lines."
    return 0
  fi

  echo_heading "Patching sdkconfig.defaults"
  {
    echo ""
    echo "# Added by scripts/atomvm-esp32.sh"
    grep -qF "$want_ipv6" "$path" || echo "$want_ipv6"
    grep -qF "$want_partitions" "$path" || echo "$want_partitions"
  } >>"$path"

  ok "sdkconfig.defaults patched."
}
