#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
SCRATCH="${NANZIP_SCRATCH:-$HOME/Library/Developer/NanZipBuild}"
SIGN_IDENTITY="${NANZIP_SIGN_IDENTITY:--}"
APP="$ROOT/build/NanZip.app"
STAGE_APP="$SCRATCH/NanZip.app"

export DEVELOPER_DIR

/usr/bin/swift build \
  --package-path "$ROOT" \
  --scratch-path "$SCRATCH" \
  -c release \
  --product NanZip

/usr/bin/swift build \
  --package-path "$ROOT" \
  --scratch-path "$SCRATCH" \
  -c release \
  --product NanZipFinder

/usr/bin/swift build \
  --package-path "$ROOT" \
  --scratch-path "$SCRATCH" \
  -c release \
  --product NanZipQuickLook

BIN_PATH="$(/usr/bin/swift build \
  --package-path "$ROOT" \
  --scratch-path "$SCRATCH" \
  -c release \
  --show-bin-path)"

rm -rf "$STAGE_APP"
mkdir -p \
  "$STAGE_APP/Contents/MacOS" \
  "$STAGE_APP/Contents/Resources" \
  "$STAGE_APP/Contents/PlugIns/NanZipFinder.appex/Contents/MacOS" \
  "$STAGE_APP/Contents/PlugIns/NanZipQuickLook.appex/Contents/MacOS"

cp "$BIN_PATH/NanZip" "$STAGE_APP/Contents/MacOS/NanZip"
cp "$ROOT/Resources/NanZip-Info.plist" "$STAGE_APP/Contents/Info.plist"
printf 'APPL????' > "$STAGE_APP/Contents/PkgInfo"

cp "$BIN_PATH/NanZipFinder" \
  "$STAGE_APP/Contents/PlugIns/NanZipFinder.appex/Contents/MacOS/NanZipFinder"
cp "$ROOT/Resources/NanZipFinder-Info.plist" \
  "$STAGE_APP/Contents/PlugIns/NanZipFinder.appex/Contents/Info.plist"

cp "$BIN_PATH/NanZipQuickLook" \
  "$STAGE_APP/Contents/PlugIns/NanZipQuickLook.appex/Contents/MacOS/NanZipQuickLook"
cp "$ROOT/Resources/NanZipQuickLook-Info.plist" \
  "$STAGE_APP/Contents/PlugIns/NanZipQuickLook.appex/Contents/Info.plist"

/usr/bin/xattr -cr "$STAGE_APP" 2>/dev/null || true

/usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" \
  --entitlements "$ROOT/Resources/NanZipFinder.entitlements" \
  "$STAGE_APP/Contents/PlugIns/NanZipFinder.appex"
/usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" \
  --entitlements "$ROOT/Resources/NanZipQuickLook.entitlements" \
  "$STAGE_APP/Contents/PlugIns/NanZipQuickLook.appex"
/usr/bin/codesign --force --sign "$SIGN_IDENTITY" "$STAGE_APP"

/usr/bin/plutil -lint "$STAGE_APP/Contents/Info.plist"
/usr/bin/plutil -lint "$STAGE_APP/Contents/PlugIns/NanZipFinder.appex/Contents/Info.plist"
/usr/bin/plutil -lint "$STAGE_APP/Contents/PlugIns/NanZipQuickLook.appex/Contents/Info.plist"

rm -rf "$APP"
mkdir -p "$ROOT/build"
ditto "$STAGE_APP" "$APP"

if [ -n "${NANZIP_INSTALL_APP:-}" ]; then
  EXTERNAL_APP="$NANZIP_INSTALL_APP"
  rm -rf "$EXTERNAL_APP"
  mkdir -p "$(dirname "$EXTERNAL_APP")"
  ditto "$STAGE_APP" "$EXTERNAL_APP"
  /usr/bin/xattr -cr "$EXTERNAL_APP" 2>/dev/null || true
  /usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" \
    --entitlements "$ROOT/Resources/NanZipFinder.entitlements" \
    "$EXTERNAL_APP/Contents/PlugIns/NanZipFinder.appex"
  /usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" \
    --entitlements "$ROOT/Resources/NanZipQuickLook.entitlements" \
    "$EXTERNAL_APP/Contents/PlugIns/NanZipQuickLook.appex"
  /usr/bin/codesign --force --sign "$SIGN_IDENTITY" "$EXTERNAL_APP"
  echo "Installed: $EXTERNAL_APP"
fi

echo "$APP"
