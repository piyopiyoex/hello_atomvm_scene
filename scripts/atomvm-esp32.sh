#!/usr/bin/env bash
set -Eeuo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

# Colors (disabled when not a TTY; respects NO_COLOR)
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""
  C_BOLD=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_CYAN=""
fi

usage() {
  local script_name
  script_name="$(basename "$0")"

  cat <<EOF
Usage:
  ${script_name} <command> [options] [-- IDF_GLOBAL_ARGS...]

Commands:
  doctor    Print resolved paths and basic checks (no changes)
  install   Clone/update deps (AtomVM + AtomGL), patch config, build + mkimage, erase + flash
  monitor   Attach serial monitor (idf.py monitor)

Options:
  --idf-dir PATH       ESP-IDF root (contains export.sh). Optional.
  --target TARGET      esp32 / esp32s3 / etc (default: esp32s3)
  --port PORT          Serial device (optional; auto-detect if omitted for install/monitor)
  --baud BAUD          Baud for erase_flash (default: 921600)
  --no-erase           Skip erase_flash during install
  -h, --help           Show help

ESP-IDF discovery (if --idf-dir not provided):
  Uses ESP_IDF_DIR, then IDF_PATH, else defaults to: \$HOME/esp/esp-idf

Notes:
  AtomVM is expected at: \$HOME/atomvm/AtomVM
  AtomGL is cloned under: AtomVM/src/platforms/esp32/components/atomgl
EOF
}

die() {
  printf "%b✖%b %s\n" "${C_RED}${C_BOLD}" "${C_RESET}" "$*" >&2
  exit 1
}

say() {
  local msg="$*"
  case "${msg}" in
  "✔"*)
    printf "%b%s%b\n" "${C_GREEN}" "${msg}" "${C_RESET}"
    ;;
  "Next:"*)
    printf "%b%s%b\n" "${C_YELLOW}" "${msg}" "${C_RESET}"
    ;;
  *)
    printf "%s\n" "${msg}"
    ;;
  esac
}

run() {
  printf "%b+%b %s\n" "${C_CYAN}${C_BOLD}" "${C_RESET}" "$*"
  "$@"
}

require_cmd() {
  local cmd="$1"
  if command -v "${cmd}" >/dev/null 2>&1; then
    :
  else
    die "Missing dependency: ${cmd}"
  fi
}

script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}

repo_root() {
  cd "$(script_dir)/.." && pwd
}

resolve_idf_dir() {
  local override="$1"

  if [ -n "${override}" ]; then
    printf "%s" "${override}"
    return 0
  fi

  if [ -n "${ESP_IDF_DIR:-}" ]; then
    printf "%s" "${ESP_IDF_DIR}"
    return 0
  fi

  if [ -n "${IDF_PATH:-}" ]; then
    printf "%s" "${IDF_PATH}"
    return 0
  fi

  printf "%s" "${HOME}/esp/esp-idf"
}

