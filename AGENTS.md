# NanZip Repository Instructions

Before changing code:

1. Read `docs/PROJECT_STATE.md`, `docs/DEVELOPMENT_LOG.md`, `docs/CONTEXT_HANDOFF.md`, and the relevant section of `docs/ROADMAP.md`.
2. Run `git status` and inspect the latest commit.
3. Build with `NANZIP_SIGN_IDENTITY="<APPLE_DEVELOPMENT_IDENTITY>" ./Scripts/build-app.sh`.

Development constraints:

- Keep the deployment target at macOS 14 unless the user explicitly changes it.
- macOS 26/27 Liquid Glass is progressive enhancement. Never gate core functionality by OS version.
- Preserve the material fallback for macOS 14–25.
- Sign nested extensions before the containing app. Do not use `--deep` on the final app.
- Refresh `pluginkit` registration after rebuilding extensions.
- Update `docs/DEVELOPMENT_LOG.md` after meaningful changes.
- Update `docs/PROJECT_STATE.md` and `docs/CONTEXT_HANDOFF.md` when architecture, paths, build commands, known limitations or next actions change.
- Do not claim unverified format support, benchmarks, repair or recovery capabilities.
