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

show_ipv4_addresses() {
  printf 'Mac IPv4 addresses currently available:\n'
  local dev ip hw_port marker found=0
  while IFS= read -r dev; do
    [ -n "$dev" ] || continue
    ip="$(ipconfig getifaddr "$dev" 2>/dev/null || true)"
    [ -n "$ip" ] || continue
    hw_port="$(networksetup -listallhardwareports 2>/dev/null | awk -v d="$dev" '$1 == "Hardware" && $2 == "Port:" { sub(/^Hardware Port: /, ""); port=$0 } $1 == "Device:" && $2 == d { print port; exit }')"
    [ -n "$hw_port" ] || hw_port="network interface"
    marker=""
    case "$ip" in 192.168.137.*) marker="  <-- likely Windows Bluetooth PAN address" ;; esac
    printf '  %-8s  %-15s  %s%s\n' "$dev" "$ip" "$hw_port" "$marker"
    found=1
  done < <(ifconfig -l 2>/dev/null | tr ' ' '\n')
  [ "$found" -eq 1 ] || printf '  No active IPv4 address was detected.\n'
  printf '\nGive the Windows sender the Mac address belonging to the Bluetooth/PAN link.\n'
  printf 'It is often 192.168.137.x when Windows is providing the Bluetooth hotspot.\n\n'
}

printf '\n============================================================\n'
printf ' Windows -> Mac Bluetooth-PAN Audio Receiver\n'
printf '============================================================\n\n'

FFPLAY="$(find_tool ffplay || true)"
if [ -z "$FFPLAY" ]; then
  printf 'FFplay is missing. Rerun the GitHub AudioBridge one-liner after installing FFmpeg.\n' >&2
  exit 1
fi

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1024 ] || [ "$PORT" -gt 65535 ]; then
  printf 'Invalid UDP port: %s\n' "$PORT" >&2
  exit 2
fi

show_ipv4_addresses
printf 'Select the desired speakers in System Settings > Sound > Output.\n'
printf 'Listening on UDP %s. Leave this window open; Control-C stops it.\n\n' "$PORT"

exec "$FFPLAY" -hide_banner -loglevel warning -nodisp -fflags nobuffer -flags low_delay -probesize 32768 -analyzeduration 0 -sync audio "udp://0.0.0.0:${PORT}?fifo_size=65536&overrun_nonfatal=1&reuse=1"
