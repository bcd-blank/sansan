#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIM_ID="${SIM_ID:-E7F7DEE7-028D-43E7-B18B-1C13FA13B080}"
DD="$ROOT/build/DerivedData"
APP="$DD/Build/Products/Debug-iphonesimulator/sansan.app"
OUT="$ROOT/AppStoreScreenshots"
RAW="$OUT/raw"
FINAL="$OUT/iPhone-6.7"

mkdir -p "$RAW" "$FINAL"

xcrun simctl boot "$SIM_ID" 2>/dev/null || true

xcodebuild \
  -project "$ROOT/sansan.xcodeproj" \
  -scheme sansan \
  -destination "platform=iOS Simulator,id=$SIM_ID" \
  -derivedDataPath "$DD" \
  build >/dev/null

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")"
xcrun simctl install "$SIM_ID" "$APP"

capture() {
  local mode="$1"
  local name="$2"
  local wait="${3:-4}"

  xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
  sleep 1
  SIMCTL_CHILD_SANSAN_SCREENSHOT="$mode" xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" >/dev/null
  sleep "$wait"
  xcrun simctl io "$SIM_ID" screenshot "$RAW/$name.png"
  echo "Captured $name"
}

capture dashboard 01-dashboard 5
capture records 02-records 4
capture kmsc 03-kmsc-browse 5
capture kmsc-detail 04-kmsc-detail 6

for file in "$RAW"/*.png; do
  base="$(basename "$file" .png)"
  sips -z 2796 1290 "$file" --out "$FINAL/${base}.png" >/dev/null
done

echo "Done. App Store size (1290×2796): $FINAL"
