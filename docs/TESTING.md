# Testing

## Build

```sh
NANZIP_ROOT="$HOME/Projects/NanZip"
NANZIP_APP="$HOME/Applications/NanZip.app"
NANZIP_BUNDLE_PREFIX="<BUNDLE_PREFIX>"
cd "$NANZIP_ROOT"

NANZIP_SIGN_IDENTITY="<APPLE_DEVELOPMENT_IDENTITY>" \
NANZIP_INSTALL_APP="$NANZIP_APP" \
./Scripts/build-app.sh

codesign --verify --deep --strict --verbose=2 "$NANZIP_APP"
```

## Basic extraction

```sh
APP="$NANZIP_APP/Contents/MacOS/NanZip"
"$APP" --self-test archive.zip /tmp/nanzip-extract
"$APP" --self-test archive.tar.gz /tmp/nanzip-extract - automatic overwrite
```

The optional arguments are:

```text
--self-test <archive> <destination> [password|-] [encoding] [overwrite]
```

Supported encoding values: `automatic`, `utf8`, `cp437`, `cp936`, `cp932`.

Supported overwrite values: `keepBoth`, `overwrite`, `skip`, `newerOnly`, `ask`.

## Compression

```sh
"$APP" --compress-test zip /tmp/test.zip 6 - /path/to/input
"$APP" --compress-test sevenZip /tmp/test.7z 6 - /path/to/input
"$APP" --compress-test tarGz /tmp/test.tar.gz 6 - /path/to/input
"$APP" --compress-test zip /tmp/encrypted.zip 6 secret /path/to/input
```

## Split volumes

```sh
"$APP" --volume-test zip /tmp/split.zip 6 - 10 /path/to/input
"$APP" --self-test /tmp/split.zip.001 /tmp/split-out

"$APP" --volume-test sevenZip /tmp/split.7z 6 - 10 /path/to/input
"$APP" --self-test /tmp/split.7z.001 /tmp/split-out

"$APP" --volume-test tarGz /tmp/split.tar.gz 6 - 10 /path/to/input
"$APP" --self-test /tmp/split.tar.gz.001 /tmp/split-out
```

Encrypted split ZIP:

```sh
"$APP" --volume-test zip /tmp/encrypted-split.zip 6 testpass 10 /path/to/input
"$APP" --self-test /tmp/encrypted-split.zip.001 /tmp/split-out testpass automatic overwrite
```

## Editing

```sh
"$APP" --replace-test /tmp/test.zip input/hello.txt /path/to/replacement.txt -
"$APP" --replace-test /tmp/encrypted.zip input/hello.txt /path/to/replacement.txt secret
"$APP" --delete-test /tmp/test.zip input/hello.txt -
```

## ZIP repair copy

The repair test expects a damaged/unencrypted ZIP whose local headers and compressed payload remain present but whose central directory is damaged or missing.

```sh
"$APP" --repair-test /tmp/broken.zip /tmp/repaired.zip -
"$APP" --self-test /tmp/repaired.zip /tmp/repaired-output
```

## XPC service

Run this from the signed app bundle, outside an enclosing command sandbox:

```sh
APP="$NANZIP_APP/Contents/MacOS/NanZip"
"$APP" --xpc-test /tmp/test.zip /tmp/xpc-output
```

Expected output includes `items=...` and `extracted=...`. This verifies the app-to-XPC connection and engine invocation from the installed bundle.

## Keychain password manager

```sh
"$APP" --keychain-test
```

This creates a temporary Keychain account, reads it back, verifies it appears in the account list and deletes it again.

## Manual GUI regression checklist

1. Open a ZIP containing folders, text, image, audio and nested ZIP entries.
2. Right-click a table header, hide/show a column, resize and reorder columns, relaunch and confirm persistence.
3. Select a text/image/audio entry and confirm the preview inspector appears.
4. Select a nested archive and use `更多 > 浏览嵌套归档`, then use `返回`.
5. Use `更多 > 智能解压`, `解压到当前目录` and `解压到指定文件夹…`.
6. Switch to compression, choose a split size and filename encoding, then create an archive.
7. Batch page: add two archives, choose an output directory and run batch extraction.
8. Settings → Password Manager: confirm saved archive passwords are listed and deletable.
9. Finder Sync: verify `NanZip` submenu contains compress and extraction shortcuts.
10. Finder Services/Quick Actions: verify `用 NanZip 压缩`, `NanZip 解压到当前目录`, `用 NanZip 解压…` after Services cache refresh.
11. Settings → General: invoke the default ZIP app helper and confirm macOS presents the system consent UI.

## Verified on 2026-11-28

- 7-Zip 26.06 engine bundled, signed and executable from app and XPC resources.
- ZIP/7Z/TAR/TAR.GZ/TAR.BZ2/TAR.XZ creation.
- ZIP/7Z password creation and password-required extraction failures.
- ZIP, 7Z and TAR.GZ split creation; extraction from `.001`.
- Encrypted split ZIP creation and extraction.
- Add/replace/delete archive entries.
- CP437 and CP936 legacy filename listing, extraction and filename remapping.
- ZIP central-directory salvage and repaired archive integrity.
- Skip and overwrite extraction policies.
- Path traversal rejection.
- Installed app XPC list/extract round-trip.
- Keychain save/read/list/delete round-trip.
- Main app sandbox entitlement and nested XPC/extension signing.
- Batch extraction of two archives through GUI and XPC.
- GUI archive table, persistent column hiding, document preview, nested archive browsing and batch UI.
- Finder Sync and Quick Look bundles register and sign; Quick Look itself was previously exercised.

## Extension registration

```sh
APP="$NANZIP_APP"
pluginkit -a "$APP/Contents/PlugIns/NanZipFinder.appex"
pluginkit -a "$APP/Contents/PlugIns/NanZipQuickLook.appex"
pluginkit -e use -i "${NANZIP_BUNDLE_PREFIX}.nanzip.finder"
pluginkit -e use -i "${NANZIP_BUNDLE_PREFIX}.nanzip.quicklook"
pluginkit -mAv -i "${NANZIP_BUNDLE_PREFIX}.nanzip.finder"
pluginkit -mAv -i "${NANZIP_BUNDLE_PREFIX}.nanzip.quicklook"
```

After adding/changing `NSServices`, refresh the Services cache:

```sh
/System/Library/CoreServices/pbs -update zh_CN en
/System/Library/CoreServices/pbs -read_bundle "$NANZIP_APP"
```

## Important signing rule

Sign the bundled `7zz` helpers first, then the XPC service and extensions, then the containing app. Never use `codesign --deep` as the final signing operation because it re-signs nested code and can remove entitlements/runtime flags.
