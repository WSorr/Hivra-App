# macOS Release Checklist

Use this checklist before publishing any macOS build to testers or end users.

## Build

- [ ] `main` contains the intended release commits.
- [ ] `tools/release/preflight.sh` passes before packaging.
- [ ] `flutter build macos --release` succeeds.
- [ ] `libhivra_ffi.dylib` inside the app bundle is universal (`x86_64` + `arm64`).
- [ ] App bundle contains `Contents/Frameworks/libhivra_ffi.dylib`.

## Verification

- [ ] `codesign --verify --deep --strict` succeeds for the `.app`.
- [ ] `spctl --assess --type execute` result is recorded.
- [ ] Apple Silicon smoke launch was tested.
- [ ] Intel smoke launch was tested.
- [ ] App starts past first screen on a clean machine or clean user account.
- [ ] Existing-user update path was evaluated for truth preservation (same ledger -> same starters/relationships/pending state).
- [ ] Update build does not re-materialize previously resolved invitation history.

## Packaging

- [ ] Release asset name clearly indicates version and target.
- [ ] ZIP or DMG was rebuilt from the latest `.app`.
- [ ] `SHA256SUMS.txt` was regenerated.
- [ ] Release notes mention whether the build is signed/notarized or test-only.

## Publish

- [ ] Correct Git tag exists on the intended commit.
- [ ] GitHub Release assets match the latest local artifacts.
- [ ] `Pre-release` flag is correct.
- [ ] Tester instructions are included if the build is unsigned.
