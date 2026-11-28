# Bandizip Feature Gap

Updated: 2026-11-28

This checklist compares NanZip with publicly documented Bandizip capabilities. It is a development plan, not a claim of feature parity.

## Implemented in NanZip 0.5

- [x] Native macOS archive browser.
- [x] Left archive tree and central file table.
- [x] Original size, packed size, compression ratio, modified date and method columns.
- [x] Native column width, order and visibility customization with session persistence.
- [x] Search inside archive.
- [x] Extract all or selected files.
- [x] Password-protected extraction and Keychain password manager.
- [x] Progress and cancellation, including XPC operation cancellation.
- [x] Create ZIP, 7Z, TAR, TAR.GZ, TAR.BZ2 and TAR.XZ.
- [x] ZIP/7Z password creation through 7-Zip AES support.
- [x] Split/multi-volume creation. ZIP, 7Z and TAR.GZ first-volume extraction are regression-tested.
- [x] ZIP filename decoding and post-extraction renaming for Auto, UTF-8, CP437, CP936 and CP932.
- [x] Smart Extract, Extract Here, archive-named folder and custom-folder rules.
- [x] Overwrite, skip, keep-both, newer-only and ask-before-extract rules.
- [x] Add files to an existing archive.
- [x] Replace one archive entry with a local file.
- [x] Delete selected archive entries.
- [x] Test archive integrity.
- [x] Image, text, document, PDF and audio/video preview through an on-demand single-entry extraction.
- [x] Direct nested-archive browsing with breadcrumb/back navigation.
- [x] Batch compression/extraction queue with per-item status.
- [x] Finder Sync submenu with smart/here/choose-folder extraction.
- [x] Finder Quick Actions/Services in addition to Finder Sync.
- [x] ZIP default-application setting helper.
- [x] Quick Look archive contents listing.
- [x] Bundled open-source 7-Zip 26.06 engine.
- [x] Main-app and XPC App Sandbox with same-Team-ID client validation.
- [x] Private shared staging handoff for security-scoped user input/output.
- [x] XPC streaming progress and cancellation.
- [x] Developer ID/notarization release script.
- [x] SwiftPM automated test target with real ZIP/7Z/TAR.GZ/GBK fixtures.
- [x] macOS 26/27 Liquid Glass and macOS 14+ fallback.
- [x] Path traversal preflight checks.
- [x] Safe ZIP repair copy for unencrypted Store/Deflate entries.

## Remaining archive-manager basics

- [ ] Drag selected entries from an archive to Finder.
- [ ] Copy archive entry paths and metadata.
- [ ] Recent extraction destinations and recent archives.
- [ ] Rename entries without extraction.
- [ ] Multi-file replacement in one transaction.
- [ ] Edit an archive entry in an external app and save it back.
- [ ] Open a selected non-previewable entry directly with its default app.
- [ ] Per-entry integrity report rather than pass/fail summary.

## Remaining password and repair work

- [ ] Recent-password UI scoped by volume/user account.
- [ ] Generic 7Z/RAR repair or salvage workflow.
- [ ] Encrypted ZIP salvage when the central directory is destroyed.
- [ ] Password recovery is intentionally deferred because of security, legal and abuse risk.

## Remaining compression controls

- [ ] Compression method selection per format.
- [ ] Dictionary size, word size and solid-block options for 7Z.
- [ ] CPU thread count control.
- [ ] Store/deflate selection for ZIP.
- [ ] ZIPX and additional formats where the engine supports them.
- [ ] Delete source files after archiving.
- [ ] Saved compression presets and exclusion rules.
- [ ] Compression benchmark and import/export of presets.

## Remaining macOS/product work

- [ ] Mac App Store-compatible App Group/container handoff.
- [ ] Developer ID certificate issuance and actual Apple notary submission.
- [ ] Sparkle signed auto-update.
- [ ] Full localization.
- [ ] VoiceOver, Full Keyboard Access and high-contrast QA.
- [ ] Malware scan integration.
- [ ] Per-extension archive association management UI.
- [ ] Crash recovery and safe-edit journal.
- [ ] RAR/RAR5 committed fixture regression set.

## Known limitations

- The XPC service is sandboxed and only accepts shared staging paths. The shared staging path uses a Developer-ID-oriented temporary filesystem exception.
- Archive edits are atomic via a working copy, but encrypted-header edge cases still need broader fixture coverage.
- ZIP legacy-name remapping is tested for CP437 and GBK; CP932 is wired through the same decoder but needs a committed fixture.
- TAR.GZ split extraction is tested; TAR.BZ2/TAR.XZ split extraction follows the same path but needs dedicated regression fixtures.
- Quick Look may compete with another installed archive preview extension. NanZip's nested-archive action stays inside its own browser and does not delegate archive previews to third-party extensions.
