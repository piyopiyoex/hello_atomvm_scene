#!/usr/bin/env bash
set -Eeuo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

usage() {
  local script_name
  script_name="$(basename "$0")"

  cat <<EOF
Usage:
  ${script_name} <command> [options]

Commands:
  sync              Ensure AtomVM + AtomGL repos exist and patch sdkconfig.defaults
  core              Build Generic UNIX core libs (boot AVM)
  build             Build ESP32 + mkimage (delegates to tools/atomvm-esp32-build-image.sh)
  erase             Erase flash (esptool.py via ESP-IDF)
  flash             Flash locally-built image (delegates to tools/atomvm-esp32-flash-image.sh)
  monitor           Serial monitor (delegates to tools/atomvm-esp32-monitor.sh)
  configure         Configure actions (delegates to tools/atomvm-esp32-configure.sh)
  clean             Remove build artifacts
  build-erase-flash Run: sync -> core -> build -> erase -> flash

Options (used by some commands):
  --idf-dir PATH          ESP-IDF root (contains export.sh)
  --target TARGET         Target chip (e.g. esp32, esp32s3)  [required for build/build-erase-flash]
  --port PORT             Serial port (optional; auto-detect if omitted) [erase/flash/monitor/build-erase-flash]
  --baud BAUD             Baud for erase (default: 921600) [erase/build-erase-flash]
  -h, --help              Show help
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TOOLS_DIR="${SCRIPT_DIR}/tools"

ATOMVM_WRAPPER_DIR="${ROOT}/atomvm"
ATOMVM_DIR="${ATOMVM_WRAPPER_DIR}/AtomVM"

ATOMVM_URL="https://github.com/atomvm/AtomVM.git"
ATOMGL_URL="https://github.com/atomvm/atomgl.git"
ATOMVM_REF="main"
ATOMGL_REF="main"

SDKCFG_WANT_IPV6='CONFIG_LWIP_IPV6=y'
SDKCFG_WANT_PARTITIONS='CONFIG_PARTITION_TABLE_CUSTOM_FILENAME="partitions-elixir.csv"'

die() {
  printf "✖ %s\n" "$*" >&2
  exit 1
}
run() {
  printf "+ %s\n" "$*"
  "$@"
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }
require_executable() { [ -x "$1" ] || die "Missing tool: $1"; }

# Usage: append_if_set array_name flag value
append_if_set() {
  local -n ary="$1"
  local flag="$2"
  local value="$3"
  if [ -n "$value" ]; then
    ary+=("$flag" "$value")
  fi
}

resolve_idf_dir() {
  local override="$1"
  if [ -n "$override" ]; then
    printf "%s" "$override"
  elif [ -n "${ESP_IDF_DIR:-}" ]; then
    printf "%s" "${ESP_IDF_DIR}"
  elif [ -n "${IDF_PATH:-}" ]; then
    printf "%s" "${IDF_PATH}"
  else
    printf "%s" "${HOME}/esp/esp-idf"
  fi
}

auto_port() {
  local p
  if [ -d /dev/serial/by-id ]; then
    for p in /dev/serial/by-id/*; do
      [ -e "$p" ] && {
        printf "%s" "$p"
        return 0
      }
    done
  fi

  for p in /dev/ttyACM* /dev/ttyUSB*; do
    [ -e "$p" ] && {
      printf "%s" "$p"
      return 0
    }
  done

  return 1
}

ensure_repo_present() {
  local name="$1" dir="$2" url="$3" ref="$4"

  if [ -d "${dir}/.git" ]; then
    return 0
  fi

  [ ! -e "$dir" ] || die "${name} exists but is not a git repo: ${dir}"
  mkdir -p "$(dirname "$dir")"

  if [ -n "$ref" ]; then
    run git clone --filter=blob:none --depth 1 --branch "$ref" "$url" "$dir"
  else
    run git clone --filter=blob:none --depth 1 "$url" "$dir"
  fi
}

patch_sdkconfig_defaults() {
  local esp32_dir="${ATOMVM_DIR}/src/platforms/esp32"
  local path="${esp32_dir}/sdkconfig.defaults"
  local marker="# Added by hello_atomvm_scene/scripts/atomvm-esp32.sh"

  [ -f "$path" ] || die "sdkconfig.defaults not found: ${path}"

  local want_lines=("$SDKCFG_WANT_IPV6" "$SDKCFG_WANT_PARTITIONS")
  local line needs_patch="0"

  for line in "${want_lines[@]}"; do
    grep -qF "$line" "$path" || needs_patch="1"
  done

  [ "$needs_patch" = "1" ] || return 0

  {
    printf "\n"
    printf "%s\n" "$marker"
    for line in "${want_lines[@]}"; do
      grep -qF "$line" "$path" || printf "%s\n" "$line"
    done
  } >>"$path"

  printf "✔ patched: %s\n" "$path"
}

idf_env_run() {
  local idf_dir="$1" workdir="$2"
  shift 2

  [ -f "${idf_dir}/export.sh" ] || die "ESP-IDF export.sh not found: ${idf_dir}/export.sh"

  (
    set -Eeuo pipefail
    # shellcheck source=/dev/null
    source "${idf_dir}/export.sh" >/dev/null 2>&1
    cd "$workdir"
    "$@"
  )
}

require_target_arg() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --target)
      shift
      [ "$#" -gt 0 ] || die "--target requires a value"
      return 0
      ;;
    --) break ;;
    esac
    shift
  done
  die "--target is required for: build"
}

sync_cmd() {
  require_cmd git

  ensure_repo_present "AtomVM" "${ATOMVM_DIR}" "${ATOMVM_URL}" "${ATOMVM_REF}"

  local atomgl_dir="${ATOMVM_DIR}/src/platforms/esp32/components/atomgl"
  ensure_repo_present "AtomGL" "${atomgl_dir}" "${ATOMGL_URL}" "${ATOMGL_REF}"

  patch_sdkconfig_defaults
}

core_cmd() {
  local boot_avm="${ATOMVM_DIR}/build/libs/esp32boot/elixir_esp32boot.avm"
  require_executable "${TOOLS_DIR}/atomvm-build-boot-avm.sh"

  if [ -f "$boot_avm" ]; then
    printf "✔ core already built: %s\n" "$boot_avm"
  else
    run "${TOOLS_DIR}/atomvm-build-boot-avm.sh" --atomvm-repo "${ATOMVM_WRAPPER_DIR}"
  fi
}

build_cmd() {
  require_executable "${TOOLS_DIR}/atomvm-esp32-build-image.sh"
  require_target_arg "$@"
  run "${TOOLS_DIR}/atomvm-esp32-build-image.sh" --atomvm-repo "${ATOMVM_WRAPPER_DIR}" "$@"
}

flash_cmd() {
  require_executable "${TOOLS_DIR}/atomvm-esp32-flash-image.sh"
  run "${TOOLS_DIR}/atomvm-esp32-flash-image.sh" --atomvm-repo "${ATOMVM_WRAPPER_DIR}" "$@"
}

monitor_cmd() {
  require_executable "${TOOLS_DIR}/atomvm-esp32-monitor.sh"
  run "${TOOLS_DIR}/atomvm-esp32-monitor.sh" --atomvm-repo "${ATOMVM_WRAPPER_DIR}" "$@"
}

configure_cmd() {
  require_executable "${TOOLS_DIR}/atomvm-esp32-configure.sh"
  run "${TOOLS_DIR}/atomvm-esp32-configure.sh" --atomvm-repo "${ATOMVM_WRAPPER_DIR}" "$@"
}

erase_cmd() {
  local idf_dir_override="" port="" baud="921600"

  while [ "$#" -gt 0 ]; do
    case "$1" in
    --idf-dir)
      shift
      [ "$#" -gt 0 ] || die "--idf-dir requires a value"
      idf_dir_override="$1"
      shift
      ;;
    --port | -p)
      shift
      [ "$#" -gt 0 ] || die "--port requires a value"
      port="$1"
      shift
      ;;
    --baud)
      shift
      [ "$#" -gt 0 ] || die "--baud requires a value"
      baud="$1"
      shift
      ;;
    --)
      shift
      break
      ;;
    *) die "Unknown arg for erase: $1" ;;
    esac
  done

  local idf_dir
  idf_dir="$(resolve_idf_dir "$idf_dir_override")"

  if [ -n "$port" ]; then
    [ -e "$port" ] || die "Port not found: ${port}"
  else
    port="$(auto_port)" || die "Could not auto-detect a serial port. Pass --port."
  fi

  idf_env_run "$idf_dir" "${ATOMVM_DIR}/src/platforms/esp32" \
    esptool.py --chip auto --port "$port" --baud "$baud" erase_flash
}

clean_cmd() {
  [ "${1:-}" = "--" ] && shift || [ "$#" -eq 0 ] || die "Unknown arg for clean: $1"
  local esp32_build="${ATOMVM_DIR}/src/platforms/esp32/build"
  [ -d "$esp32_build" ] && run rm -rf "$esp32_build"
}

build_erase_flash_cmd() {
  local target="" idf_dir="" port="" baud="921600" passthru=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
    --target)
      shift
      [ "$#" -gt 0 ] || die "--target requires a value"
      target="$1"
      shift
      ;;
    --idf-dir)
      shift
      [ "$#" -gt 0 ] || die "--idf-dir requires a value"
      idf_dir="$1"
      shift
      ;;
    --port | -p)
      shift
      [ "$#" -gt 0 ] || die "--port requires a value"
      port="$1"
      shift
      ;;
    --baud)
      shift
      [ "$#" -gt 0 ] || die "--baud requires a value"
      baud="$1"
      shift
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        passthru+=("$1")
        shift
      done
      ;;
    *)
      passthru+=("$1")
      shift
      ;;
    esac
  done

  [ -n "$target" ] || die "--target is required for: build-erase-flash"

  sync_cmd
  core_cmd

  local build_args=(--target "$target")
  append_if_set build_args --idf-dir "$idf_dir"
  build_args+=(-- "${passthru[@]}")

  local erase_args=(--baud "$baud")
  append_if_set erase_args --idf-dir "$idf_dir"
  append_if_set erase_args --port "$port"
  erase_args+=(--)

  local flash_args=()
  append_if_set flash_args --idf-dir "$idf_dir"
  append_if_set flash_args --port "$port"
  flash_args+=(-- "${passthru[@]}")

  build_cmd "${build_args[@]}"
  erase_cmd "${erase_args[@]}"
  flash_cmd "${flash_args[@]}"
}

main() {
  local cmd="${1:-}"

  if [ -z "$cmd" ]; then
    usage
    return 2
  fi
  shift || true

  case "$cmd" in
  -h | --help)
    usage
    return 0
    ;;
  sync) sync_cmd ;;
  core) core_cmd ;;
  build) build_cmd "$@" ;;
  erase) erase_cmd "$@" ;;
  flash) flash_cmd "$@" ;;
  monitor) monitor_cmd "$@" ;;
  configure) configure_cmd "$@" ;;
  clean) clean_cmd "$@" ;;
  build-erase-flash) build_erase_flash_cmd "$@" ;;
  *)
    usage
    die "Unknown command: ${cmd}"
    ;;
  esac
}

main "$@"
