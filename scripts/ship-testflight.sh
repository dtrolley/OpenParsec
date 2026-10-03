#!/bin/bash
# Archive, export, validate and upload OpenParsec to TestFlight (internal
# testing on team C4DK548P92). Builds expire after 90 days; re-run to renew.
#
# The build number is the current UTC minute, so it always increases and
# nothing has to be committed per build.
#
# Needs Frameworks/ParsecSDK.framework (git submodule, or copy it in). Its
# binary carries an x86_64 simulator slice that App Store validation rejects,
# so it is thinned to arm64 first.
#
# Usage: scripts/ship-testflight.sh [--no-upload]
set -euo pipefail
cd "$(dirname "$0")/.."
UPLOAD=1
[ "${1:-}" = "--no-upload" ] && UPLOAD=0

KEY_ID=755L5KJ37H
ISSUER=dbffc985-8e3d-43ba-b0f0-5618ba500403
SDK=Frameworks/ParsecSDK.framework/ParsecSDK

[ -f "$SDK" ] || { echo "Missing $SDK" >&2; exit 2; }
if lipo -archs "$SDK" | grep -qw x86_64; then
  lipo -remove x86_64 "$SDK" -output "$SDK"
fi

build=$(date -u +%Y%m%d%H%M)
echo "Build $build"
OUT=$(mktemp -d "${TMPDIR:-/tmp}/openparsec-ship.XXXXXX")
xcodebuild -project OpenParsec.xcodeproj -scheme OpenParsec -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/OpenParsec.xcarchive" \
  -derivedDataPath build/dd-archive -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$build" archive -quiet
xcodebuild -exportArchive -archivePath "$OUT/OpenParsec.xcarchive" \
  -exportOptionsPlist ExportOptions.plist -exportPath "$OUT/export" -allowProvisioningUpdates -quiet

# altool's stdout is the only record of a failed upload; keep it.
xcrun altool --validate-app -f "$OUT/export/OpenParsec.ipa" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER" 2>&1 | tee "$OUT/validate.log"
[ "$UPLOAD" = 0 ] && { echo "Validated only: $OUT"; exit 0; }
xcrun altool --upload-app -f "$OUT/export/OpenParsec.ipa" -t ios \
  --apiKey "$KEY_ID" --apiIssuer "$ISSUER" 2>&1 | tee "$OUT/upload.log"
grep -qi "UPLOAD SUCCEEDED\|No errors uploading" "$OUT/upload.log"
echo "Uploaded build $build. Logs: $OUT"
