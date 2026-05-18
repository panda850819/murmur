#!/usr/bin/env bash
# One-shot dogfood deploy: regenerate project → CLEAN build to a pinned
# derived-data path → re-sign with Developer ID → install to /Applications.
#
# Use THIS, not the steps by hand. The whole reason it exists: incremental
# xcodebuild + a regenerated XcodeGen project + a local SwiftPM package
# silently no-ops on Core/ source edits ("BUILD SUCCEEDED" but stale
# binary). `clean build` + the pinned path + dogfood-install.sh's
# stale-build guard make "what you test == what you built" guaranteed.
#
# See docs/learnings/pitfalls/2026-05-18-xcodebuild-stale-deriveddata-*.
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> bootstrap (xcodegen + patch)"
./scripts/bootstrap.sh >/dev/null

echo "==> xcodebuild CLEAN build (incremental is unreliable here)"
xcodebuild -project Murmur.xcodeproj -scheme MurmurMac \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .ddp ONLY_ACTIVE_ARCH=YES clean build \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -1

echo "==> install (Developer ID re-sign + stale-build guard)"
./scripts/dogfood-install.sh
