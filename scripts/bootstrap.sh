#!/usr/bin/env bash
# Regenerate Murmur.xcodeproj from project.yml and patch out the XcodeGen
# 2.45.4 local-package-product-dependency-missing-link bug. Idempotent.
#
# Run after a fresh clone, after editing project.yml, or whenever
# Murmur.xcodeproj/ goes missing (it's gitignored).
#
# Pairs with: scripts/patch-xcodeproj.py
# Removal trigger: bump XcodeGen past the version that lands the fix for
#   the local-package product-dependency package= linkage bug, then drop
#   the patch step from this script.

set -euo pipefail

cd "$(dirname "$0")/.."

command -v xcodegen >/dev/null || {
    echo "ERROR: xcodegen not found. Install: brew install xcodegen" >&2
    exit 1
}

echo "==> xcodegen generate"
xcodegen generate

echo "==> patch-xcodeproj.py (XcodeGen 2.45.4 local-package linkage bug)"
python3 scripts/patch-xcodeproj.py

echo
echo "Bootstrap complete. Build with:"
echo "  xcodebuild -project Murmur.xcodeproj -scheme MurmurMac \\"
echo "    -configuration Debug -destination 'platform=macOS,arch=arm64' \\"
echo "    ONLY_ACTIVE_ARCH=YES build"
