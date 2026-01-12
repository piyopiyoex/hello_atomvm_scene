#!/usr/bin/env bash
set -euo pipefail

usage() {
  local script_name
  script_name="$(basename "$0")"

  cat <<EOF
Usage:
  ${script_name} --atomvm-repo PATH [OPTIONS]

Description:
  Build AtomVM core libraries (Generic UNIX) using CMake, and verify the boot AVM:
    <atomvm_root>/build/libs/esp32boot/elixir_esp32boot.avm

Required:
  --atomvm-repo PATH      AtomVM repo root (or wrapper repo containing AtomVM/)

Options:
  --build-dir PATH        Build directory (default: <atomvm_root>/build)
  --clean                Remove build-dir before building
  -h, --help              Show help

Examples:
  ${script_name} --atomvm-repo ~/atomvm/AtomVM
  ${script_name} --atomvm-repo ~/atomvm --clean
EOF
}

die() {
  printf "✖ %s\n" "$*" >&2
  exit 1
}

resolve_atomvm_root() {
  local repo="$1"
  local candidate=""

  candidate="${repo}/CMakeLists.txt"
  if [[ -f "${candidate}" ]]; then
    printf "%s" "${repo}"
    return 0
  fi

  candidate="${repo}/AtomVM/CMakeLists.txt"
  if [[ -f "${candidate}" ]]; then
    printf "%s" "${repo}/AtomVM"
    return 0
  fi

  return 1
}

require_cmd() {
  local cmd="$1"
  if command -v "${cmd}" >/dev/null 2>&1; then
    :
  else
    die "Missing dependency: ${cmd}"
  fi
}

ATOMVM_REPO=""
BUILD_DIR_OVERRIDE=""
DO_CLEAN="0"

while [[ $# -gt 0 ]]; do
  if [[ "$1" = "--atomvm-repo" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      die "--atomvm-repo requires a value"
    fi
    ATOMVM_REPO="$1"
    shift
  elif [[ "$1" = "--build-dir" ]]; then
    shift
    if [[ $# -eq 0 ]]; then
      die "--build-dir requires a value"
    fi
    BUILD_DIR_OVERRIDE="$1"
    shift
  elif [[ "$1" = "--clean" ]]; then
    DO_CLEAN="1"
    shift
  elif [[ "$1" = "--help" ]] || [[ "$1" = "-h" ]]; then
    usage
    exit 0
  else
    die "Unknown arg: $1 (use --help)"
  fi
done

if [[ -z "${ATOMVM_REPO}" ]]; then
  usage
  exit 1
fi

require_cmd cmake

ATOMVM_ROOT=""
if ATOMVM_ROOT="$(resolve_atomvm_root "${ATOMVM_REPO}")"; then
  :
else
  die "AtomVM root not found under ${ATOMVM_REPO} (expected CMakeLists.txt at repo root or AtomVM/)"
fi

BUILD_DIR="${ATOMVM_ROOT}/build"
if [[ -n "${BUILD_DIR_OVERRIDE}" ]]; then
  BUILD_DIR="${BUILD_DIR_OVERRIDE}"
fi

BOOT_AVM="${ATOMVM_ROOT}/build/libs/esp32boot/elixir_esp32boot.avm"

if [[ "${DO_CLEAN}" = "1" ]]; then
  if [[ -d "${BUILD_DIR}" ]]; then
    rm -rf "${BUILD_DIR}"
  fi
fi

mkdir -p "${BUILD_DIR}"

(
  cd "${BUILD_DIR}"
  cmake ..
  cmake --build .
)

if [[ -f "${BOOT_AVM}" ]]; then
  printf "✔ Generated: %s\n" "${BOOT_AVM}"
else
  die "Boot AVM not found after build: ${BOOT_AVM}"
fi
