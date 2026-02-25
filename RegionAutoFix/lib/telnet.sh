# telnet.sh - send telnet commands via nc (127.0.0.1, 2-5s timeout); return 0 on success, 1 on failure

telnet_send() {
  local cmd="$1"
  local host="127.0.0.1"
  local port="${telnet:-8081}"
  local timeout="${telnet_timeout:-5}"
  [[ $timeout -lt 2 ]] && timeout=2
  [[ $timeout -gt 5 ]] && timeout=5
  local response

  if [[ -n "${telnet_password:-}" ]]; then
    response=$( (
      echo "$telnet_password"
      sleep 0.3
      echo "$cmd"
      sleep 1
    ) | nc -w "$timeout" "$host" "$port" 2>/dev/null) || true
  else
    response=$(echo "$cmd" | nc -w "$timeout" "$host" "$port" 2>/dev/null) || true
  fi

  if [[ -n "$response" ]]; then
    return 0
  fi
  return 1
}
