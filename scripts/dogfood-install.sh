#!/usr/bin/env bash
# Re-sign the built MurmurMac.app with a STABLE self-signed identity and
# install it to /Applications, so macOS TCC grants (Microphone /
# Accessibility / Input Monitoring) SURVIVE rebuilds.
#
# Why: an adhoc-signed binary has no stable code identity, so TCC keys its
# grants on the cdhash — which changes every rebuild, revoking Mic / AX /
# Input-Monitoring every single time. A fixed self-signed cert gives the
# bundle a constant "designated requirement"; TCC then keeps the grant
# across rebuilds (you authorise once). CI (project.yml) stays adhoc — it
# has no local cert and doesn't need one.
#
# No setup needed: this auto-selects the existing "Developer ID
# Application" identity from the keychain (stable, Team-anchored — and the
# same cert the eventual signed-DMG release will use). Override with
# MURMUR_SIGN_IDENTITY="…" to force a specific identity.
#
# Every iteration:  ./scripts/bootstrap.sh && xcodebuild … build \
#                   && ./scripts/dogfood-install.sh

set -euo pipefail

DEST="/Applications/Murmur.app"

if [ -n "${MURMUR_SIGN_IDENTITY:-}" ]; then
  IDENTITY="$MURMUR_SIGN_IDENTITY"
else
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application:" | head -1 \
    | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+[0-9A-F]+[[:space:]]+"(.*)"$/\1/')
fi
if [ -z "${IDENTITY:-}" ]; then
  echo "ERROR: no 'Developer ID Application' identity found and" >&2
  echo "MURMUR_SIGN_IDENTITY not set. Pick one from:" >&2
  security find-identity -v -p codesigning >&2
  exit 1
fi

APP=$(find "$HOME/Library/Developer/Xcode/DerivedData" -maxdepth 6 \
  -name MurmurMac.app -path '*Build/Products/Debug*' -type d 2>/dev/null \
  | head -1)
if [ -z "${APP:-}" ]; then
  echo "ERROR: built MurmurMac.app not found. Build it first:" >&2
  echo "  ./scripts/bootstrap.sh && xcodebuild -project Murmur.xcodeproj \\" >&2
  echo "    -scheme MurmurMac -configuration Debug \\" >&2
  echo "    -destination 'platform=macOS,arch=arm64' ONLY_ACTIVE_ARCH=YES build" >&2
  exit 1
fi

if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
  echo "ERROR: code-signing identity '$IDENTITY' not in keychain. Available:" >&2
  security find-identity -v -p codesigning >&2
  exit 1
fi

rm -rf "$DEST"
cp -R "$APP" "$DEST"
codesign --force --deep --sign "$IDENTITY" "$DEST"

echo "==> signed:"
codesign -dvvv "$DEST" 2>&1 | grep -E "Authority=|Identifier=|Signature=" | head -3
echo "Installed + stably signed → $DEST"
echo
echo "First run after this: grant Microphone + Accessibility + Input"
echo "Monitoring ONCE. They will then persist across future rebuilds."
