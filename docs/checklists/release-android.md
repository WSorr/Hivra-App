# Android Release Checklist

Use this checklist before publishing Android builds to testers or end users.

## Build

- [ ] `tools/release/preflight.sh` passes before packaging.
- [ ] `tools/release/android_release.sh --version <version> --channel <test|public>` is used for packaging.
- [ ] `--channel` was chosen explicitly (`test` for internal/pre-release, `public` for stable release).
- [ ] Android build includes Rust FFI artifacts from the current source state.
- [ ] Release APK was built from the intended commit.

## Verification

- [ ] APK installs on a clean Android device.
- [ ] APK install verification used the packaged release artifact (not only a local debug/build-tree install).
- [ ] App launches and reaches first interactive screen.
- [ ] Create or recover capsule path succeeds.
- [ ] Invitation send succeeds.
- [ ] Invitation accept succeeds.
- [ ] Backup/recovery entry path is reachable and operational.
- [ ] User Lifetime Safety Pack (`docs/checklists/user-lifetime-safety-pack.md`) was completed on this build.

## Diagnostics

- [ ] Outbound transport failure path was exercised and produces actionable diagnostics.
- [ ] Android keystore-backed seed storage behavior was validated on restart.

## Publish

- [ ] Release asset name clearly indicates version and target.
- [ ] Checksums were generated for published APK assets.
- [ ] `RELEASE-METADATA.txt` was generated and kept with release artifacts.
- [ ] Release notes mention testing scope and known Android limitations, if any.
- [ ] GitHub Release `Pre-release` flag matches channel (`test` => pre-release, `public` => stable release).
