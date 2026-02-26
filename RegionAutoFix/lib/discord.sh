# discord.sh - send Discord webhook notifications (no-op if webhook empty)

# Escape string for JSON content: backslash, quote, newline
discord_json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\n/\\n/g'
}

discord_send() {
  local msg="$1"
  if [[ -z "${webhook:-}" ]]; then
    return 0
  fi
  local escaped
  escaped=$(discord_json_escape "$msg")
  local payload="{\"content\": \"$escaped\"}"
  if ! curl -sf -X POST -H "Content-Type: application/json" -d "$payload" "$webhook" >/dev/null 2>&1; then
    log "Discord webhook failed (non-fatal)"
    return 1
  fi
  return 0
}

# One-time startup announcement: hostname, timestamp, config summary. No secrets. Cooldown to avoid spam.
discord_startup_announce() {
  if [[ -z "${webhook:-}" ]]; then
    return 0
  fi
  local cooldown="${startup_announce_cooldown:-300}"
  local now
  now=$(now_epoch)
  local last_announce
  last_announce=$(read_state "last_startup_announce.ts" "0")
  if [[ -n "$last_announce" && -n "$cooldown" ]] && [[ $((now - last_announce)) -lt $cooldown ]]; then
    log "Startup announce skipped (cooldown ${cooldown}s)"
    return 0
  fi
  write_state "last_startup_announce.ts" "$now"

  local host ts world log_disp backup_disp dry git_commit
  host=$(hostname 2>/dev/null || echo "unknown")
  ts=$(timestamp)
  world=$(get_world_name "${worldsave:-}")
  log_disp=$(sanitize_path "${logfile:-}")
  backup_disp=$(sanitize_path "${backup:-}")
  dry="${dry_run:-false}"
  git_commit=$(get_git_commit "$BASE")
  local msg
  msg="RegionAutoFix online
Host: $host | $ts
World: $world | Log: $log_disp | Backup: $backup_disp
dry_run: $dry | ${REGIONAUTOFIX_VERSION:-?} | git: $git_commit"

  if discord_send "$msg"; then
    log "Startup announcement sent to Discord"
    return 0
  else
    log "Startup announcement failed (webhook error)"
    return 1
  fi
}
