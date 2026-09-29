# Android Release Checklist

Use this checklist before publishing Android builds to testers or end users.

Publishing is blocked until this checklist is reflected in
`docs/checklists/release-manual-signoff-log.md` and validated with:

```bash
tools/release/check_manual_release_signoff.sh --build-tag <version-tag> --platform Android --channel <test|public>
```

## Build

- [ ] `tools/toolchain/verify_environment.sh --full` passes against the checked-in baseline.
- [ ] `tools/release/preflight.sh` passes before packaging; this validates the
      repository and build environment, not packaged manual signoff.
- [ ] Tracked worktree and index are clean before packaging.
- [ ] `tools/release/android_release.sh --version <version> --channel <test|public>` is used for packaging.
- [ ] `--channel` was chosen explicitly (`test` for internal/pre-release, `public` for stable release).
- [ ] Android build includes Rust FFI artifacts from the current source state.
- [ ] Release APK was built from the intended commit.

## Verification

- [ ] APK installs on a clean Android device.
- [ ] APK install verification used the packaged release artifact (not only a local debug/build-tree install).
- [ ] The published APK is the exact artifact used for smoke; a rebuild requires a new digest-bound smoke/signoff.
- [ ] App launches and reaches first interactive screen.
- [ ] Create or recover capsule path succeeds.
- [ ] Invitation send succeeds.
- [ ] Invitation accept succeeds.
- [ ] Backup/recovery entry path is reachable and operational.
- [ ] Moltbook release smoke checklist was completed (`docs/checklists/moltbook-release-smoke.md`).
- [ ] User Lifetime Safety Pack (`docs/checklists/user-lifetime-safety-pack.md`) was completed on this build.

## Diagnostics

- [ ] Outbound transport failure path was exercised and produces actionable diagnostics.
- [ ] Android keystore-backed seed storage behavior was validated on restart.

## Publish

- [ ] Manual Android signoff row was recorded in `docs/checklists/release-manual-signoff-log.md`.
- [ ] Manual Android signoff was validated with `tools/release/check_manual_release_signoff.sh --build-tag <version-tag> --platform Android --channel <test|public>`.
- [ ] GitHub publication used `tools/release/publish_github_release.sh` after both macOS and Android signoff rows existed.
- [ ] Release asset name clearly indicates version and target.
- [ ] Checksums were generated for published APK assets.
- [ ] `RELEASE-METADATA.txt` was generated and kept with release artifacts.
- [ ] `RELEASE-METADATA.txt` records the source commit and `source_tree_dirty=no`.
- [ ] Release notes mention testing scope and known Android limitations, if any.
- [ ] GitHub Release `Pre-release` flag matches channel (`test` => pre-release, `public` => stable release).
