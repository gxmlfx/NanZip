# Release and Notarization Runbook

NanZip uses Developer ID distribution outside the Mac App Store. The build must be signed with a Developer ID Application certificate and notarized by Apple before it is published.

## Prerequisites

- Xcode with the Developer ID Application certificate in the login Keychain
- Apple Developer team membership and notary access
- A stored `notarytool` keychain profile
- Network access to Apple's notary service

Create a notary profile once:

```sh
xcrun notarytool store-credentials nanzip-notary \
  --apple-id "<APPLE_DEVELOPER_EMAIL>" \
  --team-id "<APPLE_DEVELOPER_TEAM_ID>" \
  --password "<APP_SPECIFIC_PASSWORD>"
```

Do not write the profile password, Apple ID or Team ID into the repository.

## Build a Developer ID candidate

```sh
cd "$HOME/Projects/NanZip"
NANZIP_SIGN_IDENTITY="Developer ID Application: <DEVELOPER_NAME> (<TEAM_ID>)" \
  ./Scripts/build-app.sh
```

The app contains a sandboxed XPC service and a sandboxed 7zz child process. The child is signed with `com.apple.security.inherit` and only receives access through NanZip's private shared staging directory.

## Notarize

```sh
NANZIP_SIGN_IDENTITY="Developer ID Application: <DEVELOPER_NAME> (<TEAM_ID>)" \
NANZIP_NOTARY_PROFILE="nanzip-notary" \
  ./Scripts/notarize.sh
```

The script performs:

1. Deep strict signature verification.
2. ZIP creation with `ditto`.
3. `notarytool submit --wait` for the app archive.
4. DMG creation with `hdiutil`.
5. notarization and `stapler` for the DMG.
6. stapler validation and Gatekeeper assessment.

## Release checks

```sh
codesign -dvvv build/NanZip.app
codesign -d --entitlements :- build/NanZip.app
spctl --assess --type execute --verbose=4 build/NanZip.app
./Scripts/test-core.sh
```

Verify:

- Main app: App Sandbox, user-selected read/write, no unnecessary entitlements.
- XPC service: App Sandbox, user-selected read/write, only `/Users/Shared/NanZip/` staging exception.
- `7zz`: App Sandbox with inherit only.
- No developer identity, Team ID, Apple ID, mailbox address or user home path in tracked files.
- `NanZipXPCService` rejects a client not signed by the NanZip team and main-app identifier.
- Staging directories are removed after success, failure and cancellation.
- A real ZIP round trip succeeds after a fresh install from the notarized artifact.

## Current signing limitation

The local development environment may contain only an `Apple Development` identity. That is sufficient for local signing and XPC tests, but `Scripts/notarize.sh` intentionally refuses it. Developer ID issuance and Apple notary credentials are external release credentials and must be supplied by the project owner.
