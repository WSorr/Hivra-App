# Release Tools

This directory contains the single guarded packaging and publication path for
Hivra.

## Scripts

- `preflight.sh`: verifies pinned dependencies/toolchain, repository gates,
  Rust FFI tests, Flutter analysis/tests, and existing build artifacts.
- `macos_release.sh`: creates a versioned macOS ZIP, checksums, and source
  metadata from a clean checkout.
- `android_release.sh`: creates a versioned universal APK, checksums, and
  source metadata from a clean checkout.
- `workspace_runner.sh`: builds the standalone installed-WASM host candidate
  on Ubuntu 24.04 x86_64 with the pinned Dart/Rust toolchains. It includes the
  existing FFI library, one systemd unit, source metadata and archive digest.
  `--prepare-assets <CI-artifact-directory> <verified-archive-sha256>` embeds a
  verified canonical candidate for the same source tree into Flutter assets.
  `--verify-assets` checks that component; both app packagers verify its exact
  digest again inside their compiled artifact. Binary assets remain ignored by
  Git. Preparation does not rebuild the runner on macOS or Android.
  It neither installs a VPS nor publishes a release. Capsule provisioning and
  a tested state handoff are required before exposing remote Start to users.
- `derive_flutter_version.sh`: derives one monotonic cross-platform build
  number from the release tag.
- `check_manual_release_signoff.sh`: requires digest-bound macOS and Android
  signoff rows for the exact build tag. `test` releases require exact
  packaged Manual Smoke; User Lifetime may be `PENDING` with a reason in
  Notes. `public` releases require User Lifetime `PASS` on both platforms.
  Moltbook Smoke may be `PASS` or `N/A` when live provider or Gemini access is
  unavailable.
- `publish_github_release.sh`: the only approved GitHub Release publication
  path; binds tag, source commit, metadata, artifact digests, and signoff.

## Gate ownership

Each layer answers one question:

- `review_all.sh` and `release_discipline_gate.sh` check repository structure,
  wiring, and rule consistency. They do not prove a release artifact or a
  user journey.
- `preflight.sh` checks the pinned toolchain, source tests, analysis, review
  gates, and any already-built bundles. Missing local bundles are warnings so
  development checks can run before packaging.
- `macos_release.sh` and `android_release.sh` create exact platform bytes
  from a clean checkout and record their source commit, runner digest, and
  artifact digest.
- `release-manual-signoff-log.md` records behavior observed on those exact
  bytes. `test` accepts deferred User Lifetime evidence and Moltbook `N/A`
  with a reason; `public` requires User Lifetime `PASS` on both platforms.
- `publish_github_release.sh` is the final conjunction: clean tree, valid
  version sequence, tag binding, metadata binding, artifact digests, and
  channel-appropriate signoff. It does not repeat product testing.

## Flow

1. Obtain the next allowed tag with
   `tools/release/release_version_guard.sh --suggest`.
2. Run `tools/release/preflight.sh`.
3. Prepare the matching green-CI runner component, then build each platform once
   with its release script. The component is delivered inside Capsule, not as
   an extra installation step for its users.
4. Exercise those exact packaged bytes using the matching platform checklist.
   The full User Lifetime Safety Pack is mandatory for `public`; for an
   internal `test` release it may remain explicitly `PENDING`.
5. Record both rows in
   `docs/checklists/release-manual-signoff-log.md`.
6. Publish with `tools/release/publish_github_release.sh`.

Both packaging scripts reject a dirty tracked worktree, invalid sequencing,
channel mismatch, or an already published version. They expose no preflight or
build bypass. Packaging is not publication. Rebuilding or repackaging after
manual signoff invalidates that signoff.
