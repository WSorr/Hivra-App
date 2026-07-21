# Release Tools

This directory contains deterministic release helpers for Hivra.

## Scripts

- `preflight.sh`
  - Runs review gates, tests, analyze, and artifact sanity checks.
  - Requires evidence coverage for the exact release tag:
    - `tools/release/preflight.sh --trading-evidence-build-tag <version-tag>`

- `macos_release.sh`
  - Channel-aware macOS packaging (`test` / `public`).
  - Produces ZIP + `SHA256SUMS.txt` + `RELEASE-METADATA.txt`.
  - Always runs preflight and a fresh versioned build.
  - Requires a clean tracked worktree and records the source commit in release
    metadata.
  - Derives the embedded Flutter build name/number from `--version`.
    - `tools/release/macos_release.sh --version <v> --channel <test|public>`

- `android_release.sh`
  - Channel-aware Android packaging (`test` / `public`).
  - Produces APK + `SHA256SUMS.txt` + `RELEASE-METADATA.txt`.
  - Always runs preflight and a fresh versioned build.
  - Requires a clean tracked worktree and records the source commit in release
    metadata.
  - Derives the embedded Flutter build name/number from `--version`.
    - `tools/release/android_release.sh --version <v> --channel <test|public>`

- `record_trading_drone_evidence.sh`
  - Appends one build-tagged evidence row to:
    - `docs/checklists/trading-drone-evidence-log.md`

- `check_trading_drone_evidence.sh`
  - Verifies required coverage for one build tag:
    - macOS `situational` + `interactive`
    - Android `situational` + `interactive`
    - at least one `risk_blocked`
    - non-empty decision/execution hashes

- `check_manual_release_signoff.sh`
  - Verifies the canonical manual signoff log for one build tag.
  - GitHub publication requires signed-off rows for both macOS and Android.
    - `tools/release/check_manual_release_signoff.sh --build-tag <version-tag> --platform all`

- `publish_github_release.sh`
  - The only approved GitHub Release publication path.
  - Runs preflight, validates manual signoff, verifies artifacts, and creates the
    GitHub Release.
  - Requires the release tag to point at the current clean checkout and refuses
    artifacts whose metadata was not built from that commit.
    - `tools/release/publish_github_release.sh --version <v> --channel <test|public>`

## Typical Flow

1. Ask the repository guard for the next test tag:
   - `tools/release/release_version_guard.sh --suggest`
   - The guard reads published releases from `WSorr/Hivra-App`; it deliberately
     ignores legacy local tags.
   - Test releases are strictly sequential: if the guard suggests `test9`,
     packaging rejects `test10` or any other skipped number.
2. Record trading-drone parity evidence rows during smoke or deterministic
   fixture verification:
   - `tools/release/record_trading_drone_evidence.sh ...`
3. Validate coverage:
   - `tools/release/check_trading_drone_evidence.sh --build-tag <version-tag>`
4. Run preflight with strict evidence gate:
   - `tools/release/preflight.sh --trading-evidence-build-tag <version-tag>`
5. Build channel release:
   - `tools/release/macos_release.sh ...`
   - `tools/release/android_release.sh ...`
6. Manually install/launch the packaged artifacts and complete platform
   checklists:
   - `docs/checklists/release-macos.md`
   - `docs/checklists/release-android.md`
7. Record manual signoff rows:
   - `docs/checklists/release-manual-signoff-log.md`
8. Publish through the guarded GitHub release script:
   - `tools/release/publish_github_release.sh --version <v> --channel <test|public>`

Both packaging scripts reject a dirty tracked worktree, a version that belongs to
another major release line, already exists on GitHub, conflicts with a remote
tag, or does not match the selected channel. They do not expose
preflight/build bypass flags.

Packaging is not publication. Publishing to GitHub is blocked until the manual
signoff checker passes for both macOS and Android. Deterministic fixture rows in
`docs/checklists/trading-drone-evidence-log.md` are not a manual signoff.

Release remains blocked while the trading-drone parity table contains any
status other than `DONE`. Plugin-owned execution requires the bounded semantic
ABI v2 runtime; package presence or entry-probe evidence alone is insufficient.
