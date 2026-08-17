#!/bin/bash
# Installs FFmpeg through an existing Homebrew installation.

set -u

find_brew() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

printf '\nMac audio receiver setup\n'
printf '========================\n\n'

if command -v ffplay >/dev/null 2>&1 || [ -x /opt/homebrew/bin/ffplay ] || [ -x /usr/local/bin/ffplay ]; then
  printf 'FFplay is already installed. No change is needed.\n'
  printf 'You can now run RECEIVE_AUDIO.command.\n\n'
  exit 0
fi

BREW="$(find_brew || true)"
if [ -z "$BREW" ]; then
  printf 'Homebrew was not found.\n\n'
  printf 'Install Homebrew from its official website, then rerun the same AudioBridge one-liner.\n'
  exit 1
fi

printf 'Installing FFmpeg with Homebrew...\n\n'
"$BREW" install ffmpeg
printf '\nInstallation complete.\n'
