# Architecture and Product Decisions

## Archive engine

Superseded 2026-11-28: use the bundled open-source 7-Zip console executable (`7zz`) instead of macOS system `libarchive`.

Reasons:

- 7-Zip provides multi-threaded compression and fast native format implementations.
- It supports ZIP/7Z creation, RAR/RAR5 reading, TAR families and many additional formats.
- It exposes update/delete/test operations required for archive-content editing.
- It avoids depending on the older system libarchive build.

Tradeoffs and controls:

- The executable is bundled under `Contents/Resources/Helpers/7zz` and must be signed with the app.
- Process output is parsed for progress and failures.
- Unsafe archive paths are rejected by NanZip before extraction.
- The app still needs a future XPC isolation boundary.

## Compression scope

Initial creation targets:

- ZIP (deflate or store), with optional WinZip AES-256 encryption.
- 7-Zip writer with multi-threaded `-mmt=on`.
- TAR, TAR.GZ, TAR.BZ2, TAR.XZ.

Password creation is enabled for ZIP and 7Z. TAR families do not support passwords.

## UI compatibility policy

- Deployment target: macOS 14.
- macOS 14–25: materials, gradients and standard controls.
- macOS 26/27: explicit Liquid Glass for floating surfaces and key actions where it improves hierarchy; standard controls also receive system glass treatment from the SDK.
- Never gate core functionality behind a new OS version.

## Extension strategy

- Finder Sync uses a custom `nanzip://` URL handoff instead of embedding archive logic.
- Quick Look imports `NanZipCore` to list archive entries without extracting them.
- Extensions are packaged manually as nested `.appex` bundles and signed before the containing app.

## Long-term recovery

The repository must always contain:

- `docs/PROJECT_STATE.md`: canonical paths and resume instructions.
- `docs/DEVELOPMENT_LOG.md`: chronological work log and verification results.
- `docs/ROADMAP.md`: prioritized remaining work.
- `docs/UPSTREAM_RESEARCH.md`: sourced competitor research and feature implications.
