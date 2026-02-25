# backups.sh - scheduled Region-only backups with retention

backup_loop() {
  local savetime_mins="${savetime:-60}"
  local savecount_num="${savecount:-24}"
  while true; do
    sleep $((savetime_mins * 60))
    run_one_backup "$savecount_num"
  done
}

run_one_backup() {
  local retain="${1:-$savecount}"
  local ts
  ts=$(date '+%Y-%m-%d_%H-%M-%S')
  local snap_base="$backup/snap_$ts"
  if [[ ! -d "$region_dir" ]]; then
    log "Backup skipped: region_dir does not exist: $region_dir"
    return
  fi
  if [[ "${dry_run:-false}" == "true" ]]; then
    log "[DRY RUN] Would cp -a $region_dir $snap_base/Region"
  else
    mkdir -p "$snap_base"
    cp -a "$region_dir" "$snap_base/Region" || {
      log "Backup copy failed"
      return 1
    }
  fi
  write_state "last_backup.ts" "$(epoch)"
  # Retention: keep newest $retain snapshots
  local count=0
  local to_remove=()
  while IFS= read -r snap; do
    [[ -z "$snap" ]] && continue
    ((count++)) || true
    if [[ $count -gt $retain ]]; then
      to_remove+=("$snap")
    fi
  done < <(list_snapshots)
  for old in "${to_remove[@]}"; do
    if [[ "${dry_run:-false}" != "true" ]]; then
      rm -rf "$old"
    else
      log "[DRY RUN] Would remove old snapshot: $old"
    fi
  done
  log "Backup complete: snap_$ts"
  discord_send "Backup complete 🧘: snap_$ts"
}
