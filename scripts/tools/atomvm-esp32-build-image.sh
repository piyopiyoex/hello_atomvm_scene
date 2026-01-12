#!/usr/bin/env bash
set -euo pipefail

usage() {
  local script_name
  script_name="$(basename "$0")"

  cat <<EOF
Usage:
  ${script_name} --atomvm-repo PATH --target TARGET [OPTIONS] [-- IDF_GLOBAL_ARGS...]

Description:
  Source ESP-IDF, cd into AtomVM ESP32 platform dir, then:
    1) idf.py set-target <target>
    2) idf.py reconfigure
    3) idf.py build
    4) bash ./build/mkimage.sh --boot <boot.avm>

Required:
  --atomvm-repo PATH
  --target TARGET

Options:
  --idf-dir PATH          ESP-IDF directory (contains export.sh)
  --boot-avm PATH         Boot AVM path
                          (default: <atomvm_root>/build/libs/esp32boot/elixir_esp32boot.avm)
  -h, --help              Show help

IDF_GLOBAL_ARGS:
  Anything after "--" is passed as global args to each idf.py invocation.

Examples:
  ${script_name} --atomvm-repo ~/atomvm --target esp32s3
  ${script_name} --atomvm-repo ~/atomvm --target esp32 -- --verbose
EOF
}

die() {
  printf "✖ %s\n" "$*" >&2
  exit 1
}

resolve_atomvm_paths() {
  local repo="$1"
  local candidate=""

  candidate="${repo}/src/platforms/esp32"
  if [[ -d "${candidate}" ]]; then
    ATOMVM_ROOT="${repo}"
    ESP32_DIR="${candidate}"
    return 0
  fi

  candidate="${repo}/AtomVM/src/platforms/esp32"
  if [[ -d "${candidate}" ]]; then
    ATOMVM_ROOT="${repo}/AtomVM"
    ESP32_DIR="${candidate}"
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

  if ! command -v idf.py >/dev/null 2>&1; then
    die "idf.py not found in PATH after sourcing ESP-IDF"
  fi
}

ATOMVM_REPO=""
ESP_IDF_DIR_OVERRIDE=""
TARGET=""
BOOT_AVM_OVERRIDE=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  if [[ "$1" = "--atomvm-repo" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      die "--atomvm-repo requires a value"
    fi
    ATOMVM_REPO="$1"
    shift
  elif [[ "$1" = "--target" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      die "--target requires a value"
    fi
    TARGET="$1"
    shift
  elif [[ "$1" = "--idf-dir" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      die "--idf-dir requires a value"
    fi
    ESP_IDF_DIR_OVERRIDE="$1"
    shift
  elif [[ "$1" = "--boot-avm" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      die "--boot-avm requires a value"
    fi
    BOOT_AVM_OVERRIDE="$1"
    shift
  elif [[ "$1" = "--help" ]] || [[ "$1" = "-h" ]]; then
    usage
    exit 0
  elif [[ "$1" = "--" ]]; then
    shift
    while [[ $# -gt 0 ]]; do
      EXTRA_ARGS+=("$1")
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

if [[ -z "${TARGET}" ]]; then
  die "--target is required (e.g. --target esp32s3)"
fi

ATOMVM_ROOT=""
ESP32_DIR=""
if resolve_atomvm_paths "${ATOMVM_REPO}"; then
  :
else
  die "ESP32 dir not found under ${ATOMVM_REPO} (expected src/platforms/esp32 or AtomVM/src/platforms/esp32)"
fi

source_esp_idf "${ESP_IDF_DIR_OVERRIDE}"

BOOT_AVM_DEFAULT="${ATOMVM_ROOT}/build/libs/esp32boot/elixir_esp32boot.avm"
BOOT_AVM="${BOOT_AVM_DEFAULT}"

if [[ -n "${BOOT_AVM_OVERRIDE}" ]]; then
  BOOT_AVM="${BOOT_AVM_OVERRIDE}"
fi

if [[ -f "${BOOT_AVM}" ]]; then
  :
else
  die "Boot AVM not found: ${BOOT_AVM}. Build the core libs first (Generic UNIX) to generate it, or pass --boot-avm PATH."
fi

cd "${ESP32_DIR}"

idf.py "${EXTRA_ARGS[@]}" set-target "${TARGET}"
idf.py "${EXTRA_ARGS[@]}" reconfigure
idf.py "${EXTRA_ARGS[@]}" build

if [[ -f "./build/mkimage.sh" ]]; then
  :
else
  die "mkimage.sh not found at ${ESP32_DIR}/build/mkimage.sh"
fi

bash "./build/mkimage.sh" --boot "${BOOT_AVM}"

printf "Done. Check images under: %s/build\n" "${ESP32_DIR}"

