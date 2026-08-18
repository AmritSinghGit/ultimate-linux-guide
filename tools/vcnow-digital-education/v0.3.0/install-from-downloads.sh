#!/bin/bash
set -Eeuo pipefail

# VCNow Digital Education convergence v0.3.0 — install from the verified ZIP
# downloaded into the Mac Downloads folder from the ChatGPT handoff.

cd "$HOME" || exit 1
umask 077

VERSION="v0.3.0"
NAME="VCNOW_DIGITAL_EDUCATION_CONVERGENCE_${VERSION}"
ZIP_NAME="${NAME}.zip"
EXPECTED_SHA256="f7f85f4973b4544f53dfda33fa286929c38ecbb15925febbad7b57c516112a69"
DOWNLOADS="${VCNOW_INSTALL_DOWNLOADS_DIR:-$HOME/Downloads}"
ZIP_PATH="${VCNOW_PACKAGE_PATH:-$DOWNLOADS/$ZIP_NAME}"
TARGET="$DOWNLOADS/$NAME"

banner() {
  printf '\n============================================================\n%s\n============================================================\n' "$1"
}
fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

banner "VCNow Digital Education convergence ${VERSION}"
printf '%s\n' \
  "This verifies and starts one local review containing:" \
  "  • the VCNow website and programme/application handoff" \
  "  • progressive WordPress linkage and rollback controls" \
  "  • persistent AMS identity, OTP recovery and admissions" \
  "  • Canvas-class LMS learner/faculty/course operations" \
  "  • WhatsApp, PayU, Paynimo, LinkedIn, DigiLocker, Photos and Zoom gates" \
  "It does not change live WordPress, DNS, external providers or production data."

for tool in unzip shasum; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done

[ -f "$ZIP_PATH" ] || fail \
  "$ZIP_NAME is not in $DOWNLOADS. Download the v0.3.0 ZIP from the ChatGPT handoff first."

ACTUAL_SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
[ "$ACTUAL_SHA256" = "$EXPECTED_SHA256" ] || fail \
  "Package checksum mismatch. Expected $EXPECTED_SHA256, received $ACTUAL_SHA256"

if [ -e "$TARGET" ]; then
  BACKUP="${TARGET}.preserved-$(date +%Y%m%d-%H%M%S)"
  mv "$TARGET" "$BACKUP"
  printf 'Preserved earlier review at: %s\n' "$BACKUP"
fi

banner "Extracting and verifying every packaged file"
unzip -q "$ZIP_PATH" -d "$DOWNLOADS"
[ -d "$TARGET" ] || fail "The package did not create $TARGET"
cd "$TARGET"

if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine . 2>/dev/null || true
fi
chmod +x ./*.command 2>/dev/null || true
shasum -a 256 -c PACKAGE_MANIFEST.sha256

banner "Starting the integrated local review"
exec ./RUN_VCNOW_DIGITAL_EDUCATION.command
