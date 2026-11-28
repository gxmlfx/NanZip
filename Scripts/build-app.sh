#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEVELOPER_DIR="${DEVELOPER_DIR:-$(/usr/bin/xcode-select -p)}"
SCRATCH="${NANZIP_SCRATCH:-$HOME/Library/Developer/NanZipBuild}"
SIGN_IDENTITY="${NANZIP_SIGN_IDENTITY:--}"
APP="$ROOT/build/NanZip.app"
STAGE_APP="$SCRATCH/NanZip.app"
SEVEN_ZIP="${NANZIP_7ZZ:-}"
if [ -z "$SEVEN_ZIP" ] && [ -x "$ROOT/.tools/7zip/26.06/7zz" ]; then
  SEVEN_ZIP="$ROOT/.tools/7zip/26.06/7zz"
fi
if [ -z "$SEVEN_ZIP" ]; then
  SEVEN_ZIP="$(command -v 7zz || true)"
fi

if [ -z "$SEVEN_ZIP" ] || [ ! -x "$SEVEN_ZIP" ]; then
  echo "7-Zip engine not found. Run ./Scripts/fetch-7zz.sh or set NANZIP_7ZZ." >&2
  exit 1
fi

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

/usr/bin/swift build \
  --package-path "$ROOT" \
  --scratch-path "$SCRATCH" \
  -c release \
  --product NanZipXPCService

BIN_PATH="$(/usr/bin/swift build \
  --package-path "$ROOT" \
  --scratch-path "$SCRATCH" \
  -c release \
  --show-bin-path)"

rm -rf "$STAGE_APP"
mkdir -p \
  "$STAGE_APP/Contents/MacOS" \
  "$STAGE_APP/Contents/Resources" \
  "$STAGE_APP/Contents/XPCServices/NanZipXPCService.xpc/Contents/MacOS" \
  "$STAGE_APP/Contents/XPCServices/NanZipXPCService.xpc/Contents/Resources/Helpers" \
  "$STAGE_APP/Contents/PlugIns/NanZipFinder.appex/Contents/MacOS" \
  "$STAGE_APP/Contents/PlugIns/NanZipQuickLook.appex/Contents/MacOS" \
  "$STAGE_APP/Contents/Resources/Helpers"

cp "$BIN_PATH/NanZip" "$STAGE_APP/Contents/MacOS/NanZip"
cp "$ROOT/Resources/NanZip-Info.plist" "$STAGE_APP/Contents/Info.plist"
cp "$SEVEN_ZIP" "$STAGE_APP/Contents/Resources/Helpers/7zz"
chmod 755 "$STAGE_APP/Contents/Resources/Helpers/7zz"
cp "$ROOT/Resources/ThirdPartyNotices.md" "$STAGE_APP/Contents/Resources/ThirdPartyNotices.md"
printf 'APPL????' > "$STAGE_APP/Contents/PkgInfo"

cp "$BIN_PATH/NanZipFinder" \
  "$STAGE_APP/Contents/PlugIns/NanZipFinder.appex/Contents/MacOS/NanZipFinder"
cp "$ROOT/Resources/NanZipFinder-Info.plist" \
  "$STAGE_APP/Contents/PlugIns/NanZipFinder.appex/Contents/Info.plist"

cp "$BIN_PATH/NanZipQuickLook" \
  "$STAGE_APP/Contents/PlugIns/NanZipQuickLook.appex/Contents/MacOS/NanZipQuickLook"
cp "$ROOT/Resources/NanZipQuickLook-Info.plist" \
  "$STAGE_APP/Contents/PlugIns/NanZipQuickLook.appex/Contents/Info.plist"

cp "$BIN_PATH/NanZipXPCService" \
  "$STAGE_APP/Contents/XPCServices/NanZipXPCService.xpc/Contents/MacOS/NanZipXPCService"
cp "$ROOT/Resources/NanZipXPCService-Info.plist" \
  "$STAGE_APP/Contents/XPCServices/NanZipXPCService.xpc/Contents/Info.plist"
cp "$SEVEN_ZIP" \
  "$STAGE_APP/Contents/XPCServices/NanZipXPCService.xpc/Contents/Resources/Helpers/7zz"
chmod 755 \
  "$STAGE_APP/Contents/XPCServices/NanZipXPCService.xpc/Contents/MacOS/NanZipXPCService" \
  "$STAGE_APP/Contents/XPCServices/NanZipXPCService.xpc/Contents/Resources/Helpers/7zz"

/usr/bin/xattr -cr "$STAGE_APP" 2>/dev/null || true

/usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" \
  "$STAGE_APP/Contents/Resources/Helpers/7zz"
/usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" \
  "$STAGE_APP/Contents/XPCServices/NanZipXPCService.xpc/Contents/Resources/Helpers/7zz"
/usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" \
  "$STAGE_APP/Contents/XPCServices/NanZipXPCService.xpc"
/usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" \
  --entitlements "$ROOT/Resources/NanZipFinder.entitlements" \
  "$STAGE_APP/Contents/PlugIns/NanZipFinder.appex"
/usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" \
  --entitlements "$ROOT/Resources/NanZipQuickLook.entitlements" \
  "$STAGE_APP/Contents/PlugIns/NanZipQuickLook.appex"
/usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" \
  --entitlements "$ROOT/Resources/NanZip.entitlements" \
  "$STAGE_APP"

/usr/bin/plutil -lint "$STAGE_APP/Contents/Info.plist"
/usr/bin/plutil -lint "$STAGE_APP/Contents/PlugIns/NanZipFinder.appex/Contents/Info.plist"
/usr/bin/plutil -lint "$STAGE_APP/Contents/PlugIns/NanZipQuickLook.appex/Contents/Info.plist"
/usr/bin/plutil -lint "$STAGE_APP/Contents/XPCServices/NanZipXPCService.xpc/Contents/Info.plist"

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
    "$EXTERNAL_APP/Contents/Resources/Helpers/7zz"
  /usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" \
    "$EXTERNAL_APP/Contents/XPCServices/NanZipXPCService.xpc/Contents/Resources/Helpers/7zz"
  /usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" \
    "$EXTERNAL_APP/Contents/XPCServices/NanZipXPCService.xpc"
  /usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" \
    --entitlements "$ROOT/Resources/NanZipFinder.entitlements" \
    "$EXTERNAL_APP/Contents/PlugIns/NanZipFinder.appex"
  /usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" \
    --entitlements "$ROOT/Resources/NanZipQuickLook.entitlements" \
    "$EXTERNAL_APP/Contents/PlugIns/NanZipQuickLook.appex"
  /usr/bin/codesign --force --options runtime --sign "$SIGN_IDENTITY" \
    --entitlements "$ROOT/Resources/NanZip.entitlements" \
    "$EXTERNAL_APP"
  echo "Installed: $EXTERNAL_APP"
fi

echo "$APP"
