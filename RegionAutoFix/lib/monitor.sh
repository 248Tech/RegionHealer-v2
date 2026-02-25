# monitor.sh - tail log, detect "incorrect region header", trigger restore

monitor_loop() {
  if [[ ! -f "$logfile" ]]; then
    log "Log file not found, waiting: $logfile"
    while [[ ! -f "$logfile" ]]; do
      sleep 10
    done
  fi

  tail -n 0 -F "$logfile" 2>/dev/null | while IFS= read -r line; do
    write_state "last_log_activity.ts" "$(epoch)"
    if echo "$line" | grep -qi "incorrect region header"; then
      # Extract region filename like r.-3.5.7rg (must end with .7rg)
      local region
      region=$(echo "$line" | grep -oE 'r\.[^[:space:]]+\.7rg' | head -1)
      if [[ -z "$region" ]]; then
        region=$(echo "$line" | grep -oE 'r\.[-0-9]+\.[-0-9]+\.7rg' | head -1)
      fi
      if [[ -n "$region" ]] && validate_region_filename "$region"; then
        local target_path="$region_dir/$region"
        local resolved
        if resolved=$(safe_realpath "$target_path" "$region_dir" 2>/dev/null); then
          true
        else
          resolved="$region_dir/$region"
          local base_ok
          base_ok=$(safe_realpath "$region_dir" "$region_dir" 2>/dev/null) || true
          if [[ -z "$base_ok" ]]; then
            base_ok=$region_dir
          fi
          if [[ "$resolved" != "$base_ok"/* ]] && [[ "$resolved" != "$base_ok" ]]; then
            log "Rejected region (path escape): $region"
            continue
          fi
        fi
        log "Corruption detected, triggering restore: $region"
        restore_region "$region" || log "Restore failed for $region"
      else
        log "Could not extract valid region filename from line: $line"
      fi
    fi
  done
}
