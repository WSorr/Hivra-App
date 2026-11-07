# Hivra Flutter App

Flutter client for Hivra Protocol v1.0.

## Capsule UX Rules

### First Launch

- With verified empty storage, offer Capsule creation or explicit recovery.
- Unavailable/corrupt storage offers retry/recovery; it is not a new installation.
- Existing Capsules use the selector; a single Capsule may activate automatically.

### Capsule Selection Screen

- Show capsule public key, network, and starter count.
- Allow creating a new capsule.
- Allow selecting an existing capsule.

### Multi-Capsule Management

- Multiple capsules are supported.
- Capsules are independent (separate seed and ledger).
- Switching can happen at any time.
- On switch, load selected capsule state and unload previous capsule from memory.

## Run (macOS)

```bash
cd flutter
flutter pub get
flutter run -d macos
```

## Notes

- Maintained release targets are macOS and Android. Exact toolchains and
  acceptance limits belong to `../toolchains/hivra-baseline.conf` and
  `../docs/development-control.md`.
- iOS project files do not establish a supported release/acceptance target.
- Source runs are development checks, not exact packaged release evidence.
