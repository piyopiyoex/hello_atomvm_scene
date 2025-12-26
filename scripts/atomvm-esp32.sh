#!/usr/bin/env bash
set -Eeuo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ------------------------------------------------------------------------------
# Config
# ------------------------------------------------------------------------------

# Project-local AtomVM checkout
ATOMVM_DIR="${ROOT}/atomvm/AtomVM"
ATOMVM_URL="https://github.com/atomvm/AtomVM.git"
ATOMVM_REF="main"

# AtomGL is pinned to a known-good revision; use a branch/tag or a full SHA.
ATOMGL_URL="https://github.com/atomvm/atomgl.git"
ATOMGL_REF="ed262189b82c9c30c153e16e8c7b64f15fe2adf8"

IDF_PATH_DEFAULT="${HOME}/esp/esp-idf"
IDF_PATH="${IDF_PATH:-$IDF_PATH_DEFAULT}"

TARGET="esp32s3"
PORT=""
BAUD="921600"

CLEAN_ALL=0

# Derived paths
ESP32_DIR() { echo "${ATOMVM_DIR}/src/platforms/esp32"; }
ATOMGL_DIR() { echo "$(ESP32_DIR)/components/atomgl"; }
SDKCONFIG_DEFAULTS() { echo "$(ESP32_DIR)/sdkconfig.defaults"; }
BOOT_AVM() { echo "${ATOMVM_DIR}/build/libs/esp32boot/elixir_esp32boot.avm"; }

SDKCONFIG_DEFAULTS_REL="src/platforms/esp32/sdkconfig.defaults"

# ------------------------------------------------------------------------------
# Load implementation
# ------------------------------------------------------------------------------

LIB_DIR="${SCRIPT_DIR}/atomvm-esp32/lib"
CMD_DIR="${SCRIPT_DIR}/atomvm-esp32/commands"

# shellcheck disable=SC1090,SC1091
source "${LIB_DIR}/ui.sh"
source "${LIB_DIR}/deps.sh"
source "${LIB_DIR}/idf.sh"
source "${LIB_DIR}/git.sh"
source "${LIB_DIR}/patch.sh"
source "${LIB_DIR}/serial.sh"

# shellcheck disable=SC1090,SC1091
source "${CMD_DIR}/sync.sh"
source "${CMD_DIR}/core.sh"
source "${CMD_DIR}/build.sh"
source "${CMD_DIR}/mkimage.sh"
source "${CMD_DIR}/erase.sh"
source "${CMD_DIR}/flash.sh"
source "${CMD_DIR}/clean.sh"
source "${CMD_DIR}/all.sh"

usage() {
  cat <<EOF
Usage:
  ./scripts/atomvm-esp32.sh <command> [options]

Commands:
  sync       Sync AtomVM + AtomGL and patch sdkconfig.defaults
  core       Build Generic UNIX (generates elixir_esp32boot.avm)
  build      idf.py set-target/reconfigure/build
  mkimage    mkimage.sh --boot <elixir_esp32boot.avm>
  erase      Erase flash (esptool.py via ESP-IDF env)
  flash      flashimage.sh -p <port> (via ESP-IDF env)
  clean      Remove build artifacts (ESP32 build only)
  all        Run: sync -> core -> build -> mkimage -> erase -> flash

Options:
  --idf-path PATH   ESP-IDF root (default: \$IDF_PATH or ${IDF_PATH_DEFAULT})
  --target TARGET   ESP-IDF target (default: ${TARGET})
  --port PORT       Serial port (default: auto-detect /dev/ttyACM* or /dev/ttyUSB*)
  --baud BAUD       Baud rate for erase (default: ${BAUD})

Clean options:
  --all            Also remove Generic UNIX build dir (${ATOMVM_DIR}/build)

  -h, --help       Show this help
EOF
}

parse_args() {
  CMD="${1:-}"
  shift || true

  while (("$#")); do
    case "$1" in
    --idf-path)
      IDF_PATH="${2:-}"
      shift 2
      ;;
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --port)
      PORT="${2:-}"
      shift 2
      ;;
    --baud)
      BAUD="${2:-}"
      shift 2
      ;;
    --all)
      CLEAN_ALL=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      fail "Unknown option: $1"
      ;;
    esac
  done

  if [ -z "$CMD" ]; then
    usage
    exit 2
  fi
}

main() {
  parse_args "$@"

  case "$CMD" in
  sync) sync_cmd ;;
  core) core_cmd ;;
  build) build_cmd ;;
  mkimage) mkimage_cmd ;;
  erase) erase_cmd ;;
  flash) flash_cmd ;;
  clean) clean_cmd ;;
  all) all_cmd ;;
  *)
    usage
    fail "Unknown command: $CMD"
    ;;
  esac
}

main "$@"
