# Android Keystore Migration Note

## Goal

Replace the temporary Android app-private seed storage with a proper Android Keystore-backed implementation without breaking existing Android capsules.

## Current State

Current Android seed storage lives in:

- app-private files under `/data/user/0/com.hivra.hivra_app/files/hivra-keystore`
- fallback `/data/data/com.hivra.hivra_app/files/hivra-keystore`

This implementation was acceptable for Android bring-up, but it is not the target security model for a release-grade runtime.

## Target State

Keep the existing Rust keystore API unchanged:

- `store_seed`
- `load_seed`
- `delete_seed`
- `seed_exists`

Change only the Android backend implementation.

The target Android model is:

1. A wrapping key lives in Android Keystore.
2. Seed material is stored only as encrypted ciphertext in app-private storage.
3. The active capsule pointer remains explicit and migration-friendly.
4. Legacy plaintext file-backed seeds are migrated on first successful load.

## Design Constraints

### 1. No FFI API break

`hivra_seed_save`, `hivra_seed_load`, and related entrypoints should continue to work without signature changes.

### 2. No user-visible seed loss

Existing Android users who already created capsules with the temporary file-backed storage must keep working after upgrade.

### 3. Keep bootstrap behavior stable

Bootstrap should still behave like:

- load seed
- create capsule
- import ledger

The storage backend change must not alter ledger-first runtime reconstruction semantics.

### 4. Keep account model stable

The existing account-style naming remains useful:

- `ACTIVE_SEED_ACCOUNT`
- per-seed account derived from the seed hash

This should remain stable even if the actual encrypted payload format changes.

## Recommended Implementation Shape

### Kotlin / Android side

Implement Android-specific secure storage in Kotlin/Java using:

- `AndroidKeyStore`
- AES/GCM wrapping key
- app-private file storage for encrypted blobs

The Android platform layer should:

- create or load a keystore-wrapped symmetric key
- encrypt the 32-byte seed before writing to files
- decrypt ciphertext when loading
- delete ciphertext and keystore metadata when requested

### Rust side

Rust should keep only a thin JNI bridge:

- call Android helper to store/load/delete/check
- map Java/Kotlin failures into `hivra-keystore::Error`

Rust should not try to implement Android Keystore semantics itself.

## Migration Strategy

### Read path

`load_seed()` on Android should behave like:

1. Try the new keystore-backed encrypted format.
2. If not found, try the legacy plaintext file-backed format.
3. If legacy plaintext exists and loads successfully:
   - immediately migrate it into the new encrypted format
   - update the active seed pointer
   - delete the plaintext legacy file

### Write path

`store_seed()` should write only the new encrypted format.

### Delete path

`delete_seed()` should remove:

- new encrypted seed data
- active pointer metadata
- any legacy plaintext leftovers

## What Not To Do

- Do not change the public FFI keystore API just for Android migration.
- Do not mix this migration with transport refactors.
- Do not keep plaintext seed storage as a normal long-term fallback.
- Do not make upgrade depend on a manual user migration step.

## First Milestone

The first Android keystore milestone is complete when:

1. New Android installs store seeds only in keystore-backed encrypted form.
2. Existing Android installs migrate legacy plaintext seed storage automatically.
3. Capsule bootstrap still succeeds after restart.
4. Invitation send/accept flows still work after migration.
5. Reinstall/restart behavior remains diagnosable with the existing bootstrap diagnostics.

## Follow-Up Checks

After implementation, validate:

- fresh install create -> restart -> same capsule truth
- upgraded install migrate legacy seed -> restart -> same capsule truth
- backup/recovery still works
- active capsule switching still works
- Android release APK still launches and publishes events on a real device
