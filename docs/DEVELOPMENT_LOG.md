# Development Log

## 2026-11-27 — Migration and feature expansion kickoff

User request:

- Move the ArcBox project to `~/Projects/NanZip`.
- Rename the product to NanZip.
- Add compression, Finder context menu, Quick Look preview, and encrypted compression.
- Adopt macOS 27 Liquid Glass with macOS 14+ compatibility.
- Research Keka, Bandizip, and ArcZip using official/GitHub/manual sources.
- Create Git/GitHub repository, commit, and push.
- Persist enough state that development can resume after context loss.

Work completed so far:

- Verified Xcode 27.2 and Swift 6.4.2 are running from the external APFS image.
- Verified the system libarchive has read/write support for ZIP, TAR, and 7-Zip; ZIP options include AES-128/AES-256 encryption.
- Inspected the macOS 27.2 SDK SwiftUI interfaces:
  - `glassEffect(_:in:)` is available macOS 26+.
  - `GlassEffectContainer` is available macOS 26+.
  - `.buttonStyle(.glass)` and `.glassProminent` are available macOS 26+.
- Moved the source from the temporary output directory to `$HOME/Projects/NanZip`.

Next actions:

- Rename package, targets, bundle IDs, resources, and build script from ArcBox to NanZip.
- Split shared archive code into `NanZipCore`.
- Add compression and verify encrypted ZIP creation.
- Add Finder Sync and Quick Look extension bundles.
- Apply Liquid Glass availability-gated styling.
- Research products and write `docs/ROADMAP.md` and `docs/UPSTREAM_RESEARCH.md`.
- Create Git and GitHub repository, commit, push, and verify remote.

## 2026-11-27 — Rename, compression, extensions, Liquid Glass

Completed:

- Renamed package/product/bundle IDs from ArcBox to NanZip.
- Added shared `NanZipCore` module for app and Quick Look.
- Added compression formats: ZIP, 7Z, TAR.GZ, TAR.BZ2, TAR.XZ.
- Added WinZip AES-256 encrypted ZIP creation using libarchive options and passphrase.
- Added compression UI with file/folder input, output path, format, level and password.
- Added custom URL handoff: `nanzip://compress` and `nanzip://extract`.
- Added Finder Sync extension. Per user feedback, actions are grouped inside one `NanZip` submenu.
- Added Quick Look Preview extension with archive contents table.
- Added sandbox entitlements for both extensions.
- Added macOS 26/27 `.glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)` and `.glassProminent` progressive enhancement while retaining macOS 14 materials fallback.
- Added `AGENTS.md`, context handoff, testing and upstream research docs.

Verification:

- `NanZipCore`, main app, Finder extension and Quick Look extension compile.
- Nested extension signatures have hardened runtime flags and sandbox entitlements.
- Finder and Quick Look extensions register with `pluginkit` and can be enabled.
- Finder menu observed: `NanZip > 压缩 / 解压`.
- Quick Look process loaded `NanZipQuickLook.appex` and displayed archive entries.
- GUI-created encrypted ZIP required a password and extracted successfully with `nanzip123`.
- ZIP/7Z/TAR compression round trips passed.
- UI displayed Liquid Glass surfaces on macOS 27.2.1.

Issue discovered and fixed:

- `codesign --deep` on the main app re-signed nested extensions and removed their entitlements/runtime flags. Final app signing now signs each extension first and signs the app without `--deep`.
- `pluginkit` registration can be invalidated after rebuilding extensions and must be refreshed.

Remaining immediate work:

- Complete GitHub CLI sudo authentication.
- Initialize Git, create GitHub repository and push.
- Verify remote contents after push.

## 2026-11-27 — Local Git checkpoint

- Initialized Git repository on branch `main`.
- Local root commit: `f23887e` (`feat: launch NanZip with compression and macOS extensions`).
- Working tree contains the complete source, extension packaging, entitlements, tests and research documentation.
- GitHub CLI login has reached GitHub sudo-mode confirmation. Manual account authentication is required before repository creation and push.


## 2026-11-27 — GitHub publication

- Created public repository: `https://github.com/<GITHUB_OWNER>/NanZip`.
- Added `origin` as `https://github.com/<GITHUB_OWNER>/NanZip.git`.
- Pushed branch `main` successfully.
- Initial commits published:
  - `f23887e` feature implementation
  - `1c769a1` local checkpoint and handoff docs
- Next documentation commit records the verified remote and final project state.

## 2026-11-28 — Bandizip layout, 7-Zip engine and archive editing

User requirements:

- Improve the UI layout using official Bandizip web screenshots, not the locally installed app.
- Replace macOS system libarchive with a faster open-source engine.
- Add archive-content replacement if absent.
- List remaining Bandizip-style features.

Changes:

- Removed the `CArchive`/system-libarchive bridge.
- Bundled open-source 7-Zip 26.06 as `Contents/Resources/Helpers/7zz`.
- Rewrote archive listing, extraction, compression and testing around the 7-Zip process.
- Added archive editing service for add, replace and delete operations using atomic working copies.
- Added progress parsing from 7-Zip output and password error classification.
- Added recursive TAR.GZ/TAR.BZ2/TAR.XZ extraction.
- Reworked the main window:
  - Bandizip-style icon command bar.
  - Left archive tree.
  - Multi-column file table with packed size, original size, ratio, modified date and method.
  - Bottom selection and archive statistics.
  - New Archive page with input list and labeled settings.
- Added UI actions for Add, Replace, Delete and Test.
- Added bundled 7-Zip third-party notice.

Official screenshot research:

- macOS screenshots: https://www.bandisoft.com/bandizip.mac/screenshots/
- Windows screenshots: https://www.bandisoft.com/bandizip/screenshots/
- Detailed notes: `docs/BANDIZIP_UI_RESEARCH.md`

Verification:

- ZIP/7Z/TAR/TAR.GZ/TAR.BZ2/TAR.XZ creation passed.
- ZIP/7Z password creation passed.
- ZIP/7Z/encrypted ZIP entry replacement passed.
- 7-Zip executable is signed inside the app and runs from the bundle.
- Finder and Quick Look extension packaging still signs successfully.
- Feature gap checklist: `docs/BANDIZIP_FEATURE_GAP.md`.
