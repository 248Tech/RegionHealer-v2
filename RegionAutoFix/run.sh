#!/usr/bin/env bash
# RegionAutoFix - 7DTD region corruption auto-fix (log monitor, backups, restore, Discord, telnet)

set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
cd "$BASE"

# Load config
if [[ ! -f "$BASE/config.env" ]]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] FATAL: config.env not found"
  exit 1
fi
source "$BASE/config.env"

# Derived path
region_dir="${worldsave}/Region"

# Source libs (order matters: common first, then discord/telnet, then restore/backups/monitor)
source "$BASE/lib/common.sh"
source "$BASE/lib/discord.sh"
source "$BASE/lib/telnet.sh"
source "$BASE/lib/restore.sh"
source "$BASE/lib/backups.sh"
source "$BASE/lib/monitor.sh"

# --- Validation ---
validate_and_init() {
  if [[ -z "${logfile:-}" ]]; then
    die "logfile not set in config.env"
  fi
  local log_parent
  log_parent=$(dirname "$logfile")
  if [[ ! -d "$log_parent" ]]; then
    die "logfile parent dir does not exist: $log_parent"
  fi
  if [[ -z "${worldsave:-}" ]]; then
    die "worldsave not set in config.env"
  fi
  if [[ ! -d "$worldsave" ]]; then
    die "worldsave does not exist: $worldsave"
  fi
  if [[ ! -d "$region_dir" ]]; then
    die "region_dir does not exist: $region_dir"
  fi

  ensure_dirs
  # Initialize state files if missing
  [[ -f "$BASE/State/last_log_activity.ts" ]] || write_state "last_log_activity.ts" "$(epoch)"
  [[ -f "$BASE/State/last_backup.ts" ]] || write_state "last_backup.ts" "0"
  # region_restore_depth.tsv created on first use
  touch "$BASE/State/restore.lock" 2>/dev/null || true
}

# --- Idle watcher: every 30s, if idle > 120s send telnet heartbeat; rate-limit Discord ---
idle_watcher_loop() {
  local last_heartbeat_discord=0
  while true; do
    sleep 30
    local now now_ts
    now_ts=$(epoch)
    now=$now_ts
    local last_activity
    last_activity=$(read_state "last_log_activity.ts" "$now_ts")
    local idle=$((now - last_activity))
    if [[ $idle -gt 120 ]]; then
      local hb_cmd="${heartbeat_cmd:-version}"
      if telnet_send "$hb_cmd"; then
        if [[ -n "${webhook:-}" ]]; then
          if [[ $((now - last_heartbeat_discord)) -ge 300 ]]; then
            discord_send "Heartbeat 🧘"
            last_heartbeat_discord=$now
          fi
        fi
      else
        log "Telnet heartbeat failed (no Discord spam)"
      fi
    fi
  done
}

# --- Create timestamped log and redirect stdout/stderr ---
LOG_FILE=""
start_logging() {
  local ts
  ts=$(date '+%Y-%m-%d_%H-%M-%S')
  LOG_FILE="$BASE/Logs/autofix_${ts}.log"
  mkdir -p "$BASE/Logs"
  exec >"$LOG_FILE" 2>&1
  export LOG_FILE
  log "RegionAutoFix started (BASE=$BASE, dry_run=${dry_run:-false})"
}

# --- Main ---
main() {
  validate_and_init
  start_logging

  log "Starting log monitor, backup scheduler, idle watcher"

  monitor_loop &
  local pid_monitor=$!
  backup_loop &
  local pid_backup=$!
  idle_watcher_loop &
  local pid_idle=$!

  wait $pid_monitor $pid_backup $pid_idle
}

main "$@"
