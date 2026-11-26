# Testing

## Build

```sh
cd /Users/gxmlfx/Projects/NanZip
NANZIP_SIGN_IDENTITY="Apple Development: gxmlfx@icloud.com (48CV566UYY)" ./Scripts/build-app.sh
```

## Extraction self-test

```sh
APP="/Volumes/APFS P Drive/Applications/NanZip.app/Contents/MacOS/NanZip"
"$APP" --self-test archive.zip /tmp/nanzip-extract
```

## Compression self-test

```sh
"$APP" --compress-test zip /tmp/test.zip 6 - /path/to/input
"$APP" --compress-test sevenZip /tmp/test.7z 6 - /path/to/input
"$APP" --compress-test tarGz /tmp/test.tar.gz 6 - /path/to/input
"$APP" --compress-test zip /tmp/encrypted.zip 6 secret /path/to/input
```

## Verified on 2026-11-27

- ZIP extraction and creation.
- 7Z extraction and creation.
- TAR.GZ/TAR.BZ2/TAR.XZ creation and extraction.
- Unicode names: `子目录/测试.txt`.
- ZIP AES-256: extraction without password fails; correct password succeeds.
- Path traversal fixture containing `../evil.txt` is rejected.
- Finder menu appears as `NanZip > 压缩 / 解压`.
- Quick Look extension loads and displays the archive file list.
- Liquid Glass UI displayed on macOS 27.2.1; deployment target remains macOS 14.

## Extension registration

```sh
APP="/Volumes/APFS P Drive/Applications/NanZip.app"
pluginkit -a "$APP/Contents/PlugIns/NanZipFinder.appex"
pluginkit -a "$APP/Contents/PlugIns/NanZipQuickLook.appex"
pluginkit -e use -i com.gxmlfx.nanzip.finder
pluginkit -e use -i com.gxmlfx.nanzip.quicklook
pluginkit -mAv -i com.gxmlfx.nanzip.finder
pluginkit -mAv -i com.gxmlfx.nanzip.quicklook
```

## Important signing rule

Sign nested extensions first, with their entitlements, then sign the containing app without `--deep`. `--deep` re-signs nested code and can remove entitlements or runtime flags.
