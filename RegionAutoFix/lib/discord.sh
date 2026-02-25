# discord.sh - send Discord webhook notifications (no-op if webhook empty)

discord_send() {
  local msg="$1"
  if [[ -z "${webhook:-}" ]]; then
    return 0
  fi
  local payload
  payload=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')
  payload="{\"content\": \"$payload\"}"
  if ! curl -sf -X POST -H "Content-Type: application/json" -d "$payload" "$webhook" >/dev/null 2>&1; then
    log "Discord webhook failed (non-fatal)"
  fi
}
