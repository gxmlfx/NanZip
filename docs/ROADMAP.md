# NanZip Roadmap

Research-driven priorities are based on public Keka, Bandizip for macOS and ArcZip documentation. See `UPSTREAM_RESEARCH.md`.

## Milestone 1 — Foundation and macOS integration

Status: complete.

- [x] Rename product, targets, bundle IDs and installed app to NanZip.
- [x] Split shared archive code into `NanZipCore`.
- [x] Bundled open-source 7-Zip 26.06 engine.
- [x] ZIP/7Z/TAR/TAR.GZ/TAR.BZ2/TAR.XZ creation.
- [x] ZIP/7Z password creation.
- [x] Add/replace/delete archive entries.
- [x] Integrity testing.
- [x] Bandizip-style command bar, archive tree and file table.
- [x] Finder Sync extension with one compact `NanZip` submenu.
- [x] Quick Look Preview extension showing archive contents.
- [x] macOS 26/27 Liquid Glass enhancement and macOS 14+ material fallback.
- [x] Path traversal protection.
- [x] Git repository and GitHub publication.

## Milestone 2 — Reliability before breadth

- [ ] Automated `swift test` fixture suite for ZIP/7Z/RAR/TAR/GZIP/BZIP2/XZ.
- [ ] RAR/RAR5 read fixtures verified against real archives.
- [x] Corrupt/truncated ZIP produces an actionable error and a separate repair-copy workflow.
- [ ] Cancel a multi-gigabyte extraction/compression and remove all partial outputs.
- [ ] Preserve or deliberately skip symlinks with visible reporting.
- [ ] Handle duplicate paths, case-insensitive collisions and existing directories.
- [x] Detect unsafe paths before writing any file.
- [x] Add archive integrity test command and UI status.
- [x] XPC operation IDs and cancellation requests.

## Milestone 3 — Archive-manager parity

- [x] Smart extraction destination based on archive shape.
- [x] Extract Here and Extract to Folder shortcuts.
- [x] Add/replace/delete entries inside supported archives.
- [x] Split/multi-volume creation and first-volume extraction.
- [x] ZIP filename decoding for UTF-8, CP437, CP936/GBK and CP932/Shift-JIS.
- [x] Password manager backed by Keychain.
- [x] Column width/order/visibility customization with persistence.
- [x] Image/document/audio preview inside archives without full extraction.
- [x] Nested archive browsing.
- [x] Batch compression/extraction with per-item status.
- [x] Ask/skip/newer/overwrite/keep-both policies.
- [ ] Recent destinations and compression presets.

## Milestone 4 — Security and distribution

- [x] Main app App Sandbox.
- [x] Move archive operations into an independently code-signed XPC service.
- [x] XPC operation IDs and cancellation.
- [ ] Sandbox the XPC service and transfer access through security-scoped bookmarks or equivalent.
- [ ] Validate XPC clients against bundle/team identifiers.
- [ ] Developer ID signing, notarization and hardened distribution.
- [ ] Sparkle-based update feed with signed appcast.
- [ ] Crash reporting with explicit opt-in.
- [ ] Release checklist and rollback procedure.
- [ ] Independent security review of path handling, temporary files and extension handoff.

## Milestone 5 — macOS 27 polish

- [x] Liquid Glass command bar and grouped material fallback.
- [x] Archive table column customization.
- [ ] macOS 14–25 visual regression snapshots.
- [ ] Full Keyboard Access and VoiceOver pass.
- [ ] Reduce Motion and Increase Contrast behavior.
- [ ] Light, dark and high-contrast design QA.
- [ ] Accessibility descriptions for every archive-row action.

## Explicit non-goals for the next release

- Claiming independent speed superiority without benchmarks.
- Claiming universal repair or password-recovery support.
- Reusing competitor assets or proprietary UI.
- Implementing RAR compression.
