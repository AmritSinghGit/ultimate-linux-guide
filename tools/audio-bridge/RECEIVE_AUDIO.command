#!/bin/bash
set -u

PORT="${1:-49876}"

find_tool() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then command -v "$name"; return 0; fi
  for candidate in "/opt/homebrew/bin/$name" "/usr/local/bin/$name"; do
    if [ -x "$candidate" ]; then printf '%s\n' "$candidate"; return 0; fi
  done
  return 1
}

find_tailscale_cli() {
  if command -v tailscale >/dev/null 2>&1; then command -v tailscale; return 0; fi
  for candidate in /Applications/Tailscale.app/Contents/MacOS/Tailscale /usr/local/bin/tailscale /opt/homebrew/bin/tailscale; do
    if [ -x "$candidate" ]; then printf '%s\n' "$candidate"; return 0; fi
  done
  return 1
}

show_addresses() {
  printf 'Mac IPv4 addresses currently available:\n'
  local dev ip hw_port marker found=0
  while IFS= read -r dev; do
    [ -n "$dev" ] || continue
    ip="$(ipconfig getifaddr "$dev" 2>/dev/null || true)"
    [ -n "$ip" ] || continue
    hw_port="$(networksetup -listallhardwareports 2>/dev/null | awk -v d="$dev" '$1 == "Hardware" && $2 == "Port:" { sub(/^Hardware Port: /, ""); port=$0 } $1 == "Device:" && $2 == d { print port; exit }')"
    [ -n "$hw_port" ] || hw_port="network interface"
    marker=""
    case "$ip" in 192.168.137.*) marker="  <-- Windows hotspot/PAN candidate" ;; esac
    printf '  %-8s  %-15s  %s%s\n' "$dev" "$ip" "$hw_port" "$marker"
    found=1
  done < <(ifconfig -l 2>/dev/null | tr ' ' '\n')

  TS="$(find_tailscale_cli || true)"
  if [ -n "$TS" ]; then
    TS_IP="$(TAILSCALE_BE_CLI=1 "$TS" ip -4 2>/dev/null | head -n 1 || true)"
    if [ -n "$TS_IP" ]; then
      printf '  %-8s  %-15s  %s\n' 'tailscale' "$TS_IP" '<-- USE THIS when on different hotspots'
      found=1
    else
      printf '  tailscale  installed but not connected/signed in yet\n'
    fi
  fi

  [ "$found" -eq 1 ] || printf '  No active IPv4 address was detected.\n'
  printf '\n'
}

printf '\n============================================================\n'
printf ' Windows -> Mac Audio Receiver (LAN / Tailscale)\n'
printf '============================================================\n\n'

FFPLAY="$(find_tool ffplay || true)"
if [ -z "$FFPLAY" ]; then
  printf 'FFplay is missing. Rerun the GitHub AudioBridge one-liner.\n' >&2
  exit 1
fi

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; then
  printf 'Invalid UDP port: %s\n' "$PORT" >&2
  exit 2
fi

show_addresses
printf 'Select the desired speakers in System Settings > Sound > Output.\n'
printf 'Listening on UDP %s on ALL interfaces. Leave this window open; Control-C stops it.\n\n' "$PORT"

exec "$FFPLAY" -hide_banner -loglevel warning -nodisp -fflags nobuffer -flags low_delay -probesize 32768 -analyzeduration 0 -sync audio "udp://0.0.0.0:${PORT}?fifo_size=65536&overrun_nonfatal=1&reuse=1"
