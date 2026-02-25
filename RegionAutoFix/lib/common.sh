# common.sh - timestamp, log, die, ensure_dirs, state helpers, list_snapshots, safe_realpath

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

epoch() {
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
