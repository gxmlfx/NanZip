# Upstream Product Research

Research date: 2026-11-27 (Asia/Shanghai)

This document summarizes public vendor material only. Vendor performance or security claims are not treated as independently verified. The purpose is to identify expected macOS archive-manager capabilities and to avoid inventing requirements.

## Keka

Sources:

- Official product page: https://www.keka.io/en/
- Official GitHub repository/README: https://github.com/aonez/Keka

Observed positioning:

- “the macOS file archiver”; emphasis on simple drag-and-drop workflows and privacy.
- Compression formats listed on the official page include 7Z, ZIP and TAR; extraction includes 7Z, ZIP, ZIPX, RAR, TAR and many additional formats.
- Password-protected archives are a first-class feature. The official page states AES-256 for 7z and Zip 2.0 legacy encryption for ZIP.
- Supports splitting large outputs into pieces.
- The GitHub repository is primarily used for issues, discussions, releases, translations and a collaborative wiki; its README does not present the repository as a complete reusable source-code distribution.

NanZip implications:

- A one-window drag-and-drop workflow is essential.
- Password creation must be format-aware and clearly explain the actual encryption scheme.
- Split archives are expected by users, even if implemented in a later phase.

## Bandizip for macOS

Sources:

- Official macOS product page: https://www.bandisoft.com/bandizip.mac/
- Official macOS screenshot page: https://www.bandisoft.com/bandizip.mac/screenshots/
- Official Windows screenshot page: https://www.bandisoft.com/bandizip/screenshots/
- Official Finder integration guide: https://www.bandisoft.com/bandizip.mac/help/finder-extension/
- Official password guide: https://www.bandisoft.com/bandizip.mac/help/how-to-set-a-password-for-an-archive/

Observed positioning and features:

- Finder services/right-click integration is explicitly promoted.
- Official page claims multi-core compression and significant speed advantages over Finder.
- Creation formats listed by the FAQ include ZIP, 7Z, ZIPX, TAR, TGZ and GZ.
- Extraction format list includes 7Z, RAR/RAR5, ALZ, EGG and ZIP, among others.
- Additional advertised capabilities include password manager, password recovery, archive repair, image/document/audio preview inside archives, split/multi-volume output and >4 GB archives.
- The password guide confirms archive-password entry as part of archive creation.

NanZip implications:

- Finder integration should stay concise and discoverable. NanZip will use one `NanZip` submenu instead of scattering multiple first-level actions.
- Password manager/recovery and repair are advanced differentiators, not MVP requirements.
- Archive testing and repair need explicit UI and safety boundaries before being advertised.

## ArcZip

Sources:

- Official product page: https://arczip.app/

Observed positioning and features:

- Positioned as a native macOS “archive workspace” for browsing, previewing, extracting and safely editing archives.
- Official page advertises 30+ formats, including ZIP, 7Z, RAR and TAR.
- Finder integration, folder-like archive browsing and searchable archive contents are prominent.
- Quick Look support is explicitly shown: press Space on an archive in Finder to inspect contents.
- Advertised features include encrypted and split archives, nested archive opening, malicious-path protection, staged publishing/transactional saving and an isolated service process.
- The product uses a free tier plus a paid Pro license.

NanZip implications:

- Quick Look should show the archive structure without extracting unrelated contents.
- Archive operations should avoid writing directly over user files when a safer staged workflow is feasible.
- Long-term architecture should move archive parsing/extraction into an isolated XPC helper before claiming strong security isolation.

## Capability comparison

| Capability | Keka | Bandizip macOS | ArcZip | NanZip current |
|---|---|---|---|---|
| Native macOS UI | Yes | Yes | Yes | Yes |
| ZIP/7Z/TAR extract | Yes | Yes | Yes | Yes, tested |
| RAR extract | Yes | Yes | Yes | 7-Zip-backed, not yet fixture-tested |
| ZIP/7Z/TAR create | Yes | Yes | Yes | Yes, tested |
| Encrypted create | 7z AES-256, ZIP legacy | Yes | Yes | ZIP WinZip AES-256, tested |
| Finder context menu | Yes | Yes | Yes | Implemented, registered and smoke-tested |
| Quick Look archive list | Not reviewed | Preview is a separate feature | Yes | Implemented, loaded and smoke-tested |
| Split archives | Yes | Yes | Yes | Not yet |
| Preview files inside archive | Not reviewed | Yes | Yes | Not yet |
| Repair/password recovery | Not reviewed | Yes | Not reviewed | Not yet |
| Isolated worker process | Not reviewed | Not reviewed | Yes | Not yet |

## Originality boundary

NanZip may learn from expected workflows and publicly documented capability lists, but it should not copy proprietary assets, icons, exact text, layouts or internal implementations. NanZip UI and code must remain original.
