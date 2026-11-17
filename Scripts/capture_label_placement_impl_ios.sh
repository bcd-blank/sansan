#!/usr/bin/env bash
# Capture final-spec v3 km labels on a dedicated sim → Agent Store impl-ios/.
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

SIM_ID="${SIM_ID:-E77A49AE-75C5-4BA7-9761-B8BC5B7FD01F}"
BUNDLE_ID="com.jw.sansan"
APP="${APP:-/tmp/sansan-label-dd/Build/Products/Debug-iphonesimulator/sansan.app}"
OUT="${OUT:-$HOME/Library/Application Support/Cursor/AgentStores/cursor_agent_stores/bc-75707dba-5737-4d43-b5ab-a5deda5241a4/files/docs/label-placement/final/impl-ios}"
mkdir -p "$OUT"

xcrun simctl boot "$SIM_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIM_ID" -b
xcrun simctl install "$SIM_ID" "$APP"

launch_mode() {
  local mode="$1"
  xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
  sleep 1
  SIMCTL_CHILD_SANSAN_SCREENSHOT="$mode" xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" \
    -UITestSeedRecords -UITestSkipHealthAuth -UITestSkipLocationAuth \
    -SANSAN_SCREENSHOT "$mode" >/dev/null
}

capture_detail() {
  local mode="$1"
  local zoomout_name="$2"
  local zoomin_name="$3"
  launch_mode "$mode"
  # Fresh sim: user activate + triple seed + detail navigation
  sleep 12
  xcrun simctl spawn "$SIM_ID" notifyutil -p com.jw.sansan.uitest.mapFit || true
  sleep 4
  xcrun simctl io "$SIM_ID" screenshot "$OUT/${zoomout_name}.png"
  xcrun simctl spawn "$SIM_ID" notifyutil -p com.jw.sansan.uitest.mapZoomIn || true
  sleep 4
  xcrun simctl io "$SIM_ID" screenshot "$OUT/${zoomin_name}.png"
  xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
}

capture_detail detail-saryang ios-detail-saryangdo-zoomout ios-detail-saryangdo-zoomin
capture_detail detail-gahyeon ios-detail-gahyeonsan-zoomout ios-detail-gahyeonsan-zoomin
capture_detail detail-samak ios-detail-samaksan-zoomout ios-detail-samaksan-zoomin

# Records list for summary thumbs (seeded titles)
launch_mode records
sleep 10
xcrun simctl io "$SIM_ID" screenshot "$OUT/ios-records-seeded.png"
xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true

echo "Wrote captures under $OUT"
ls -la "$OUT"
