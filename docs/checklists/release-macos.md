# macOS Release Checklist

Use this checklist before publishing any macOS build to testers or end users.

Publishing is blocked until this checklist is reflected in
`docs/checklists/release-manual-signoff-log.md` and validated with:

```bash
tools/release/check_manual_release_signoff.sh --build-tag <version-tag> --platform macOS
```

## Build

- [ ] `main` contains the intended release commits.
- [ ] Tracked worktree and index are clean before packaging.
- [ ] `tools/release/preflight.sh` passes before packaging.
- [ ] `flutter build macos --release` succeeds.
- [ ] Release packaging used `tools/release/macos_release.sh` with explicit `--channel` (`test` or `public`).
- [ ] `libhivra_ffi.dylib` inside the app bundle is universal (`x86_64` + `arm64`).
- [ ] App bundle contains `Contents/Frameworks/libhivra_ffi.dylib`.

## Verification

- [ ] `codesign --verify --deep --strict` succeeds for the `.app`.
- [ ] `spctl --assess --type execute` result is recorded.
- [ ] Packaged ZIP artifact was unpacked and verified (app bundle integrity + universal `libhivra_ffi.dylib`) from the extracted `.app`, not only from build tree.
- [ ] Apple Silicon smoke launch was tested.
- [ ] Intel smoke launch was tested.
- [ ] App starts past first screen on a clean machine or clean user account.
- [ ] Existing-user update path was evaluated for truth preservation (same ledger -> same starters/relationships/pending state).
- [ ] Update build does not re-materialize previously resolved invitation history.
- [ ] Legacy container migration does not rehydrate deleted canonical capsule files on relaunch.
- [ ] Trading Drone smoke gate completed:
  - `situational` decision envelope hash captured
  - `interactive` parity hash verified
  - risk-block and retry paths exercised
  - execution envelope receipt hash captured
- [ ] Trading Drone evidence row recorded in `docs/checklists/trading-drone-evidence-log.md` (via `tools/release/record_trading_drone_evidence.sh`).
- [ ] Trading Drone evidence coverage validated for this build tag via `tools/release/check_trading_drone_evidence.sh --build-tag <version-tag>`.
- [ ] Trading drone spec/runtime parity checklist was completed (`docs/checklists/trading-drone-spec-runtime-parity.md`).
- [ ] AI Engineer release smoke checklist was completed (`docs/checklists/ai-engineer-release-smoke.md`).
- [ ] User Lifetime Safety Pack (`docs/checklists/user-lifetime-safety-pack.md`) was completed on this build.

## Packaging

- [ ] Release channel was selected intentionally:
  - `test` allows unsigned / non-notarized artifacts for internal testing only.
  - `public` requires signed + notarized artifacts.
- [ ] macOS signing capability scope is intentional:
  - `test` ad-hoc builds do not add certificate-only entitlements.
  - `public` signed builds validate Keychain-related capabilities with the signing identity.
- [ ] Capsule switching does not trigger a Keychain prompt storm:
  - two or more capsule switches complete without repeated password prompts.
  - system logs show no repeated `SecKeychainItemModifyAttributesAndData` for active-seed switching.
- [ ] Release asset name clearly indicates version and target.
- [ ] ZIP or DMG was rebuilt from the latest `.app`.
- [ ] `SHA256SUMS.txt` was regenerated.
- [ ] Release notes mention whether the build is signed/notarized or test-only.
- [ ] `RELEASE-METADATA.txt` was attached or copied into release notes for traceability.
- [ ] `RELEASE-METADATA.txt` records the source commit and `source_tree_dirty=no`.

## Publish

- [ ] Manual macOS signoff row was recorded in `docs/checklists/release-manual-signoff-log.md`.
- [ ] Manual macOS signoff was validated with `tools/release/check_manual_release_signoff.sh --build-tag <version-tag> --platform macOS`.
- [ ] Correct Git tag exists on the intended commit.
- [ ] GitHub publication used `tools/release/publish_github_release.sh` after both macOS and Android signoff rows existed.
- [ ] GitHub Release assets match the latest local artifacts.
- [ ] `Pre-release` flag is correct (`test` => pre-release, `public` => stable release).
- [ ] Tester instructions are included if the build is unsigned.
