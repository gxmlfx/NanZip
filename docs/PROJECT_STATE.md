# NanZip Project State

Last updated: 2026-11-28 Asia/Shanghai

## Purpose

NanZip is a native macOS archive manager built in SwiftUI with a bundled open-source 7-Zip 26.06 engine, designed to cover mainstream Bandizip/Keka/ArcZip utility workflows without copying competitor implementations.

## Current release target

Version: 0.4.0 (build 4)

Minimum deployment target: macOS 14

## Canonical paths

- Project: `$HOME/Projects/NanZip`
- Xcode developer directory: `$DEVELOPER_DIR`
- Xcode user data: `$NANZIP_XCODE_DATA`
- Build cache: `$NANZIP_SCRATCH`
- Installed app: `$NANZIP_INSTALL_APP`
- GitHub: https://github.com/<GITHUB_OWNER>/NanZip

## Architecture

- `NanZipCore`: archive models, 7-Zip process engine, extraction/compression/editing, legacy ZIP filename decoding, single-entry preview extraction, ZIP salvage repair and XPC request/response protocol.
- `NanZip`: sandboxed SwiftUI app, Finder URL handling, Quick Actions, Keychain password manager, batch queue and XPC client.
- `NanZipXPCService`: embedded, independently signed out-of-process archive service. It owns 7-Zip process execution for app operations.
- `NanZipFinder`: Finder Sync extension with compact smart/here/folder extraction actions.
- `NanZipQuickLook`: Quick Look archive listing extension.
- Bundled `7zz`: open-source archive engine under both the app and XPC service resources.

## Implemented features

- Bandizip-style command bar, archive tree, multi-column table and bottom statistics.
- Persistent native column width/order/visibility customization.
- Archive browsing, folder navigation, filtering, preview and nested browsing.
- Add, replace, delete and test archive entries.
- Extract all/selected with Smart Extract, Extract Here, archive-named folder and custom folder rules.
- Ask, overwrite, skip, keep-both and newer-only conflict handling.
- ZIP/7Z/TAR/TAR.GZ/TAR.BZ2/TAR.XZ creation.
- Split-volume creation with 10/50/100/500 MB presets.
- ZIP/7Z encrypted creation and encrypted split ZIP round trips.
- ZIP legacy filename code-page selection and remapping.
- Single-entry preview extraction for images/documents/PDF/audio/video.
- Keychain-backed archive password manager.
- Batch compression/extraction queue with per-item status.
- ZIP local-header salvage to a new archive copy.
- Finder Sync menu, Finder Quick Actions and ZIP default-app setting.
- Main-app App Sandbox and independent XPC archive service.
- Liquid Glass on macOS 26/27; material fallback on macOS 14–25.

## Verification status

- SwiftPM debug/release build: passing.
- Full app and nested code signatures: passing.
- Finder/Quick Look/XPC bundle signing: passing.
- XPC list and extraction from the installed app: passing.
- Split ZIP/7Z/TAR.GZ creation and first-volume extraction: passing.
- Encrypted split ZIP creation and extraction: passing.
- CP437 and CP936 legacy ZIP listing, extraction and filename remapping: passing.
- ZIP repair copy from a deliberately destroyed central directory: passing.
- Keep-both, skip and overwrite extraction behavior: passing.
- Batch extraction of two archives through the GUI/XPC path: passing.
- GUI visual checks for archive table, persistent column hiding, document preview, nested ZIP browsing, batch workspace and compression settings: passing.
- RAR fixture test: pending.
- CP932 fixture test: pending.
- Notarization and Developer ID distribution: pending.
- GitHub remote: `https://github.com/<GITHUB_OWNER>/NanZip`

## Security note

The main app is sandboxed. The embedded XPC service performs archive operations out of process and is code-signed, but remains unsandboxed to receive direct filesystem paths in this non-App-Store build. A Mac App Store target still requires a security-scoped file-access bridge and a sandboxed XPC service.

## Build

```sh
cd "$HOME/Projects/NanZip"
NANZIP_SIGN_IDENTITY="<APPLE_DEVELOPMENT_IDENTITY>" ./Scripts/build-app.sh
```

Optional install:

```sh
NANZIP_SIGN_IDENTITY="<APPLE_DEVELOPMENT_IDENTITY>" \
NANZIP_INSTALL_APP="$HOME/Applications/NanZip.app" \
./Scripts/build-app.sh
```

## Resume instructions

1. Read `AGENTS.md`, `docs/CONTEXT_HANDOFF.md`, this file and the end of `docs/DEVELOPMENT_LOG.md`.
2. Inspect `git status` and remotes.
3. Build and run the smoke tests in `docs/TESTING.md`.
4. Continue with unchecked items in `docs/ROADMAP.md`.
