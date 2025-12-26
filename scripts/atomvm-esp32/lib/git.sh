git_merge_guard() {
  local dir="$1"
  if [ -f "${dir}/.git/MERGE_HEAD" ] || [ -d "${dir}/.git/rebase-apply" ] || [ -d "${dir}/.git/rebase-merge" ]; then
    fail "Repo is mid-merge/rebase: ${dir}. Resolve it first (or reset) before running this script."
  fi
}

is_sha() { [[ "${1:-}" =~ ^[0-9a-fA-F]{7,40}$ ]]; }

is_tag() {
  git -C "$1" show-ref --verify --quiet "refs/tags/$2" 2>/dev/null
}

reset_file_if_dirty() {
  local dir="$1" relpath="$2"

  if [ ! -f "${dir}/${relpath}" ]; then
    return 0
  fi

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

  if ! is_sha "$ref"; then
    if git -C "$dir" fetch --filter=blob:none --depth 1 origin "tag" "$ref" >/dev/null 2>&1; then
      ok "Fetched tag: $ref"
      return 0
    fi
  fi

  if is_sha "$ref"; then
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

  if [ "$name" = "AtomVM" ] && ! is_sha "$ref" && ! is_tag "$dir" "$ref"; then
    reset_file_if_dirty "$dir" "$SDKCONFIG_DEFAULTS_REL"
  fi

  git_fetch_safely "$dir" "$ref"
  git_checkout_ref "$dir" "$ref"
}
