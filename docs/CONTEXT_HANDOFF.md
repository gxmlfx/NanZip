# Context Handoff

Updated: 2026-11-28 (Asia/Shanghai)

## Current release

- Version: 0.5.0 (build 5)
- Project location: `$HOME/Projects/NanZip`
- GitHub repository: `https://github.com/<GITHUB_OWNER>/NanZip`
- Minimum OS: macOS 14
- UI: Liquid Glass progressive enhancement on macOS 26/27 with material fallback.

## Architecture now in place

- `NanZip`: sandboxed SwiftUI app.
- `NanZipCore`: archive, compression, editing, preview, repair and XPC protocol code.
- `NanZipXPCService`: embedded sandboxed XPC service used for archive operations.
- `NanZipFinder`: Finder Sync extension.
- `NanZipQuickLook`: archive contents Quick Look extension.
- Bundled open-source 7-Zip 26.06 as `Contents/Resources/Helpers/7zz` in the app and XPC bundle.

## Last known working state

- `NanZipCore`, `NanZip`, `NanZipXPCService`, `NanZipFinder` and `NanZipQuickLook` compile in debug and release.
- Full app bundle signs and verifies, including XPC and extensions.
- Main app and XPC service have App Sandbox; XPC client validation requires `com.gxmlfx.nanzip` and the same Team ID.
- XPC service accepts only paths under the private shared staging root.
- XPC internal test verifies list, compression, extraction and streamed progress (`progress_events=4`).
- SwiftPM core tests pass 6 tests with ZIP/7Z/TAR.GZ/GBK fixtures.
- ZIP/7Z/TAR.GZ split archives round-trip from `.001`.
- Encrypted split ZIP round-trip passes.
- CP437 and CP936 legacy filename extraction/remapping passes.
- ZIP repair creates a valid new archive from destroyed-central-directory input.
- Batch extraction of two archives through GUI and XPC passes.
- GUI shows archive preview, nested browser and persistent table-column customization.

## Known caveats

- Shared staging uses a narrow `/Users/Shared/NanZip/` temporary exception; a Mac App Store build needs an App Group or equivalent managed container.
- RAR/RAR5 extraction has not yet been fixture-tested in this repository.
- ZIP repair is intentionally limited to unencrypted Store/Deflate entries with recoverable local headers.
- CP932 decoder is implemented but needs a committed regression fixture.
- TAR.BZ2/TAR.XZ split extraction shares the TAR.GZ path but needs dedicated fixtures.
- Archive editing is atomic but encrypted-header and multi-volume editing edge cases need broader coverage.
- Symlink/special-file policy still needs a dedicated regression suite.
- Quick Look can compete with other installed archive preview extensions. NanZip's nested-archive view stays internal.
- Quick Look helper staging is implemented, but Quick Look was not fully revalidated through `qlmanage` in this session.
- Actual Developer ID notarization is blocked on missing Developer ID certificate and `nanzip-notary` keychain profile; the release script and runbook are ready.
- Finder extension registration and macOS Services cache may need refresh after reinstall.

## Commands

```sh
cd "$HOME/Projects/NanZip"
NANZIP_SIGN_IDENTITY="<APPLE_DEVELOPMENT_IDENTITY>" ./Scripts/build-app.sh
```

Install to a chosen location:

```sh
NANZIP_SIGN_IDENTITY="<APPLE_DEVELOPMENT_IDENTITY>" \
NANZIP_INSTALL_APP="$HOME/Applications/NanZip.app" \
./Scripts/build-app.sh
```

Refresh Finder/Quick Look registration:

```sh
APP="$NANZIP_INSTALL_APP"
pluginkit -a "$APP/Contents/PlugIns/NanZipFinder.appex"
pluginkit -a "$APP/Contents/PlugIns/NanZipQuickLook.appex"
pluginkit -e use -i com.gxmlfx.nanzip.finder
pluginkit -e use -i com.gxmlfx.nanzip.quicklook
```

## Read next

1. `docs/PROJECT_STATE.md`
2. `docs/DEVELOPMENT_LOG.md`
3. `docs/TESTING.md`
4. `docs/ROADMAP.md`
5. `docs/UPSTREAM_RESEARCH.md`
6. `docs/BANDIZIP_FEATURE_GAP.md`
7. `docs/RELEASE.md`
