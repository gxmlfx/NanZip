# Testing

## Build

```sh
NANZIP_ROOT="$HOME/Projects/NanZip"
NANZIP_APP="$HOME/Applications/NanZip.app"
NANZIP_BUNDLE_PREFIX="<BUNDLE_PREFIX>"
cd "$NANZIP_ROOT"
NANZIP_SIGN_IDENTITY="<APPLE_DEVELOPMENT_IDENTITY>" ./Scripts/build-app.sh
```

## Extraction self-test

```sh
APP="$NANZIP_APP/Contents/MacOS/NanZip"
"$APP" --self-test archive.zip /tmp/nanzip-extract
```

## Archive content replacement self-test

```sh
"$APP" --replace-test /tmp/test.zip input/hello.txt /path/to/replacement.txt -
"$APP" --replace-test /tmp/encrypted.zip input/hello.txt /path/to/replacement.txt secret
```

## Compression self-test

```sh
"$APP" --compress-test zip /tmp/test.zip 6 - /path/to/input
"$APP" --compress-test sevenZip /tmp/test.7z 6 - /path/to/input
"$APP" --compress-test tarGz /tmp/test.tar.gz 6 - /path/to/input
"$APP" --compress-test zip /tmp/encrypted.zip 6 secret /path/to/input
```

## Verified on 2026-11-28

- 7-Zip 26.06 engine is bundled, signed and executable from inside the app.
- ZIP extraction and creation.
- 7Z extraction and creation.
- TAR.GZ/TAR.BZ2/TAR.XZ creation and extraction.
- Unicode names: `子目录/测试.txt`.
- ZIP and 7Z password creation: extraction without password fails; correct password succeeds.
- ZIP/7Z/encrypted ZIP entry replacement verified through the editing service.
- TAR.GZ/TAR.BZ2/TAR.XZ recursive extraction verified.
- Bandizip-style archive tree, multi-column table and selection statistics verified in the UI.
- Path traversal fixture containing `../evil.txt` is rejected.
- Finder menu appears as `NanZip > 压缩 / 解压`.
- Quick Look extension loads and displays the archive file list.
- Liquid Glass UI displayed on macOS 27.2.1; deployment target remains macOS 14.
- Bandizip official website screenshots were used for layout research; the locally installed Bandizip app was not used.
- Archive entry deletion verified through the editing service.
- Local smoke benchmark on one 64 MB zero-filled ZIP: 7-Zip `real 0.07s`, system `bsdtar` `real 0.12s`. This is only a directional local measurement, not a general performance claim.

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

## Important signing rule

Sign nested extensions first, with their entitlements, then sign the containing app without `--deep`. `--deep` re-signs nested code and can remove entitlements or runtime flags.
