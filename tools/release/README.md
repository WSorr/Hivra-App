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

1. Record rows during manual smoke:
   - `tools/release/record_trading_drone_evidence.sh ...`
2. Validate coverage:
   - `tools/release/check_trading_drone_evidence.sh --build-tag <version-tag>`
3. Run preflight with strict evidence gate:
   - `tools/release/preflight.sh --trading-evidence-build-tag <version-tag>`
4. Build channel release:
   - `tools/release/macos_release.sh ...`
   - `tools/release/android_release.sh ...`