auto_port() {
  local p=""

  if [ -d /dev/serial/by-id ]; then
    for p in /dev/serial/by-id/*; do
      if [ -e "${p}" ]; then
        printf "%s" "${p}"
        return 0
      fi
    done
  fi

  for p in /dev/ttyACM*; do
    if [ -e "${p}" ]; then
      printf "%s" "${p}"
      return 0
    fi
  done

  for p in /dev/ttyUSB*; do
    if [ -e "${p}" ]; then
      printf "%s" "${p}"
      return 0
    fi
  done

  return 1
}

with_idf_env() {
  local idf_dir="$1"
  local workdir="$2"
  shift 2

  if [ -f "${idf_dir}/export.sh" ]; then
    :
  else
    die "ESP-IDF export.sh not found: ${idf_dir}/export.sh"
  fi

  (
    set -Eeuo pipefail
    # shellcheck source=/dev/null
    source "${idf_dir}/export.sh" >/dev/null 2>&1

    if command -v idf.py >/dev/null 2>&1; then
      :
    else
      die "idf.py not found in PATH after sourcing ESP-IDF"
    fi

    cd "${workdir}"
    "$@"
  )
}

# ------------------------
# Repo layout / deps
# ------------------------
ATOMVM_URL="https://github.com/atomvm/AtomVM.git"
ATOMVM_REF="main"

ATOMGL_URL="https://github.com/atomvm/atomgl.git"
ATOMGL_REF="main"

this_repo_root="$(repo_root)"

# Keep AtomVM checkout consistent across projects (case-sensitive on Linux)
atomvm_wrapper_dir="${HOME}/atomvm"
atomvm_dir="${atomvm_wrapper_dir}/AtomVM"

esp32_dir="${atomvm_dir}/src/platforms/esp32"
atomgl_dir="${esp32_dir}/components/atomgl"

ensure_repo_present() {
  local name="$1"
  local dir="$2"
  local url="$3"
  local ref="$4"

  if [ -d "${dir}/.git" ]; then
    return 0
  fi

  if [ -e "${dir}" ]; then
    die "${name} exists but is not a git repo: ${dir}"
  fi

  require_cmd git
  mkdir -p "$(dirname "${dir}")"

  say "Cloning ${name} into: ${dir}"
  if [ -n "${ref}" ]; then
    run git clone --filter=blob:none --depth 1 --branch "${ref}" "${url}" "${dir}"
  else
    run git clone --filter=blob:none --depth 1 "${url}" "${dir}"
  fi
}

patch_sdkconfig_defaults() {
  local path="${esp32_dir}/sdkconfig.defaults"

  if [ -f "${path}" ]; then
    :
  else
    die "sdkconfig.defaults not found: ${path}"
  fi

  local tag
  tag="$(basename "${this_repo_root}")"

  local begin="# --- BEGIN ${tag} defaults (managed) ---"
  local end="# --- END ${tag} defaults ---"

  local tmp=""
  tmp="$(mktemp)"

  # Remove the managed block if it already exists.
  if grep -qF "${begin}" "${path}"; then
    awk -v begin="${begin}" -v end="${end}" '
      $0 == begin { skipping=1; next }
      $0 == end   { skipping=0; next }
      skipping != 1 { print }
    ' "${path}" >"${tmp}"
  else
    cat "${path}" >"${tmp}"
  fi

  {
    printf "\n%s\n" "${begin}"
    cat <<'EOF'
CONFIG_LWIP_IPV6=y
CONFIG_PARTITION_TABLE_CUSTOM_FILENAME="partitions-elixir.csv"
EOF
    printf "%s\n" "${end}"
  } >>"${tmp}"

  run cp "${path}" "${path}.bak"
  run mv "${tmp}" "${path}"

  say "✔ patched: ${path}"
}

ensure_partitions_csv() {
  # If your workflow stores the CSV elsewhere, add that path here.
  local candidates=(
    "${this_repo_root}/partitions-elixir.csv"
    "${this_repo_root}/scripts/partitions-elixir.csv"
    "${atomvm_wrapper_dir}/partitions-elixir.csv"
  )

  local src=""
  local c=""
  for c in "${candidates[@]}"; do
    if [ -f "${c}" ]; then
      src="${c}"
      break
    fi
  done

  if [ -z "${src}" ]; then
    # If AtomVM already provides it, fine. Otherwise, this prevents a confusing build error later.
    if [ -f "${esp32_dir}/partitions-elixir.csv" ]; then
      return 0
    fi
    die "partitions-elixir.csv not found (looked in repo root/scripts/atomvm wrapper). Place it, or adjust ensure_partitions_csv()."
  fi

  run cp "${src}" "${esp32_dir}/partitions-elixir.csv"
  say "✔ ensured: ${esp32_dir}/partitions-elixir.csv"
}

build_boot_avm_if_needed() {
  local boot_avm="${atomvm_dir}/build/libs/esp32boot/elixir_esp32boot.avm"

  if [ -f "${boot_avm}" ]; then
    return 0
  fi

  require_cmd cmake

  say "Generating boot AVM (Generic UNIX build)"
  mkdir -p "${atomvm_dir}/build"

  (
    cd "${atomvm_dir}/build"
    run cmake ..
    run cmake --build .
  )

  if [ -f "${boot_avm}" ]; then
    :
  else
    die "boot AVM missing after build: ${boot_avm}"
  fi
}

build_and_mkimage() {
  local idf_dir="$1"
  local target="$2"
  shift 2
  local extra_args=("$@")

  local boot_avm="${atomvm_dir}/build/libs/esp32boot/elixir_esp32boot.avm"
  if [ -f "${boot_avm}" ]; then
    :
  else
    die "boot AVM not found: ${boot_avm} (run build_boot_avm_if_needed first)"
  fi

  with_idf_env "${idf_dir}" "${esp32_dir}" idf.py "${extra_args[@]}" set-target "${target}"
  with_idf_env "${idf_dir}" "${esp32_dir}" idf.py "${extra_args[@]}" reconfigure
  with_idf_env "${idf_dir}" "${esp32_dir}" idf.py "${extra_args[@]}" build

  if [ -f "${esp32_dir}/build/mkimage.sh" ]; then
    :
  else
    die "mkimage.sh not found: ${esp32_dir}/build/mkimage.sh"
  fi

  with_idf_env "${idf_dir}" "${esp32_dir}" bash "./build/mkimage.sh" --boot "${boot_avm}"
  say "✔ built images under: ${esp32_dir}/build"
}

erase_flash() {
  local idf_dir="$1"
  local port="$2"
  local baud="$3"

  with_idf_env "${idf_dir}" "${esp32_dir}" esptool.py --chip auto --port "${port}" --baud "${baud}" erase_flash
}

flash_image() {
  local idf_dir="$1"
  local port="$2"

  with_idf_env "${idf_dir}" "${esp32_dir}" bash -Eeuo pipefail -c '
    port="$1"

    if [ -f "./build/flashimage.sh" ]; then
      :
    else
      echo "✖ Missing ./build/flashimage.sh. Build + mkimage first." >&2
      exit 1
    fi

    set +e
    echo "+ bash ./build/flashimage.sh -p ${port}"
    bash ./build/flashimage.sh -p "${port}"
    rc="$?"
    set -e

    if [ "${rc}" -eq 0 ]; then
      exit 0
    fi

    export ESPPORT="${port}"
    echo "+ ESPPORT=${ESPPORT} bash ./build/flashimage.sh"
    bash ./build/flashimage.sh
  ' _ "${port}"

  say "✔ flashed image via flashimage.sh"
}

doctor_cmd() {
  local idf_dir="$1"
  local target="$2"
  local port_display="$3"

  say ""
  say "Paths"
  say "- repo_root:    ${this_repo_root}"
  say "- atomvm_dir:   ${atomvm_dir}"
  say "- esp32_dir:    ${esp32_dir}"
  say "- atomgl_dir:   ${atomgl_dir}"
  say "- idf_dir:      ${idf_dir}"
  say ""
  say "Config"
  say "- target:       ${target}"
  say "- port:         ${port_display}"
  say ""
  say "Checks"

  if [ -f "${idf_dir}/export.sh" ]; then
    say "- ESP-IDF:      export.sh found"
  else
    say "- ESP-IDF:      missing export.sh"
  fi

  if [ -d "${atomvm_dir}/.git" ]; then
    say "- AtomVM:       present"
  else
    say "- AtomVM:       missing (install will clone)"
  fi

  if [ -d "${atomgl_dir}/.git" ]; then
    say "- AtomGL:       present"
  else
    say "- AtomGL:       missing (install will clone)"
  fi

  if [ -n "${port_display}" ] && [ "${port_display}" != "(not set)" ]; then
    if [ -e "${port_display}" ]; then
      say "- Port:         ok"
    else
      say "- Port:         not found (${port_display})"
    fi
  fi

  say ""
}

install_cmd() {
  local idf_dir="$1"
  local target="$2"
  local port="$3"
  local baud="$4"
  local do_erase="$5"
  shift 5
  local extra_args=("$@")

  if [ -z "${port}" ]; then
    if port="$(auto_port)"; then
      say "✔ auto-detected port: ${port}"
    else
      die "Could not auto-detect a serial port. Pass --port (e.g. /dev/ttyACM0)."
    fi
  fi

  if [ -e "${port}" ]; then
    :
  else
    die "Serial port not found: ${port}"
  fi

  mkdir -p "${atomvm_wrapper_dir}"
  ensure_repo_present "AtomVM" "${atomvm_dir}" "${ATOMVM_URL}" "${ATOMVM_REF}"
  ensure_repo_present "AtomGL" "${atomgl_dir}" "${ATOMGL_URL}" "${ATOMGL_REF}"

  patch_sdkconfig_defaults
  ensure_partitions_csv
  build_boot_avm_if_needed
  build_and_mkimage "${idf_dir}" "${target}" "${extra_args[@]}"

  if [ "${do_erase}" = "1" ]; then
    say "Erasing flash"
    erase_flash "${idf_dir}" "${port}" "${baud}"
  fi

  say "Flashing image"
  flash_image "${idf_dir}" "${port}"

  say "✔ install complete"
  say "Next: run the Elixir app flash from this repo (mix atomvm.esp32.flash ...)"
}

monitor_cmd() {
  local idf_dir="$1"
  local port="$2"
  shift 2
  local extra_args=("$@")

  if [ -z "${port}" ]; then
    if port="$(auto_port)"; then
      say "✔ auto-detected port: ${port}"
    else
      die "Could not auto-detect a serial port. Pass --port (e.g. /dev/ttyACM0)."
    fi
  fi

  if [ -e "${port}" ]; then
    :
  else
    die "Serial port not found: ${port}"
  fi

  say "Starting serial monitor"
  with_idf_env "${idf_dir}" "${esp32_dir}" idf.py -p "${port}" monitor "${extra_args[@]}"
}

main() {
  local cmd="${1:-}"
  if [ -z "${cmd}" ]; then
    usage
    return 2
  fi

  if [ "${cmd}" = "-h" ] || [ "${cmd}" = "--help" ]; then
    usage
    return 0
  fi
  shift || true

  local idf_dir_override=""
  local target="esp32s3"
  local port=""
  local baud="921600"
  local do_erase="1"
  local extra_args=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
    --idf-dir)
      shift
      if [ "$#" -gt 0 ]; then
        idf_dir_override="$1"
        shift
      else
        die "--idf-dir requires a value"
      fi
      ;;
    --target)
      shift
      if [ "$#" -gt 0 ]; then
        target="$1"
        shift
      else
        die "--target requires a value"
      fi
      ;;
    --port | -p)
      shift
      if [ "$#" -gt 0 ]; then
        port="$1"
        shift
      else
        die "--port requires a value"
      fi
      ;;
    --baud)
      shift
      if [ "$#" -gt 0 ]; then
        baud="$1"
        shift
      else
        die "--baud requires a value"
      fi
      ;;
    --no-erase)
      do_erase="0"
      shift
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        extra_args+=("$1")
        shift
      done
      ;;
    -h | --help)
      usage
      return 0
      ;;
    *)
      die "Unknown option: $1 (use --help)"
      ;;
    esac
  done

  local idf_dir=""
  idf_dir="$(resolve_idf_dir "${idf_dir_override}")"

  local port_display="(not set)"
  if [ -n "${port}" ]; then
    port_display="${port}"
  fi

  case "${cmd}" in
  doctor)
    doctor_cmd "${idf_dir}" "${target}" "${port_display}"
    ;;
  install)
    install_cmd "${idf_dir}" "${target}" "${port}" "${baud}" "${do_erase}" "${extra_args[@]}"
    ;;
  monitor)
    monitor_cmd "${idf_dir}" "${port}" "${extra_args[@]}"
    ;;
  *)
    usage
    die "Unknown command: ${cmd}"
    ;;
  esac
}

main "$@"
