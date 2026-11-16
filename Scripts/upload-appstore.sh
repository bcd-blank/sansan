#!/bin/bash
# Runs after Product → Archive. Uploads that archive to App Store Connect
# without changing its build number, so the Organizer version and the
# App Store Connect build number stay the same.
set -u

if [[ -z "${ARCHIVE_PATH:-}" || ! -d "$ARCHIVE_PATH" ]]; then
  echo "error: ARCHIVE_PATH is missing. Archive with the sansan scheme."
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OPTIONS="$ROOT/scripts/ExportOptions.plist"
EXPORT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sansan-upload.XXXXXX")"
INFO="$ARCHIVE_PATH/Info.plist"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$INFO")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$INFO")"

ALREADY="$(python3 - "$INFO" << 'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as f:
    archive = plistlib.load(f)
for item in archive.get("Distributions") or []:
    event = item.get("uploadEvent") or {}
    if event.get("state") == "success":
        print(item.get("uploadedBuildNumber") or "")
        break
PY
)"

if [[ -n "$ALREADY" ]]; then
  echo "Already on App Store Connect as ${VERSION} (${ALREADY})."
  exit 0
fi

echo "Uploading ${VERSION} (${BUILD}) to App Store Connect..."
if ! /usr/bin/xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$OPTIONS" \
  -allowProvisioningUpdates
then
  echo "error: upload failed for ${VERSION} (${BUILD}). Organizer still shows this archive. Do not Distribute it again from Organizer; that can send a different build number."
  exit 1
fi

echo "Uploaded ${VERSION} (${BUILD}). After processing, add this build on the ${VERSION} page in App Store Connect."
osascript -e "display notification \"${VERSION} (${BUILD}) 업로드됨. 처리가 끝나면 App Store Connect에서 이 빌드를 추가하세요.\" with title \"sansan\"" || true

python3 - "$ROOT/sansan.xcodeproj/project.pbxproj" "$BUILD" << 'PY'
import pathlib, sys
path = pathlib.Path(sys.argv[1])
build = sys.argv[2]
text = path.read_text()
needle = f"CURRENT_PROJECT_VERSION = {build};"
count = text.count(needle)
total = text.count("CURRENT_PROJECT_VERSION")
if count == 0 or count != total:
    print(f"Left the project build number unchanged (archive was {build}).")
    sys.exit(0)
nxt = str(int(build) + 1)
path.write_text(text.replace(needle, f"CURRENT_PROJECT_VERSION = {nxt};"))
print(f"Next archive will be build {nxt}.")
PY
