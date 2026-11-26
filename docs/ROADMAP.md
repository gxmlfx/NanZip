# NanZip Roadmap

Research-driven priorities are based on public Keka, Bandizip for macOS and ArcZip documentation. See `UPSTREAM_RESEARCH.md`.

## Milestone 1 — Foundation and macOS integration

Status: largely complete.

- [x] Rename product, targets, bundle IDs and installed app to NanZip.
- [x] Split shared archive code into `NanZipCore`.
- [x] ZIP/7Z/TAR.GZ/TAR.BZ2/TAR.XZ creation.
- [x] ZIP WinZip AES-256 creation.
- [x] Finder Sync extension with one compact `NanZip` submenu.
- [x] Quick Look Preview extension showing archive contents.
- [x] macOS 26/27 Liquid Glass enhancement and macOS 14+ material fallback.
- [x] Path traversal protection.
- [x] Unicode filename fixture.
- [x] Git repository and GitHub publication.

## Milestone 2 — Reliability before breadth

Acceptance criteria:

- [ ] Automated fixture suite for ZIP/7Z/RAR/TAR/GZIP/BZIP2/XZ.
- [ ] RAR/RAR5 read fixtures verified against real archives.
- [ ] Corrupt/truncated archive errors are actionable and never crash.
- [ ] Cancel a multi-gigabyte extraction/compression and remove partial outputs.
- [ ] Preserve or deliberately skip symlinks with visible reporting.
- [ ] Handle duplicate paths, case-insensitive collisions and existing directories.
- [ ] Detect unsafe paths before writing any file.
- [ ] Add archive integrity test command and UI status.
- [ ] Add `swift test` target independent of the GUI.

## Milestone 3 — Archive-manager parity

- [ ] Smart extraction destination based on archive shape.
- [ ] Add/delete entries inside supported archives.
- [ ] Split/multi-volume archive creation and extraction.
- [ ] Filename encoding detection: GBK, GB18030, Shift-JIS, CP437 and UTF-8.
- [ ] Password manager backed by Keychain.
- [ ] Recent destinations and compression presets.
- [ ] Image/text/PDF preview inside archives without full extraction.
- [ ] Batch extraction and per-item destination rules.
- [ ] Compression profiles and saved exclusion rules.

## Milestone 4 — Security and distribution

- [ ] Move archive parsing/extraction/compression into an isolated XPC service.
- [ ] Validate all XPC clients and use one-time, scoped operation tokens.
- [ ] App Sandbox compatibility for the main app and extensions.
- [ ] Developer ID signing, hardened runtime and notarization.
- [ ] Sparkle-based update feed with signed appcast.
- [ ] Crash reporting with explicit opt-in.
- [ ] Release checklist and rollback procedure.
- [ ] Independent security review of path handling, temporary files and extension handoff.

## Milestone 5 — macOS 27 polish

- [ ] Liquid Glass interaction animations and glass grouping where measurable.
- [ ] macOS 14–25 visual regression snapshots.
- [ ] Full Keyboard Access and VoiceOver pass.
- [ ] Reduce Motion and Increase Contrast behavior.
- [ ] Light, dark and high-contrast design QA.
- [ ] Archive table column customization and accessibility descriptions.

## Explicit non-goals for the next release

- Claiming independent speed superiority without benchmarks.
- Claiming repair/password-recovery support before implementation and tests.
- Reusing competitor assets or proprietary UI.
- Implementing RAR compression.
