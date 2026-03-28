# Android Release Checklist

Use this checklist before publishing Android builds to testers or end users.

## Build

- [ ] `tools/release/preflight.sh` passes before packaging.
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

## Diagnostics

- [ ] Outbound transport failure path was exercised and produces actionable diagnostics.
- [ ] Android keystore-backed seed storage behavior was validated on restart.

## Publish

- [ ] Release asset name clearly indicates version and target.
- [ ] Checksums were generated for published APK assets.
- [ ] Release notes mention testing scope and known Android limitations, if any.
