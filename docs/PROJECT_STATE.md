# NanZip Project State

Last updated: 2026-11-28 Asia/Shanghai

## Purpose

NanZip is a native macOS archive manager built in SwiftUI with a bundled open-source 7-Zip 26.06 engine, designed to grow toward Keka/Bandizip/ArcZip-class utility workflows without copying competitor implementations.

## Current release target

Version: 0.3.0 (build 3)

Minimum deployment target: macOS 14

## Canonical paths

- Project: `$HOME/Projects/NanZip`
- Xcode developer directory: `$DEVELOPER_DIR`
- Xcode user data: `$NANZIP_XCODE_DATA`
- Build cache: `$NANZIP_SCRATCH`
- Installed app: `$NANZIP_INSTALL_APP`
- GitHub: https://github.com/<GITHUB_OWNER>/NanZip

## Architecture

- `NanZipCore`: public archive models, 7-Zip process engine, list/extract/compress/edit services and cancellation.
- `NanZip`: SwiftUI app, compression/extraction modes, Finder URL handling.
- `NanZipFinder`: Finder Sync extension; one compact `NanZip` submenu.
- `NanZipQuickLook`: Quick Look Preview extension with archive contents.
- Bundled `7zz`: open-source archive engine under `Contents/Resources/Helpers`.

## Implemented features

- Bandizip-style icon command bar, archive tree and multi-column file table.
- Archive browsing, folder navigation and filtering.
- Add, replace, delete and test archive entries.
- Extract all/selected.
- Password extraction.
- Conflict handling.
- Progress and cancellation.
- ZIP/7Z/TAR/TAR.GZ/TAR.BZ2/TAR.XZ creation.
- ZIP and 7Z password creation.
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
- ZIP/7Z password round-trip: passing.
- Archive add/replace/delete: replace and delete tested; add uses the same update path.
- TAR compressed recursive extraction: passing.
- RAR fixture test: pending.
- Notarization: pending.
- GitHub remote: `https://github.com/<GITHUB_OWNER>/NanZip` (main pushed and verified)

## Build

```sh
cd "$HOME/Projects/NanZip"
NANZIP_SIGN_IDENTITY="<APPLE_DEVELOPMENT_IDENTITY>" ./Scripts/build-app.sh
```

## Resume instructions

1. Read `AGENTS.md`, `docs/CONTEXT_HANDOFF.md`, this file and the end of `docs/DEVELOPMENT_LOG.md`.
2. Inspect `git status` and remotes.
3. Build and run the smoke tests in `docs/TESTING.md`.
4. Continue with the unchecked reliability items in `docs/ROADMAP.md`.
