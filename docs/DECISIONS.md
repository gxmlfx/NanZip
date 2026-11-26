# Architecture and Product Decisions

## Archive engine

Use system `libarchive` through the `CArchive` system-library target. It minimizes bundled third-party code and supports ZIP, 7-Zip, RAR extraction, TAR variants, GZIP/BZIP2/XZ and other formats.

## Compression scope

Initial creation targets:

- ZIP (deflate or store), with optional WinZip AES-256 encryption.
- 7-Zip via libarchive writer.
- TAR, TAR.GZ, TAR.BZ2, TAR.XZ.

Password creation is only enabled where the selected format and system libarchive implementation support it.

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
