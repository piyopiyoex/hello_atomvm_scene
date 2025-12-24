#!/usr/bin/env bash
set -Eeuo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
  exec /usr/bin/env bash "$0" "$@"
fi

echo_heading() { echo -e "\n\033[34m$1\033[0m"; }
ok() { echo -e " \033[32m✔ $1\033[0m"; }
warn() { echo -e " \033[33m▲ $1\033[0m"; }
fail() {
  echo -e " \033[31m✖ $1\033[0m" >&2
  exit 1
}

run() {
  echo " + $*"
  "$@"
}

require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Missing dependency: $1"; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

ESP32_DIR() { echo "${ATOMVM_DIR}/src/platforms/esp32"; }
ATOMGL_DIR() { echo "$(ESP32_DIR)/components/atomgl"; }
SDKCONFIG_DEFAULTS() { echo "$(ESP32_DIR)/sdkconfig.defaults"; }
BOOT_AVM() { echo "${ATOMVM_DIR}/build/libs/esp32boot/elixir_esp32boot.avm"; }

SDKCONFIG_DEFAULTS_REL="src/platforms/esp32/sdkconfig.defaults"

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
    *) fail "Unknown option: $1" ;;
    esac
  done

  if [ -z "$CMD" ]; then
    usage
    exit 2
  fi
}

idf_run() {
  local workdir="$1"
  shift

  [ -f "${IDF_PATH}/export.sh" ] || fail "ESP-IDF export.sh not found: ${IDF_PATH}/export.sh"

  # shellcheck disable=SC1090
  (
    set -Eeuo pipefail
    source "${IDF_PATH}/export.sh" >/dev/null 2>&1
    cd "$workdir"
    "$@"
  )
}

preflight_basic() {
  require_cmd git
  require_cmd bash
  require_cmd cmake

  [ -f "${IDF_PATH}/export.sh" ] || fail "ESP-IDF export.sh not found: ${IDF_PATH}/export.sh"

  echo_heading "Preflight checks"
  idf_run "$(ESP32_DIR)" idf.py --version || fail "idf.py is not available (ESP-IDF not installed for ${TARGET}?)"
  idf_run "$(ESP32_DIR)" esptool.py version || fail "esptool.py is not available (ESP-IDF env issue?)"
  ok "Preflight complete."
}

git_merge_guard() {
  local dir="$1"
  # Avoid running in a half-resolved state (stash/checkout/reset will get messy).
  if [ -f "${dir}/.git/MERGE_HEAD" ] || [ -d "${dir}/.git/rebase-apply" ] || [ -d "${dir}/.git/rebase-merge" ]; then
    fail "Repo is mid-merge/rebase: ${dir}. Resolve it first (or reset) before running this script."
  fi
}

is_sha() { [[ "${1:-}" =~ ^[0-9a-fA-F]{7,40}$ ]]; }
is_tag() { git -C "$1" show-ref --verify --quiet "refs/tags/$2" 2>/dev/null; }

reset_file_if_dirty() {
  local dir="$1" relpath="$2"

  [ -f "${dir}/${relpath}" ] || return 0

  if git -C "$dir" ls-files -u -- "$relpath" | grep -q . 2>/dev/null; then
    warn "Resetting ${relpath} (was in conflict)."
    run git -C "$dir" restore --staged --worktree -- "$relpath" || true
    run git -C "$dir" checkout -- "$relpath" || true
    return 0
  fi

  if ! git -C "$dir" diff --quiet -- "$relpath" 2>/dev/null || ! git -C "$dir" diff --cached --quiet -- "$relpath" 2>/dev/null; then
    warn "Resetting ${relpath} to avoid conflicts while updating."
    run git -C "$dir" restore --staged --worktree -- "$relpath" || true
    run git -C "$dir" checkout -- "$relpath" || true
  fi
}

git_fetch_safely() {
  local dir="$1" ref="$2"

  # Quietly try tag fetch first; if not a tag, proceed without noise.
  if ! is_sha "$ref"; then
    if git -C "$dir" fetch --filter=blob:none --depth 1 origin "tag" "$ref" >/dev/null 2>&1; then
      ok "Fetched tag: $ref"
      return 0
    fi
  fi

  if is_sha "$ref"; then
    # Remote servers do not reliably support fetching arbitrary SHAs directly.
    run git -C "$dir" fetch --filter=blob:none origin
  else
    run git -C "$dir" fetch --filter=blob:none --depth 1 origin "$ref"
  fi
}

git_checkout_ref() {
  local dir="$1" ref="$2"

  if is_sha "$ref"; then
    if git -C "$dir" cat-file -e "${ref}^{commit}" 2>/dev/null; then
      run git -C "$dir" -c advice.detachedHead=false checkout "$ref"
      return 0
    fi
    fail "Commit not found locally after fetch: ${ref}. Use a full SHA or a branch/tag."
  fi

  if is_tag "$dir" "$ref"; then
    run git -C "$dir" -c advice.detachedHead=false checkout "$ref"
    return 0
  fi

  run git -C "$dir" checkout -B "$ref" "origin/$ref"
  run git -C "$dir" reset --hard "origin/$ref"
}

