# restore.sh - restore_region with escalation, quarantine, flock, stop/start

restore_region() {
  local regionfile="$1"
  if ! validate_region_filename "$regionfile"; then
    log "Invalid region filename (rejected): $regionfile"
    return 1
  fi

  local target_path="$region_dir/$regionfile"
  local resolved
  if ! resolved=$(safe_realpath "$target_path" "$region_dir" 2>/dev/null); then
    # Target may not exist yet; check that canonical path of (region_dir + regionfile) is under region_dir
    local base_resolved
    base_resolved=$(safe_realpath "$region_dir" "$region_dir" 2>/dev/null) || true
    if [[ -z "$base_resolved" ]]; then
      base_resolved=$region_dir
    fi
    resolved="$base_resolved/$regionfile"
    if [[ "$resolved" != "$base_resolved"/* ]]; then
      log "Restore path would escape region_dir (rejected): $regionfile"
      return 1
    fi
  fi

  discord_send "Corrupt file found ✅: $regionfile"

  local lockfile="$BASE/State/restore.lock"
  local lock_fd=200
  eval "exec $lock_fd>$lockfile"
  if ! flock -w 300 "$lock_fd"; then
    log "Could not acquire restore lock"
    discord_send "Restore lock timeout ⚠️: $regionfile"
    return 1
  fi

  # --- Stop server ---
  local stopped_ok=0
  if [[ "${dry_run:-false}" == "true" ]]; then
    log "[DRY RUN] Would stop server (telnet/stopcmd/kill)"
    stopped_ok=1
  else
    if telnet_send "shutdown"; then
      log "Server shutdown sent via telnet"
      # Wait a bit for graceful shutdown
      sleep 10
      # Check if process still running; if so, try stopcmd then kill
      if server_still_running; then
        log "Server still running after telnet shutdown, trying stopcmd/kill"
        try_stop_server
      else
        stopped_ok=1
      fi
    else
      try_stop_server
    fi
    if server_still_running; then
      try_kill_server
      discord_send "Server stopped / stuck / killed 😵"
    fi
    if server_still_running; then
      log "Server still running after stop attempts; aborting restore to avoid data corruption"
      discord_send "Restore aborted ⚠️: server would not stop"
      flock -u "$lock_fd"
      return 1
    fi
    stopped_ok=1
  fi

  # --- Restore from backup with escalation ---
  local depth
  depth=$(get_restore_depth "$regionfile")
  local snap_list
  snap_list=$(list_snapshots)
  local snap_array=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && snap_array+=("$line")
  done <<< "$snap_list"

  local backup_path=""
  local idx=$((depth - 1))
  if [[ $idx -lt 0 ]]; then
    idx=0
  fi
  while [[ $idx -lt ${#snap_array[@]} ]]; do
    local snap="${snap_array[$idx]}"
    local candidate="$snap/Region/$regionfile"
    if [[ -f "$candidate" ]]; then
      backup_path=$candidate
      break
    fi
    ((idx++)) || true
  done

  if [[ -z "$backup_path" || ! -f "$backup_path" ]]; then
    log "No valid backup found for region: $regionfile"
    discord_send "No valid backup found ⚠️: $regionfile"
    flock -u "$lock_fd"
    return 1
  fi

  if [[ "${dry_run:-false}" != "true" ]]; then
    # Quarantine corrupt file before overwrite
    local live_file="$region_dir/$regionfile"
    if [[ -f "$live_file" ]]; then
      local qname="${regionfile%.7rg}_$(timestamp | tr ' ' '_' | tr -d ':').7rg"
      qname="${qname// /-}"
      cp -a "$live_file" "$BASE/State/quarantine/$qname" || log "Quarantine copy failed (non-fatal)"
    fi
    cp -a "$backup_path" "$region_dir/$regionfile" || {
      log "Restore copy failed"
      flock -u "$lock_fd"
      return 1
    }
  else
    log "[DRY RUN] Would copy $backup_path -> $region_dir/$regionfile and quarantine live file"
  fi

  set_restore_depth "$regionfile" $((depth + 1))
  discord_send "File restored from backup 💾: $regionfile"

  # --- Restart server ---
  if [[ "${dry_run:-false}" == "true" ]]; then
    log "[DRY RUN] Would restart server"
  else
    try_start_server
  fi
  discord_send "Server restarted 🔄"

  flock -u "$lock_fd"
  return 0
}

get_restore_depth() {
  local regionfile="$1"
  local path="$BASE/State/region_restore_depth.tsv"
  if [[ -f "$path" ]]; then
    local line
    line=$(grep -F "$regionfile" "$path" 2>/dev/null | head -1)
    if [[ -n "$line" ]]; then
      echo "$line" | awk -F'\t' '{print $2}'
      return
    fi
  fi
  echo "1"
}

set_restore_depth() {
  local regionfile="$1"
  local depth="$2"
  local path="$BASE/State/region_restore_depth.tsv"
  local temp="$path.$$"
  mkdir -p "$(dirname "$path")"

  if [[ -f "$path" ]]; then
    if awk -v name="$regionfile" -v d="$depth" -F'\t' 'BEGIN{OFS="\t"} $1==name {print $1,d; next} {print}' "$path" > "$temp"; then
      if grep -qF "$regionfile" "$temp" 2>/dev/null; then
        mv -f "$temp" "$path"
        return
      fi
    fi
    rm -f "$temp"
    # Awk failed or region missing from output: replace by filtering out old line and appending new one
    grep -v -F "$regionfile" "$path" > "$temp" 2>/dev/null || true
    mv -f "$temp" "$path" 2>/dev/null || true
  fi
  echo -e "${regionfile}\t${depth}" >> "$path"
}

# Check if 7DTD server process is still running (best-effort by username + common binary names)
server_still_running() {
  local user="${username:-root}"
  if pgrep -u "$user" -f "7DaysToDie" >/dev/null 2>&1; then
    return 0
  fi
  if pgrep -u "$user" -f "7Days.*Die" >/dev/null 2>&1; then
    return 0
  fi
  if pgrep -u "$user" -f "startserver" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

try_stop_server() {
  if [[ -n "${stopcmd:-}" ]]; then
    log "Running stopcmd: $stopcmd"
    $stopcmd || true
    sleep 5
    return
  fi
  try_kill_server
}

try_kill_server() {
  local user="${username:-root}"
  local pids
  pids=$(pgrep -u "$user" -f "7DaysToDie" 2>/dev/null) || true
  [[ -z "$pids" ]] && pids=$(pgrep -u "$user" -f "7Days.*Die" 2>/dev/null) || true
  [[ -z "$pids" ]] && pids=$(pgrep -u "$user" -f "startserver" 2>/dev/null) || true
  for pid in $pids; do
    log "Killing server PID $pid"
    kill -TERM "$pid" 2>/dev/null || true
  done
  sleep 5
  for pid in $pids; do
    if kill -0 "$pid" 2>/dev/null; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done
}

try_start_server() {
  if [[ -n "${startcmd:-}" ]]; then
    log "Running startcmd: $startcmd"
    nohup $startcmd >> "$LOG_FILE" 2>&1 &
    return
  fi
  # Best-effort: systemctl or service if name is guessable
  if type systemctl &>/dev/null; then
    for svc in 7daystodie 7dtd sdtd; do
      if systemctl start "$svc" 2>/dev/null; then
        log "Started service: $svc"
        return
      fi
    done
  fi
  if type service &>/dev/null; then
    for svc in 7daystodie 7dtd sdtd; do
      if service "$svc" start 2>/dev/null; then
        log "Started service: $svc"
        return
      fi
    done
  fi
  log "Could not start server (set startcmd in config)"
}
