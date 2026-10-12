#!/bin/bash
set -uo pipefail

rm -rf build/
mkdir -p build

echo "Build Started!"

xcodebuild \
  -project lara.xcodeproj \
  -scheme lara \
  -configuration Debug \
  -sdk iphoneos \
  -arch arm64e \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="Config/lara.entitlements" \
  archive \
  -archivePath "$PWD/build/lara.xcarchive" > "$PWD/build/xcodebuild.log" 2>&1
STATUS=$?

echo "=== xcodebuild exit code: $STATUS ==="

if [ $STATUS -ne 0 ]; then
  echo "=== ERROR LINES ==="
  grep -nE "error:" "$PWD/build/xcodebuild.log" | head -60
  echo ""
  echo "=== FAILED COMMANDS ==="
  grep -A30 "The following build commands failed" "$PWD/build/xcodebuild.log" | head -40
  echo ""
  echo "=== TAIL 40 ==="
  tail -40 "$PWD/build/xcodebuild.log"
  exit 1
fi

APP_PATH="$PWD/build/lara.xcarchive/Products/Applications/lara.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Missing app at $APP_PATH"
  exit 1
fi
rm -rf "$PWD/build/Payload"
mkdir -p "$PWD/build/Payload"
cp -R "$APP_PATH" "$PWD/build/Payload/"

plutil -replace UIFileSharingEnabled -bool YES "$PWD/build/Payload/lara.app/Info.plist"

if ! command -v ldid >/dev/null 2>&1; then
  echo "ERROR: ldid not installed. Install with: brew install ldid" >&2
  exit 1
fi
ldid -SConfig/lara.entitlements "$PWD/build/Payload/lara.app/lara"
(cd "$PWD/build" && /usr/bin/zip -qry lara.ipa Payload)

echo
echo "build successful!"
echo "ipa at: build/lara.ipa"
exit 0
