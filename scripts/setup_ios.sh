#!/usr/bin/env bash
# Prepare the iOS build on the Mac: verify pinned downloads, unpack llama.xcframework, build the
# starter catalog if source data exists, and generate the Xcode project with XcodeGen.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 scripts/download_materials.py   # no-op when checksums already match
ZIP="downloads/runtime/llama-b11429-xcframework.zip"
if [ ! -d vendor/llama.xcframework ]; then
  TMP="$(mktemp -d)"
  unzip -q "$ZIP" -d "$TMP"
  FOUND="$(find "$TMP" -maxdepth 3 -type d -name llama.xcframework | head -1)"
  [ -n "$FOUND" ] || { echo "llama.xcframework not found inside $ZIP" >&2; exit 1; }
  mkdir -p vendor
  mv "$FOUND" vendor/llama.xcframework
  rm -rf "$TMP"
fi
[ -d vendor/llama.xcframework/ios-arm64/llama.framework ] || { echo "Missing ios-arm64 slice" >&2; exit 1; }
if [ -f local-data/makati/manifest.json ]; then
  python3 scripts/build_starter_catalog.py
fi
command -v xcodegen >/dev/null || { echo "Install XcodeGen first: brew install xcodegen" >&2; exit 1; }
(cd LifeOffDesk && xcodegen generate)
echo "Open LifeOffDesk/LifeOffDesk.xcodeproj, set your signing team, choose your iPhone and Run."
