# Release Manual Signoff Log

This log is the canonical proof that packaged release artifacts were manually
exercised before GitHub publication.

Automated preflight, deterministic fixtures, and trading-drone evidence rows do
not satisfy this log. Add a row only after installing or launching the packaged
artifact for that exact platform and completing the platform release checklist.

Required status values:

- `PASS`: gate was manually completed for this exact build tag and artifact.
- `N/A`: gate is intentionally not applicable to this platform.

For publication, macOS and Android must each have one row for the build tag.
`Manual Smoke`, `Trading Smoke`, and `User Lifetime` must be `PASS` on both
platforms. `AI Engineer` must be `PASS` for macOS and may be `PASS` or `N/A` for
Android.

| Build Tag | Date (UTC) | Platform | Artifact | Manual Smoke | Trading Smoke | User Lifetime | AI Engineer | Signer | Notes |
|---|---|---|---|---|---|---|---|---|---|
