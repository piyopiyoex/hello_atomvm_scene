#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") --atomvm-repo PATH [--port PORT] [--idf-dir PATH] [-- ARGS...]

Runs: idf.py -p PORT monitor (in AtomVM ESP32 platform dir, after sourcing ESP-IDF)

Required:
  --atomvm-repo PATH   AtomVM repo root (or wrapper repo containing AtomVM/)

Optional:
  --port PORT          Serial port (auto-detect if omitted)
  --idf-dir PATH       ESP-IDF dir (contains export.sh)
  -h, --help           Show help
EOF
}

die() {
  printf "✖ %s\n" "$*" >&2
  exit 1
}

auto_port() {
  local p

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

  printf "%s" "/dev/ttyACM0"
}

resolve_esp32_dir() {
  local repo="$1"
  local candidate

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

ATOMVM_REPO=""
PORT=""
ESP_IDF_DIR_OVERRIDE=""
EXTRA_ARGS=()

while [[ $# -gt 0 ]]; do
  if [[ "$1" = "--atomvm-repo" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      die "--atomvm-repo requires a value"
    fi
    ATOMVM_REPO="$1"
    shift
  elif [[ "$1" = "--port" ]] || [[ "$1" = "-p" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      die "--port requires a value"
    fi
    PORT="$1"
    shift
  elif [[ "$1" = "--idf-dir" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      die "--idf-dir requires a value"
    fi
    ESP_IDF_DIR_OVERRIDE="$1"
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

ESP32_DIR=""
if ESP32_DIR="$(resolve_esp32_dir "${ATOMVM_REPO}")"; then
  :
else
  die "ESP32 dir not found under ${ATOMVM_REPO} (expected src/platforms/esp32 or AtomVM/src/platforms/esp32)"
fi

if [[ -n "${ESP_IDF_DIR_OVERRIDE}" ]]; then
  ESP_IDF_DIR="${ESP_IDF_DIR_OVERRIDE}"
else
  if [[ -n "${ESP_IDF_DIR:-}" ]]; then
    :
  elif [[ -n "${IDF_PATH:-}" ]]; then
    ESP_IDF_DIR="${IDF_PATH}"
  else
    ESP_IDF_DIR="${HOME}/esp/esp-idf"
  fi
fi

if [[ ! -f "${ESP_IDF_DIR}/export.sh" ]]; then
  die "ESP-IDF export.sh not found at ${ESP_IDF_DIR}/export.sh"
fi

# shellcheck source=/dev/null
source "${ESP_IDF_DIR}/export.sh"

if [[ -z "${PORT}" ]]; then
  PORT="$(auto_port)"
fi

cd "${ESP32_DIR}"
exec idf.py -p "${PORT}" monitor "${EXTRA_ARGS[@]}"
