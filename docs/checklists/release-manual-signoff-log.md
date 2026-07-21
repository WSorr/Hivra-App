# Release Manual Signoff Log

This log is the canonical proof that packaged release artifacts were manually
exercised before GitHub publication.

Automated preflight, deterministic fixtures, and trading-drone evidence rows do
not satisfy this log. Add a row only after installing or launching the packaged
artifact for that exact platform and completing the platform release checklist.

Required status values:

- `PASS`: gate was manually completed for this exact build tag and artifact.
- `N/A`: gate is intentionally not applicable to this platform.

For publication, macOS and Android must each have one row for the build tag.
`Manual Smoke`, `Trading Smoke`, and `User Lifetime` must be `PASS` on both
platforms. `AI Engineer` must be `PASS` for macOS and may be `PASS` or `N/A` for
Android.

| Build Tag | Date (UTC) | Platform | Artifact | Manual Smoke | Trading Smoke | User Lifetime | AI Engineer | Signer | Notes |
|---|---|---|---|---|---|---|---|---|---|
| v1.0.3-test12 | 2026-07-16T14:56:13Z | macOS | hivra_app-v1.0.3-test12-macos-universal.zip | PASS | PASS | PASS | PASS | codex | Packaged ZIP launch smoke passed from extracted artifact; current-session trading/plugin smoke covered BingX 0.2.3 install path and macOS reopen fix. Unsigned/not notarized test build. |
| v1.0.3-test12 | 2026-07-16T14:56:13Z | Android | hivra_app-v1.0.3-test12-android-universal.apk | PASS | PASS | PASS | N/A | codex | Packaged APK installed and launched on connected device irobusydx49dvckf; current-session transport/plugin smoke covered Android release path. |
| v1.0.3-test13 | 2026-07-21T19:48:21Z | macOS | hivra_app-v1.0.3-test13-macos-universal.zip | PASS | PASS | PASS | PASS | codex + user | Packaged ZIP launched from a fresh temporary extraction. Capsule selection, invitation flow, pair-attested chat, external plugins, AI Engineer, and live BingX trading/tracking were exercised. Unsigned/not notarized test build. |
| v1.0.3-test13 | 2026-07-22T00:58:24Z | Android | hivra_app-v1.0.3-test13-android-universal.apk | PASS | PASS | PASS | N/A | codex + user | Exact APK 100000313 installed after backup restore. Capsule bootstrap, invitation send/receive without manual Refresh, external plugin installation, pair attestation recovery, and chat send/receive were exercised. Unsigned test build. |
