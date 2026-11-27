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
- Moved the source from the temporary output directory to `/Users/gxmlfx/Projects/NanZip`.

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

- Created public repository: https://github.com/gxmlfx/NanZip
- Added `origin` as `https://github.com/gxmlfx/NanZip.git`.
- Pushed branch `main` successfully.
- Initial commits published:
  - `f23887e` feature implementation
  - `1c769a1` local checkpoint and handoff docs
- Next documentation commit records the verified remote and final project state.