ensure_repo() {
  local name="$1" dir="$2" url="$3" ref="$4"

  mkdir -p "$(dirname "$dir")"

  # Submodules may have ".git" as a file, not a directory.
  if [ -e "${dir}/.git" ]; then
    run git -C "$dir" remote set-url origin "$url"
  elif [ -e "$dir" ]; then
    warn "${dir} exists but is not a git repo. Backing it up."
    mv "$dir" "${dir}.bak.$(date +%s)"
    run git clone --filter=blob:none --depth 1 "$url" "$dir"
  else
    run git clone --filter=blob:none --depth 1 "$url" "$dir"
  fi

  git_merge_guard "$dir"

  echo " Syncing ${name} at ${ref}"

  # We patch AtomVM's sdkconfig.defaults later. Reset it here so updating main never conflicts.
  if [ "$name" = "AtomVM" ] && ! is_sha "$ref" && ! is_tag "$dir" "$ref"; then
    reset_file_if_dirty "$dir" "$SDKCONFIG_DEFAULTS_REL"
  fi

  git_fetch_safely "$dir" "$ref"
  git_checkout_ref "$dir" "$ref"
}

patch_sdkconfig_defaults() {
  local path
  path="$(SDKCONFIG_DEFAULTS)"
  [ -f "$path" ] || fail "Expected sdkconfig.defaults at: $path"

  local want_ipv6='CONFIG_LWIP_IPV6=y'
  local want_partitions='CONFIG_PARTITION_TABLE_CUSTOM_FILENAME="partitions-elixir.csv"'
  local missing=0

  grep -qF "$want_ipv6" "$path" || missing=1
  grep -qF "$want_partitions" "$path" || missing=1

  if [ "$missing" -eq 0 ]; then
    ok "sdkconfig.defaults already contains required lines."
    return
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

resolve_port() {
  if [ -n "$PORT" ]; then
    [ -e "$PORT" ] || fail "Port not found: $PORT"
    ok "Using port: $PORT"
    return
  fi

  local ports=()
  shopt -s nullglob
  ports=(/dev/ttyACM* /dev/ttyUSB*)
  shopt -u nullglob

  if [ "${#ports[@]}" -eq 0 ]; then
    fail "Could not auto-detect a serial port. Pass --port (e.g. /dev/ttyACM0)."
  fi

  mapfile -t ports < <(printf "%s\n" "${ports[@]}" | sort -u)

  if [ "${#ports[@]}" -eq 1 ]; then
    PORT="${ports[0]}"
    ok "Auto-detected port: $PORT"
    return
  fi

  echo_heading "Multiple serial ports detected"
  printf "  %s\n" "${ports[@]}"
  fail "Please specify --port."
}

sync_cmd() {
  echo_heading "Syncing repositories"
  ensure_repo "AtomVM" "$ATOMVM_DIR" "$ATOMVM_URL" "$ATOMVM_REF"
  ensure_repo "AtomGL" "$(ATOMGL_DIR)" "$ATOMGL_URL" "$ATOMGL_REF"
  patch_sdkconfig_defaults
  ok "Repos ready."
}

core_cmd() {
  echo_heading "Building core libraries (Generic UNIX)"
  mkdir -p "${ATOMVM_DIR}/build"
  (
    cd "${ATOMVM_DIR}/build"
    run cmake ..
    run cmake --build .
  )

  [ -f "$(BOOT_AVM)" ] || fail "Missing: $(BOOT_AVM)"
  ok "Generated: $(BOOT_AVM)"
}

build_cmd() {
  sync_cmd
  preflight_basic

  echo_heading "Building AtomVM for ESP32 (${TARGET})"
  idf_run "$(ESP32_DIR)" idf.py set-target "$TARGET"
  idf_run "$(ESP32_DIR)" idf.py reconfigure
  idf_run "$(ESP32_DIR)" idf.py build
  ok "ESP32 build complete."
}

mkimage_cmd() {
  sync_cmd
  preflight_basic

  [ -f "$(BOOT_AVM)" ] || core_cmd

  echo_heading "Generating release image (mkimage)"
  idf_run "$(ESP32_DIR)" bash "./build/mkimage.sh" --boot "$(BOOT_AVM)"

  local img
  img="$(ls -t "$(ESP32_DIR)"/build/*.img 2>/dev/null | head -n1 || true)"
  [ -n "$img" ] || fail "No .img found under $(ESP32_DIR)/build."
  ok "Image ready: $img"
}

erase_cmd() {
  sync_cmd
  preflight_basic
  resolve_port

  echo_heading "Erasing flash"
  idf_run "$(ESP32_DIR)" esptool.py --chip auto --port "$PORT" --baud "$BAUD" erase_flash
  ok "Erase complete."
}

flash_cmd() {
  sync_cmd
  preflight_basic
  resolve_port

  echo_heading "Flashing image"
  idf_run "$(ESP32_DIR)" bash "./build/flashimage.sh" -p "$PORT"
  ok "Flash complete."
}

clean_cmd() {
  echo_heading "Cleaning build artifacts"

  local esp32_build
  esp32_build="$(ESP32_DIR)/build"

  if [ -d "$esp32_build" ]; then
    run rm -rf "$esp32_build"
    ok "Removed: $esp32_build"
  else
    ok "Nothing to remove: $esp32_build"
  fi

  if [ "$CLEAN_ALL" -eq 1 ]; then
    local generic_build
    generic_build="${ATOMVM_DIR}/build"

    if [ -d "$generic_build" ]; then
      run rm -rf "$generic_build"
      ok "Removed: $generic_build"
    else
      ok "Nothing to remove: $generic_build"
    fi
  else
    ok "Kept: ${ATOMVM_DIR}/build (use 'clean --all' to remove)"
  fi
}

all_cmd() {
  sync_cmd
  core_cmd
  build_cmd
  mkimage_cmd
  erase_cmd
  flash_cmd
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
