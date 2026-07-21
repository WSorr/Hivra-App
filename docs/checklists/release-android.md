# Android Release Checklist

Use this checklist before publishing Android builds to testers or end users.

Publishing is blocked until this checklist is reflected in
`docs/checklists/release-manual-signoff-log.md` and validated with:

```bash
tools/release/check_manual_release_signoff.sh --build-tag <version-tag> --platform Android
```

## Build

- [ ] `tools/release/preflight.sh` passes before packaging.
- [ ] Tracked worktree and index are clean before packaging.
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
- [ ] Trading Drone smoke gate completed:
  - `situational` decision envelope hash captured
  - `interactive` parity hash verified
  - risk-block and retry paths exercised
  - execution envelope receipt hash captured
- [ ] Trading Drone evidence row recorded in `docs/checklists/trading-drone-evidence-log.md` (via `tools/release/record_trading_drone_evidence.sh`).
- [ ] Trading Drone evidence coverage validated for this build tag via `tools/release/check_trading_drone_evidence.sh --build-tag <version-tag>`.
- [ ] Trading drone spec/runtime parity checklist was completed (`docs/checklists/trading-drone-spec-runtime-parity.md`).
- [ ] User Lifetime Safety Pack (`docs/checklists/user-lifetime-safety-pack.md`) was completed on this build.

## Diagnostics

- [ ] Outbound transport failure path was exercised and produces actionable diagnostics.
- [ ] Android keystore-backed seed storage behavior was validated on restart.

## Publish

- [ ] Manual Android signoff row was recorded in `docs/checklists/release-manual-signoff-log.md`.
- [ ] Manual Android signoff was validated with `tools/release/check_manual_release_signoff.sh --build-tag <version-tag> --platform Android`.
- [ ] GitHub publication used `tools/release/publish_github_release.sh` after both macOS and Android signoff rows existed.
- [ ] Release asset name clearly indicates version and target.
- [ ] Checksums were generated for published APK assets.
- [ ] `RELEASE-METADATA.txt` was generated and kept with release artifacts.
- [ ] `RELEASE-METADATA.txt` records the source commit and `source_tree_dirty=no`.
- [ ] Release notes mention testing scope and known Android limitations, if any.
- [ ] GitHub Release `Pre-release` flag matches channel (`test` => pre-release, `public` => stable release).
