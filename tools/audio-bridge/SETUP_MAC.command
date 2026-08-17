#!/bin/bash
set -u

find_brew() {
  if command -v brew >/dev/null 2>&1; then command -v brew; return 0; fi
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
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

printf '\nMac audio receiver setup\n'
printf '========================\n\n'

BREW="$(find_brew || true)"

if command -v ffplay >/dev/null 2>&1 || [ -x /opt/homebrew/bin/ffplay ] || [ -x /usr/local/bin/ffplay ]; then
  printf 'FFplay is already installed.\n'
else
  if [ -z "$BREW" ]; then
    printf 'Homebrew was not found, so FFmpeg cannot be installed automatically.\n' >&2
    exit 1
  fi
  printf 'Installing FFmpeg with Homebrew...\n'
  "$BREW" install ffmpeg || exit $?
fi

printf '\nNetwork transport check\n'
printf '-----------------------\n'

TS="$(find_tailscale_cli || true)"
if [ -z "$TS" ] && [ -n "$BREW" ]; then
  printf 'No Bluetooth/PAN interface was detected in the previous run.\n'
  printf 'Installing Tailscale as the automatic fallback for separate phone hotspots...\n'
  "$BREW" install --cask tailscale-app || "$BREW" install --cask tailscale || true
  TS="$(find_tailscale_cli || true)"
fi

if [ -n "$TS" ]; then
  open -a Tailscale >/dev/null 2>&1 || true
  TS_IP="$(TAILSCALE_BE_CLI=1 "$TS" ip -4 2>/dev/null | head -n 1 || true)"
  if [ -n "$TS_IP" ]; then
    printf 'Tailscale connected: %s\n' "$TS_IP"
  else
    printf '\nONE-TIME ACTION: Tailscale has been opened.\n'
    printf 'Approve its VPN/network-extension prompt and sign in.\n'
    printf 'Both computers must be in the same Tailscale network.\n'
    printf 'After that, rerunning the SAME AudioBridge one-liner is enough.\n'
  fi
else
  printf 'Tailscale is not installed yet. The receiver will still listen on ordinary LAN interfaces.\n'
fi

printf '\nSetup complete.\n\n'
