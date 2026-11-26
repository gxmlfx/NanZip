# Context Handoff

Updated: 2026-11-27 (Asia/Shanghai)

## What is already implemented

- Project location: `/Users/gxmlfx/Projects/NanZip`
- Native SwiftUI app: `NanZip`
- Shared library: `NanZipCore`
- Finder Sync extension: `NanZipFinder`
- Quick Look Preview extension: `NanZipQuickLook`
- System libarchive bridge: `CArchive`
- ZIP/7Z/TAR.GZ/TAR.BZ2/TAR.XZ creation
- ZIP AES-256 creation
- Extraction with password, selection, progress and cancellation
- Liquid Glass on macOS 26+; material fallback for macOS 14–25

## Last known working state

- `NanZipCore`, `NanZip`, `NanZipFinder` and `NanZipQuickLook` compile.
- Full app bundle signs and verifies.
- Finder submenu `NanZip > 压缩 / 解压` was displayed.
- Quick Look displayed `archive.zip` entries.
- AES-256 ZIP and all compression-format smoke tests passed.
- Recommended local signing identity: `Apple Development: gxmlfx@icloud.com (48CV566UYY)`.

## Known caveats

- GitHub CLI authorization is pending sudo-mode account confirmation.
- RAR extraction has not yet been fixture-tested.
- Symlinks are currently listed but skipped during extraction.
- Quick Look in the presence of ArcZip may select ArcZip due to extension precedence. Temporarily ignoring ArcZip confirmed NanZip Quick Look loads.
- Finder extension registration must be refreshed after rebuilding the app.
- The main app is not sandboxed yet; extensions are sandboxed.
- No notarized release has been produced.

## Commands

```sh
cd /Users/gxmlfx/Projects/NanZip
NANZIP_SIGN_IDENTITY="Apple Development: gxmlfx@icloud.com (48CV566UYY)" ./Scripts/build-app.sh
```

## Read next

1. `docs/PROJECT_STATE.md`
2. `docs/DEVELOPMENT_LOG.md`
3. `docs/ROADMAP.md`
4. `docs/UPSTREAM_RESEARCH.md`
5. `docs/TESTING.md`
