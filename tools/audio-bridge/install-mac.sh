#!/usr/bin/env bash
set -euo pipefail

BASE_URL="https://raw.githubusercontent.com/AmritSinghGit/ultimate-linux-guide/audio-bridge-bootstrap/tools/audio-bridge"
ROOT="$HOME/Downloads/AudioBridge"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

printf '\nAudioBridge bootstrap (Mac)\n===========================\n'

# Move away from the managed directory before touching it. This makes reruns safe
# even when Terminal was previously cd'd into ~/Downloads/AudioBridge.
cd "$HOME"
mkdir -p "$ROOT"

for file in SETUP_MAC.command RECEIVE_AUDIO.command; do
  curl -fsSL --retry 3 "$BASE_URL/$file" -o "$TMP/$file"
done
chmod +x "$TMP"/*.command
cp "$TMP"/*.command "$ROOT/"
chmod +x "$ROOT"/*.command

printf 'Refreshed safely: %s\n' "$ROOT"
printf 'Running setup, then starting the receiver...\n\n'

if ! "$ROOT/SETUP_MAC.command" </dev/tty; then
  code=$?
  printf '\nMac setup did not complete (exit %s). The files are still in %s.\n' "$code" "$ROOT" >&2
  exit "$code"
fi

exec "$ROOT/RECEIVE_AUDIO.command" </dev/tty
