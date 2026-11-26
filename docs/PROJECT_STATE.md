# NanZip Project State

Last updated: 2026-11-27 Asia/Shanghai

## Purpose

NanZip is a native macOS archive manager built in SwiftUI with system `libarchive`, designed to grow toward Keka/Bandizip/ArcZip-class utility workflows without copying competitor implementations.

## Current release target

Version: 0.2.0 (build 2)

Minimum deployment target: macOS 14

## Canonical paths

- Project: `/Users/gxmlfx/Projects/NanZip`
- Xcode: `/Volumes/APFS P Drive/Applications/Xcode.app`
- Xcode user data: `/Volumes/APFS P Drive/XcodeData/Developer`
- Build cache: `/Volumes/APFS P Drive/XcodeData/NanZipBuild`
- Installed app: `/Volumes/APFS P Drive/Applications/NanZip.app`

## Architecture

- `NanZipCore`: public archive models, list/extract/compress services, cancellation.
- `NanZip`: SwiftUI app, compression/extraction modes, Finder URL handling.
- `NanZipFinder`: Finder Sync extension; one compact `NanZip` submenu.
- `NanZipQuickLook`: Quick Look Preview extension with archive contents.
- `CArchive`: libarchive bridge.

## Implemented features

- Archive browsing and filtering.
- Extract all/selected.
- Password extraction.
- Conflict handling.
- Progress and cancellation.
- ZIP/7Z/TAR.GZ/TAR.BZ2/TAR.XZ creation.
- ZIP AES-256 creation.
- Finder context menu.
- Quick Look archive listing.
- Zip Slip/path traversal prevention.
- Liquid Glass on macOS 26/27; material fallback on macOS 14–25.

## Verification status

- Build: passing.
- App signature: passing.
- Extension signatures and entitlements: passing.
- Finder extension registration: passing.
- Quick Look extension load: passing.
- Compression round-trip tests: passing.
- Encrypted ZIP round-trip: passing.
- RAR fixture test: pending.
- Notarization: pending.
- GitHub remote: pending at the time this file was written.

## Build

```sh
cd /Users/gxmlfx/Projects/NanZip
NANZIP_SIGN_IDENTITY="Apple Development: gxmlfx@icloud.com (48CV566UYY)" ./Scripts/build-app.sh
```

## Resume instructions

1. Read `AGENTS.md`, `docs/CONTEXT_HANDOFF.md`, this file and the end of `docs/DEVELOPMENT_LOG.md`.
2. Inspect `git status` and remotes.
3. Build and run the smoke tests in `docs/TESTING.md`.
4. Continue with the unchecked reliability items in `docs/ROADMAP.md`.
