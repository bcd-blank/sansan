#!/usr/bin/env bash
# Capture final-spec v3 km labels on a dedicated sim → Agent Store impl-ios/.
# No TestFlight / no physical device install.
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
# Wipe app data so only JW fixture seeds remain (filename=content).
xcrun simctl uninstall "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$SIM_ID" "$APP"

DATA_CONTAINER=$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE_ID" data 2>/dev/null || true)

launch_mode() {
  local mode="$1"
  shift || true
  xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
  sleep 1
  # Prefer -SANSAN_SCREENSHOT launch args (SIMCTL_CHILD env can stick to a stale mode).
  if [[ "${EXPORT_SUMMARIES:-0}" == "1" ]]; then
    xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" \
      -UITestSeedRecords -UITestSkipHealthAuth -UITestSkipLocationAuth \
      -SANSAN_SCREENSHOT "$mode" -SANSAN_EXPORT_SUMMARIES "$@" >/dev/null
  else
    xcrun simctl launch "$SIM_ID" "$BUNDLE_ID" \
      -UITestSeedRecords -UITestSkipHealthAuth -UITestSkipLocationAuth \
      -SANSAN_SCREENSHOT "$mode" "$@" >/dev/null
  fi
}

capture_detail() {
  local mode="$1"
  local zoomout_name="$2"
  local zoomin_name="$3"
  launch_mode "$mode"
  # Fresh sim: user activate + fixture seed + detail navigation
  sleep 16
  xcrun simctl spawn "$SIM_ID" notifyutil -p com.jw.sansan.uitest.mapFit || true
  sleep 5
  xcrun simctl io "$SIM_ID" screenshot "$OUT/${zoomout_name}.png"
  xcrun simctl spawn "$SIM_ID" notifyutil -p com.jw.sansan.uitest.mapZoomIn || true
  sleep 5
  xcrun simctl io "$SIM_ID" screenshot "$OUT/${zoomin_name}.png"
  xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true
}

capture_detail detail-saryang ios-detail-saryangdo-zoomout ios-detail-saryangdo-zoomin
capture_detail detail-gahyeon ios-detail-gahyeonsan-zoomout ios-detail-gahyeonsan-zoomin
capture_detail detail-samak ios-detail-samaksan-zoomout ios-detail-samaksan-zoomin

# Share-summary PNGs via in-app renderer (JW real seeds).
EXPORT_SUMMARIES=1 launch_mode records -SANSAN_EXPORT_SUMMARIES
# Wait for MKMap snapshot + ImageRenderer
for _ in $(seq 1 40); do
  DATA_CONTAINER=$(xcrun simctl get_app_container "$SIM_ID" "$BUNDLE_ID" data 2>/dev/null || true)
  if [[ -n "${DATA_CONTAINER}" && -f "$DATA_CONTAINER/Documents/label-placement/SUMMARIES_DONE.txt" ]]; then
    break
  fi
  sleep 3
done
if [[ -n "${DATA_CONTAINER}" ]]; then
  for name in saryangdo gahyeonsan samaksan gamajicheon gamajicheon-memo-none gamajicheon-memo-on; do
    src="$DATA_CONTAINER/Documents/label-placement/ios-summary-${name}.png"
    if [[ -f "$src" ]]; then
      cp -f "$src" "$OUT/ios-summary-${name}.png"
    else
      echo "MISSING summary $src" >&2
    fi
  done
fi
xcrun simctl terminate "$SIM_ID" "$BUNDLE_ID" 2>/dev/null || true

echo "Wrote captures under $OUT"
ls -la "$OUT"
