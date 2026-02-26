# common.sh - timestamp, log, die, ensure_dirs, state helpers, list_snapshots, safe_realpath, startup helpers

REGIONAUTOFIX_VERSION="1.0.1"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

epoch() {
  date '+%s'
}

now_epoch() {
  date '+%s'
}

# Call from a process that has already redirected stdout/stderr to log file
log() {
  echo "[$(timestamp)] $*"
}

die() {
  log "FATAL: $*"
  exit 1
}

# Ensure RegionAutoFix base dir and standard subdirs exist (BASE set by run.sh)
ensure_dirs() {
  local base="${1:-$BASE}"
  mkdir -p "$base/Saves" "$base/Logs" "$base/State/quarantine" "$base/lib"
}

# Read state value from State/<name>; default if missing
read_state() {
  local name="$1"
  local default="${2:-}"
  local path="$BASE/State/$name"
  if [[ -f "$path" ]]; then
    cat "$path"
  else
    echo "$default"
  fi
}

# Write state value to State/<name>
write_state() {
  local name="$1"
  local value="$2"
  local path="$BASE/State/$name"
  mkdir -p "$(dirname "$path")"
  printf '%s' "$value" > "$path"
}

# List snapshot dirs under backup, newest first (by name = timestamp order)
list_snapshots() {
  local backup_base="${1:-$backup}"
  if [[ ! -d "$backup_base" ]]; then
    return 0
  fi
  for d in "$backup_base"/snap_*; do
    [[ -d "$d" ]] || continue
    echo "$d"
  done | sort -r
}

# Safe realpath: resolve path and ensure it is under the given prefix (no traversal)
# Usage: safe_realpath <path> <required_prefix>
# Returns 0 if path resolves and is under prefix; prints path. Else returns 1.
safe_realpath() {
  local path="$1"
  local prefix="$2"
  local resolved
  if ! resolved=$(realpath -m -- "$path" 2>/dev/null); then
    # Fallback when realpath not available (e.g. busybox)
    resolved=$(cd -P "$(dirname "$path")" 2>/dev/null && echo "$(pwd)/$(basename "$path")") || true
    if [[ -z "$resolved" ]]; then
      return 1
    fi
  fi
  local prefix_norm
  prefix_norm=$(realpath -m -- "$prefix" 2>/dev/null) || prefix_norm=$(cd -P "$prefix" 2>/dev/null && pwd) || return 1
  if [[ "$resolved" == "$prefix_norm"/* || "$resolved" == "$prefix_norm" ]]; then
    echo "$resolved"
    return 0
  fi
  return 1
}

# Validate region filename: must end with .7rg, no slashes, match r.*.7rg
# Region files are like r.-3.5.7rg (r.<x>.<z>.7rg)
validate_region_filename() {
  local name="$1"
  [[ "$name" == */.7rg* ]] && return 1
  [[ "$name" == */* ]] && return 1
  [[ "$name" == *.7rg ]] || return 1
  [[ "$name" =~ ^r\..*\.7rg$ ]] || return 1
  return 0
}

# Resolve region_dir from worldsave (must be set by caller)
# region_dir="$worldsave/Region"

# Sanitize path for display: show last 2 segments or basename, replace $HOME with ~
sanitize_path() {
  local path="${1:-}"
  [[ -z "$path" ]] && echo "(not set)" && return
  local home="${HOME:-}"
  if [[ -n "$home" && "$path" == "$home"/* ]]; then
    path="~/${path#$home/}"
  fi
  local base1 base2
  base1=$(basename "$path")
  base2=$(basename "$(dirname "$path")")
  if [[ "$base1" == "$base2" ]]; then
    echo "$base1"
  else
    echo "$base2/$base1"
  fi
}

# Derive world/save name from worldsave path (e.g. .../Saves/WorldName/WorldName -> WorldName)
get_world_name() {
  local ws="${1:-$worldsave}"
  [[ -z "$ws" ]] && echo "(not set)" && return
  local name
  name=$(basename "$ws")
  local parent
  parent=$(dirname "$ws")
  if [[ -n "$parent" && "$(basename "$parent")" == "$name" ]]; then
    echo "$name"
  else
    echo "$name"
  fi
}

# Safe git commit: print short HEAD if git and repo available, else "unknown"
get_git_commit() {
  local repo_root="${1:-$BASE}"
  if ! command -v git &>/dev/null; then
    echo "unknown"
    return
  fi
  local try
  for try in "$repo_root" "$(dirname "$repo_root")"; do
    [[ -z "$try" ]] && continue
    if git -C "$try" rev-parse --is-inside-work-tree &>/dev/null; then
      git -C "$try" rev-parse --short HEAD 2>/dev/null || echo "unknown"
      return
    fi
  done
  echo "unknown"
}
