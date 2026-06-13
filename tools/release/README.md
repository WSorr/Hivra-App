# Release Tools

This directory contains deterministic release helpers for Hivra.

## Scripts

- `preflight.sh`
  - Runs review gates, tests, analyze, and artifact sanity checks.
  - Optional evidence coverage check:
    - `tools/release/preflight.sh --trading-evidence-build-tag <version-tag>`

- `macos_release.sh`
  - Channel-aware macOS packaging (`test` / `public`).
  - Produces ZIP + `SHA256SUMS.txt` + `RELEASE-METADATA.txt`.
  - Optional evidence forwarding to preflight:
    - `tools/release/macos_release.sh --version <v> --channel <test|public> --trading-evidence-build-tag <v>`

- `android_release.sh`
  - Channel-aware Android packaging (`test` / `public`).
  - Produces APK + `SHA256SUMS.txt` + `RELEASE-METADATA.txt`.
  - Optional evidence forwarding to preflight:
    - `tools/release/android_release.sh --version <v> --channel <test|public> --trading-evidence-build-tag <v>`

- `record_trading_drone_evidence.sh`
  - Appends one build-tagged evidence row to:
    - `docs/checklists/trading-drone-evidence-log.md`

- `check_trading_drone_evidence.sh`
  - Verifies required coverage for one build tag:
    - macOS `situational` + `interactive`
    - Android `situational` + `interactive`
    - at least one `risk_blocked`
    - non-empty decision/execution hashes

## Typical Flow

1. Ask the repository guard for the next test tag:
   - `tools/release/release_version_guard.sh --suggest`
   - The guard reads published releases from `WSorr/Hivra-App`; it deliberately
     ignores legacy local tags.
2. Record rows during manual smoke:
   - `tools/release/record_trading_drone_evidence.sh ...`
3. Validate coverage:
   - `tools/release/check_trading_drone_evidence.sh --build-tag <version-tag>`
4. Run preflight with strict evidence gate:
   - `tools/release/preflight.sh --trading-evidence-build-tag <version-tag>`
5. Build channel release:
   - `tools/release/macos_release.sh ...`
   - `tools/release/android_release.sh ...`

Both packaging scripts reject a version that belongs to another major release
line, already exists on GitHub, conflicts with a remote tag, or does not match
the selected channel.
