#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
if [ "$DEVELOPER_DIR" = "/Library/Developer/CommandLineTools" ]; then
  for candidate in /Volumes/*/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer; do
    if [ -d "$candidate" ]; then
      DEVELOPER_DIR="$candidate"
      break
    fi
  done
fi
export DEVELOPER_DIR

APP="${NANZIP_APP:-$ROOT/build/NanZip.app}"
IDENTITY="${NANZIP_SIGN_IDENTITY:-}"
PROFILE="${NANZIP_NOTARY_PROFILE:-nanzip-notary}"

if [ -z "$IDENTITY" ]; then
  echo "NANZIP_SIGN_IDENTITY must name a Developer ID Application certificate." >&2
  exit 64
fi
if [[ "$IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo "Refusing notarization with non-Developer-ID identity: $IDENTITY" >&2
  echo "Export NANZIP_SIGN_IDENTITY as the Developer ID Application identity." >&2
  exit 65
fi
if [ ! -d "$APP" ]; then
  echo "App bundle not found: $APP" >&2
  exit 66
fi

codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=4 "$APP" || true

OUTPUT_DIR="${NANZIP_RELEASE_DIR:-$ROOT/build/release}"
mkdir -p "$OUTPUT_DIR"
ZIP="$OUTPUT_DIR/NanZip-notarization.zip"
DMG="$OUTPUT_DIR/NanZip-0.5.0.dmg"

rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" \
  --keychain-profile "$PROFILE" \
  --wait

hdiutil create -volname "NanZip" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null
xcrun notarytool submit "$DMG" \
  --keychain-profile "$PROFILE" \
  --wait

xcrun stapler staple "$APP"
xcrun stapler staple "$DMG"
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"
spctl --assess --type execute --verbose=4 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG"
echo "Notarized app: $APP"
echo "Notarized disk image: $DMG"
