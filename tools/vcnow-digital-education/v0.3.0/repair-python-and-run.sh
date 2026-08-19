#!/bin/bash
set -Eeuo pipefail

# Repair the v0.3.0 local review after macOS selects an older /usr/bin/python3.
# This script changes only the extracted package's private review-data folder.
# It does not modify the VCNow repository, WordPress, DNS, providers or production.

cd "$HOME" || exit 1
umask 077

NAME="VCNOW_DIGITAL_EDUCATION_CONVERGENCE_v0.3.0"
ROOT="${VCNOW_PACKAGE_ROOT:-$HOME/Downloads/$NAME}"
RUNNER="$ROOT/RUN_VCNOW_DIGITAL_EDUCATION.command"
MANIFEST="$ROOT/PACKAGE_MANIFEST.sha256"
SHIM_DIR="$ROOT/review-data/python-shim"

banner() {
  printf '\n============================================================\n%s\n============================================================\n' "$1"
}
fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}
compatible_python() {
  local candidate="$1"
  [ -x "$candidate" ] || return 1
  "$candidate" - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info >= (3, 11) else 1)
PY
}
python_version() {
  "$1" - <<'PY'
import platform, sys
print(f"{sys.version.split()[0]} ({platform.machine()})")
PY
}

banner "VCNow v0.3.0 Python repair and continue"
[ -d "$ROOT" ] || fail "The extracted package is missing: $ROOT"
[ -f "$RUNNER" ] || fail "The package runner is missing: $RUNNER"
[ -f "$MANIFEST" ] || fail "The package manifest is missing: $MANIFEST"

cd "$ROOT"
shasum -a 256 -c PACKAGE_MANIFEST.sha256 >/dev/null
printf 'Package manifest: verified\n'

BREW="$(command -v brew 2>/dev/null || true)"
if [ -z "$BREW" ] && [ -x /opt/homebrew/bin/brew ]; then BREW=/opt/homebrew/bin/brew; fi
if [ -z "$BREW" ] && [ -x /usr/local/bin/brew ]; then BREW=/usr/local/bin/brew; fi

PYTHON_BIN=""
for candidate in \
  "${VCNOW_PYTHON:-}" \
  /opt/homebrew/bin/python3.12 \
  /opt/homebrew/bin/python3.11 \
  /opt/homebrew/bin/python3.13 \
  /usr/local/bin/python3.12 \
  /usr/local/bin/python3.11 \
  /usr/local/bin/python3.13 \
  "$(command -v python3.12 2>/dev/null || true)" \
  "$(command -v python3.11 2>/dev/null || true)" \
  "$(command -v python3.13 2>/dev/null || true)" \
  "$(command -v python3 2>/dev/null || true)"
do
  [ -n "$candidate" ] || continue
  if compatible_python "$candidate"; then
    PYTHON_BIN="$candidate"
    break
  fi
done

if [ -z "$PYTHON_BIN" ] && [ -n "$BREW" ]; then
  for formula in python@3.12 python@3.11 python@3.13; do
    prefix="$($BREW --prefix "$formula" 2>/dev/null || true)"
    [ -n "$prefix" ] || continue
    for candidate in \
      "$prefix/bin/python3.12" \
      "$prefix/bin/python3.11" \
      "$prefix/bin/python3.13" \
      "$prefix/libexec/bin/python3"
    do
      if compatible_python "$candidate"; then
        PYTHON_BIN="$candidate"
        break 2
      fi
    done
  done
fi

if [ -z "$PYTHON_BIN" ]; then
  [ -n "$BREW" ] || fail \
    "Python 3.11+ was not found and Homebrew is unavailable. Install Homebrew or Python 3.12, then rerun this command."
  banner "Installing Homebrew Python 3.12"
  "$BREW" install python@3.12
  prefix="$($BREW --prefix python@3.12)"
  PYTHON_BIN="$prefix/bin/python3.12"
  compatible_python "$PYTHON_BIN" || fail "Homebrew Python 3.12 did not become available"
fi

banner "Using a compatible Python runtime"
printf 'Selected Python: %s\n' "$PYTHON_BIN"
printf 'Version:         %s\n' "$(python_version "$PYTHON_BIN")"

mkdir -p "$SHIM_DIR"
ln -sfn "$PYTHON_BIN" "$SHIM_DIR/python3"

# Preserve only an incompatible package-local virtual environment. No user or
# repository environment is removed.
if [ -x "$ROOT/review-data/venv/bin/python" ] && ! compatible_python "$ROOT/review-data/venv/bin/python"; then
  preserved="$ROOT/review-data/venv.incompatible-$(date +%Y%m%d-%H%M%S)"
  mv "$ROOT/review-data/venv" "$preserved"
  printf 'Preserved incompatible package venv at: %s\n' "$preserved"
fi

export PATH="$SHIM_DIR:$PATH"
export VCNOW_PYTHON="$PYTHON_BIN"

banner "Continuing the integrated local review"
exec "$RUNNER"
