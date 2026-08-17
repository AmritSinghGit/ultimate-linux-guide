#!/usr/bin/env bash
set -euo pipefail

BASE_URL="https://raw.githubusercontent.com/AmritSinghGit/ultimate-linux-guide/audio-bridge-bootstrap/tools/audio-bridge"
ROOT="$HOME/Downloads/AudioBridge"

printf '\nAudioBridge bootstrap (Mac)\n===========================\n'
rm -rf "$ROOT"
mkdir -p "$ROOT"

curl -fsSL --retry 3 "$BASE_URL/SETUP_MAC.command" -o "$ROOT/SETUP_MAC.command"
curl -fsSL --retry 3 "$BASE_URL/RECEIVE_AUDIO.command" -o "$ROOT/RECEIVE_AUDIO.command"
chmod +x "$ROOT"/*.command

printf 'Refreshed: %s\n' "$ROOT"
printf 'Running setup, then starting the receiver...\n\n'
"$ROOT/SETUP_MAC.command" </dev/tty || true
exec "$ROOT/RECEIVE_AUDIO.command" </dev/tty
