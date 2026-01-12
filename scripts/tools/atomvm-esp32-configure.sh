#!/usr/bin/env bash
set -euo pipefail

usage() {
  local script_name
  script_name="$(basename "$0")"

  cat <<EOF
Usage:
  ${script_name} --atomvm-repo PATH [OPTIONS] [-- IDF_GLOBAL_ARGS...]

Description:
  Source ESP-IDF, cd into AtomVM ESP32 platform dir, then run one or more
  configure actions (set-target / clean / fullclean / menuconfig).

Required:
  --atomvm-repo PATH

Options:
  --idf-dir PATH          ESP-IDF directory (contains export.sh)

Actions (can be combined; they run in this order):
  --set-target TARGET     Run: idf.py set-target TARGET
  --fullclean             Run: idf.py fullclean
  --clean                 Run: idf.py clean
  --no-menuconfig         Do not run menuconfig at the end

Other:
  -h, --help              Show help

Interactive mode:
  If you provide no action flags, an interactive prompt will ask what to run.

IDF_GLOBAL_ARGS:
  Anything after "--" is passed as global args to each idf.py invocation.

Examples:
  ${script_name} --atomvm-repo ~/atomvm
  ${script_name} --atomvm-repo ~/atomvm --set-target esp32s3 --fullclean
  ${script_name} --atomvm-repo ~/atomvm --clean -- --verbose
EOF
}

die() {
  printf "✖ %s\n" "$*" >&2
  exit 1
}

is_tty() {
  if [[ -t 0 ]]; then
    return 0
  else
    return 1
  fi
}

ask_yes_no() {
  # args: prompt default(y/n)
  local prompt="$1"
  local default_answer="$2"
  local answer=""

  while true; do
    if [[ "${default_answer}" = "y" ]]; then
      printf "%s [Y/n]: " "${prompt}"
    else
      printf "%s [y/N]: " "${prompt}"
    fi

    read -r answer

    if [[ -z "${answer}" ]]; then
      if [[ "${default_answer}" = "y" ]]; then
        return 0
      else
        return 1
      fi
    fi

    if [[ "${answer}" = "y" ]] || [[ "${answer}" = "Y" ]]; then
      return 0
    elif [[ "${answer}" = "n" ]] || [[ "${answer}" = "N" ]]; then
      return 1
    else
      printf "Please answer y or n.\n"
    fi
  done
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

  if ! command -v idf.py >/dev/null 2>&1; then
    die "idf.py not found in PATH after sourcing ESP-IDF"
  fi
}

interactive_wizard() {
  # mutates globals: TARGET, DO_FULLCLEAN, DO_CLEAN, DO_MENUCONFIG
  printf "\nInteractive configure\n\n"

  if ask_yes_no "Set target?" "n"; then
    printf "Target (e.g. esp32, esp32s3): "
    read -r TARGET
    if [[ -z "${TARGET}" ]]; then
      die "Target was empty"
    fi
  fi

  if ask_yes_no "Run fullclean?" "n"; then
    DO_FULLCLEAN="1"
  else
    if ask_yes_no "Run clean?" "n"; then
      DO_CLEAN="1"
    fi
  fi

  if ask_yes_no "Open menuconfig?" "y"; then
    DO_MENUCONFIG="1"
  else
    DO_MENUCONFIG="0"
  fi
}

# ------------------------
# Parse args
# ------------------------
ATOMVM_REPO=""
ESP_IDF_DIR_OVERRIDE=""

TARGET=""
DO_CLEAN="0"
DO_FULLCLEAN="0"
DO_MENUCONFIG="1"

ACTION_FLAG_SEEN="0"

EXTRA_ARGS=()

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
  elif [[ "$1" = "--set-target" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      die "--set-target requires a value"
    fi
    TARGET="$1"
    ACTION_FLAG_SEEN="1"
    shift
  elif [[ "$1" = "--fullclean" ]]; then
    DO_FULLCLEAN="1"
    ACTION_FLAG_SEEN="1"
    shift
  elif [[ "$1" = "--clean" ]]; then
    DO_CLEAN="1"
    ACTION_FLAG_SEEN="1"
    shift
  elif [[ "$1" = "--no-menuconfig" ]]; then
    DO_MENUCONFIG="0"
    ACTION_FLAG_SEEN="1"
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

source_esp_idf "${ESP_IDF_DIR_OVERRIDE}"

cd "${ESP32_DIR}"

# If no action flags were given, ask interactively
if [[ "${ACTION_FLAG_SEEN}" = "0" ]]; then
  if is_tty; then
    interactive_wizard
  else
    die "No action flags provided and stdin is not a TTY. Provide flags such as --clean or --set-target."
  fi
fi

# ------------------------
# Run actions in order
# ------------------------
if [[ -n "${TARGET}" ]]; then
  idf.py "${EXTRA_ARGS[@]}" set-target "${TARGET}"
fi

if [[ "${DO_FULLCLEAN}" = "1" ]]; then
  idf.py "${EXTRA_ARGS[@]}" fullclean
else
  if [[ "${DO_CLEAN}" = "1" ]]; then
    idf.py "${EXTRA_ARGS[@]}" clean
  fi
fi

if [[ "${DO_MENUCONFIG}" = "1" ]]; then
  exec idf.py "${EXTRA_ARGS[@]}" menuconfig
fi

printf "Done.\n"
