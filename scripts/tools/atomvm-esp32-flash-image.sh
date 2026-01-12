#!/usr/bin/env bash
set -euo pipefail

usage() {
  local script_name
  script_name="$(basename "$0")"

  cat <<EOF
Usage:
  ${script_name} --atomvm-repo PATH [OPTIONS] [-- FLASHIMAGE_ARGS...]

Description:
  Source ESP-IDF, cd into AtomVM's ESP32 platform dir, then flash the
  locally-built AtomVM release image via ./build/flashimage.sh.

Required:
  --atomvm-repo PATH      AtomVM repo root (or wrapper repo containing AtomVM/)

Options:
  --port PORT             Serial port (auto-detect if omitted)
  --idf-dir PATH          ESP-IDF directory (contains export.sh)
  --erase-flash           Run: esptool.py erase_flash before flashing
  --baud BAUD             Baud for erase_flash (default: 921600)
  -h, --help              Show help

FLASHIMAGE_ARGS:
  Anything after "--" is passed to ./build/flashimage.sh

Examples:
  ${script_name} --atomvm-repo ~/atomvm --port /dev/ttyACM0
  ${script_name} --atomvm-repo ~/atomvm --erase-flash
  ${script_name} --atomvm-repo ~/atomvm -- --help
EOF
}

die() {
  printf "✖ %s\n" "$*" >&2
  exit 1
}

resolve_esp32_dir() {
  local repo="$1"
  local candidate=""

  candidate="${repo}/src/platforms/esp32"
  if [[ -d "${candidate}" ]]; then
    printf "%s" "${candidate}"
    return 0
  fi

  candidate="${repo}/AtomVM/src/platforms/esp32"
  if [[ -d "${candidate}" ]]; then
    printf "%s" "${candidate}"
    return 0
  fi

  return 1
}

source_esp_idf() {
  local esp_idf_dir_override="$1"
  local esp_idf_dir=""

  if [[ -n "${esp_idf_dir_override}" ]]; then
    esp_idf_dir="${esp_idf_dir_override}"
  else
    if [[ -n "${ESP_IDF_DIR:-}" ]]; then
      esp_idf_dir="${ESP_IDF_DIR}"
    elif [[ -n "${IDF_PATH:-}" ]]; then
      esp_idf_dir="${IDF_PATH}"
    else
      esp_idf_dir="${HOME}/esp/esp-idf"
    fi
  fi

  if [[ ! -f "${esp_idf_dir}/export.sh" ]]; then
    die "ESP-IDF export.sh not found at ${esp_idf_dir}/export.sh"
  fi

  # shellcheck source=/dev/null
  source "${esp_idf_dir}/export.sh"

  if command -v idf.py >/dev/null 2>&1; then
    :
  else
    die "idf.py not found in PATH after sourcing ESP-IDF"
  fi

  if command -v esptool.py >/dev/null 2>&1; then
    :
  else
    die "esptool.py not found in PATH after sourcing ESP-IDF"
  fi
}

auto_port() {
  local p=""

  if [[ -d /dev/serial/by-id ]]; then
    for p in /dev/serial/by-id/*; do
      if [[ -e "$p" ]]; then
        printf "%s" "$p"
        return 0
      fi
    done
  fi

  for p in /dev/ttyACM*; do
    if [[ -e "$p" ]]; then
      printf "%s" "$p"
      return 0
    fi
  done

  for p in /dev/ttyUSB*; do
    if [[ -e "$p" ]]; then
      printf "%s" "$p"
      return 0
    fi
  done

  return 1
}

validate_port() {
  local port="$1"

  if [[ -n "${port}" ]]; then
    if [[ -e "${port}" ]]; then
      :
    else
      die "Port not found: ${port}"
    fi
  else
    die "Port is empty"
  fi
}

run_erase_flash() {
  local port="$1"
  local baud="$2"

  printf "+ esptool.py --chip auto --port %s --baud %s erase_flash\n" "${port}" "${baud}"
  esptool.py --chip auto --port "${port}" --baud "${baud}" erase_flash
}

run_flashimage() {
  local port="$1"
  shift
  local args=("$@")
  local rc=0

  if [[ -f "./build/flashimage.sh" ]]; then
    :
  else
    die "Missing ./build/flashimage.sh. Build + mkimage first."
  fi

  # Try the common form first: flashimage.sh supports -p on many setups.
  set +e
  printf "+ bash ./build/flashimage.sh -p %s" "${port}"
  if [[ "${#args[@]}" -gt 0 ]]; then
    printf " %s" "${args[*]}"
  fi
  printf "\n"
  bash ./build/flashimage.sh -p "${port}" "${args[@]}"
  rc="$?"
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    return 0
  fi

  # Fallback: some variants don't take -p, but will respect ESPPORT.
  export ESPPORT="${port}"
  printf "+ ESPPORT=%s bash ./build/flashimage.sh" "${ESPPORT}"
  if [[ "${#args[@]}" -gt 0 ]]; then
    printf " %s" "${args[*]}"
  fi
  printf "\n"
  bash ./build/flashimage.sh "${args[@]}"
}

ATOMVM_REPO=""
ESP_IDF_DIR_OVERRIDE=""
PORT=""
ERASE_FLASH="0"
BAUD="921600"
FLASHIMAGE_ARGS=()

while [[ $# -gt 0 ]]; do
  if [[ "$1" = "--atomvm-repo" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      die "--atomvm-repo requires a value"
    fi
    ATOMVM_REPO="$1"
    shift
  elif [[ "$1" = "--idf-dir" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      die "--idf-dir requires a value"
    fi
    ESP_IDF_DIR_OVERRIDE="$1"
    shift
  elif [[ "$1" = "--port" ]] || [[ "$1" = "-p" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      die "--port requires a value"
    fi
    PORT="$1"
    shift
  elif [[ "$1" = "--erase-flash" ]]; then
    ERASE_FLASH="1"
    shift
  elif [[ "$1" = "--baud" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      die "--baud requires a value"
    fi
    BAUD="$1"
    shift
  elif [[ "$1" = "--help" ]] || [[ "$1" = "-h" ]]; then
    usage
    exit 0
  elif [[ "$1" = "--" ]]; then
    shift
    while [[ $# -gt 0 ]]; do
      FLASHIMAGE_ARGS+=("$1")
      shift
    done
  else
    die "Unknown arg: $1 (use --help)"
  fi
done

if [[ -z "${ATOMVM_REPO}" ]]; then
  usage
  exit 1
fi

ESP32_DIR=""
if ESP32_DIR="$(resolve_esp32_dir "${ATOMVM_REPO}")"; then
  :
else
  die "ESP32 dir not found under ${ATOMVM_REPO} (expected src/platforms/esp32 or AtomVM/src/platforms/esp32)"
fi

source_esp_idf "${ESP_IDF_DIR_OVERRIDE}"

if [[ -z "${PORT}" ]]; then
  if PORT="$(auto_port)"; then
    :
  else
    die "Could not auto-detect a serial port. Pass --port (e.g. /dev/ttyACM0)."
  fi
fi

validate_port "${PORT}"

cd "${ESP32_DIR}"

if [[ "${ERASE_FLASH}" = "1" ]]; then
  run_erase_flash "${PORT}" "${BAUD}"
fi

run_flashimage "${PORT}" "${FLASHIMAGE_ARGS[@]}"
