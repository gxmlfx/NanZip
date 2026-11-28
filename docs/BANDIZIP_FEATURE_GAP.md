# Bandizip Feature Gap

Updated: 2026-11-28

This checklist compares NanZip with publicly documented Bandizip capabilities. It is a development plan, not a claim of feature parity.

## Implemented in NanZip now

- [x] Native macOS archive browser.
- [x] Left archive tree and central file table.
- [x] Original size, packed size, compression ratio, modified date and method columns.
- [x] Search inside archive.
- [x] Extract all or selected files.
- [x] Password-protected extraction.
- [x] Progress and cancellation.
- [x] Create ZIP, 7Z, TAR, TAR.GZ, TAR.BZ2 and TAR.XZ.
- [x] ZIP/7Z password creation through 7-Zip AES support.
- [x] Add files to an existing archive.
- [x] Replace one archive entry with a local file.
- [x] Delete selected archive entries.
- [x] Test archive integrity.
- [x] Finder right-click submenu: Compress/Extract.
- [x] Quick Look archive contents listing.
- [x] Bundled open-source 7-Zip 26.06 engine.
- [x] macOS 26/27 Liquid Glass and macOS 14+ fallback.
- [x] Path traversal preflight checks.

## P0 — expected archive-manager basics

- [ ] Smart extraction destination rules.
- [ ] “Extract here”, “Extract to folder” and “Extract to another folder” as distinct Finder actions.
- [ ] Split/multi-volume archive creation and extraction.
- [ ] Filename encoding/code-page selection and recovery.
- [ ] Column visibility, width and order customization.
- [ ] Drag selected entries from an archive to Finder.
- [ ] Copy archive entry paths and metadata.
- [ ] More advanced overwrite rules: ask, newer-only, rename, skip.
- [ ] Recent extraction destinations and recent archives.
- [ ] Batch extraction for multiple archives.

## P1 — archive editing and preview depth

- [ ] Multi-file replacement in one transaction.
- [ ] Rename entries without extracting them.
- [ ] Edit an archive entry in an external app and save it back.
- [ ] Add/replace/delete support audit for every writable format.
- [ ] Image thumbnails inside archive.
- [ ] Document and audio preview inside archive.
- [ ] Nested archive browsing without manually extracting to Finder.
- [ ] Open selected archive entry with Quick Look.
- [ ] Archive comments and metadata inspection.
- [ ] Integrity test report with per-entry failures.

## P1 — password and repair workflows

- [ ] Password manager backed by Keychain.
- [ ] Recent passwords scoped by archive.
- [ ] Repair command UI for ZIP/7Z where the engine supports recovery.
- [ ] Password recovery is intentionally deferred because of security, legal and abuse risk.

## P2 — advanced compression controls

- [ ] Compression method selection per format.
- [ ] Dictionary size, word size and solid-block options for 7Z.
- [ ] CPU thread count control.
- [ ] Store/deflate selection for ZIP.
- [ ] ZIPX and additional exotic formats where the engine supports them.
- [ ] Create split archives by configurable size.
- [ ] “Delete source files after archiving” option.
- [ ] “Create one archive per file/folder” option.
- [ ] Compression benchmark and saved presets.

## P2 — macOS integration and product quality

- [ ] Finder Quick Actions/Services in addition to Finder Sync.
- [ ] “Set NanZip as default archive app” helper.
- [ ] App Sandbox/XPC isolation for archive operations.
- [ ] Developer ID signing, notarization and hardened distribution.
- [ ] Sparkle signed auto-update.
- [ ] Full localization.
- [ ] VoiceOver, Full Keyboard Access and high-contrast QA.
- [ ] Malware scan integration.
- [ ] Archive association management.
- [ ] Crash recovery and safe-edit journal.

## Known limitations after the 7-Zip migration

- The engine is invoked as a bundled command-line process. It is faster and format-capable, but operations are not yet isolated in XPC.
- Archive edits are atomic via a working copy but encrypted-header edge cases still need broader fixture coverage.
- RAR/RAR5 read support exists in 7-Zip, but NanZip does not yet have a committed RAR regression fixture set.
- TAR.GZ/BZ2/XZ extraction is recursively handled by NanZip, but creation uses a two-stage TAR plus compression flow.
- Quick Look may compete with another installed archive preview extension. macOS selects the registered preview extension; NanZip's extension itself has been loaded and verified.
