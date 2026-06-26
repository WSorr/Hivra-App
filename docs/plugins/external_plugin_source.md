# External Plugin Source (Separate Repo)

This project now supports loading plugin packages from an external source catalog.

## Repository boundary contract (mandatory)

- `Hivra-App` repository is host/runtime only.
- WASM plugin implementation source and plugin package release flow belong to `hivra-plugins` repository.
- `Hivra-App` may contain plugin host API/contracts and UI install/run projections, but must not become a second plugin-source repository.
- New plugin logic must be implemented and released from `hivra-plugins`, then installed into capsule through source catalog.

## Runtime behavior

- Local source catalog path, used first when present:
  - `~/Documents/Hivra/Plugins/plugin_catalog.json`
- Published source catalog URL:
  - `https://raw.githubusercontent.com/WSorr/hivra-plugins/main/catalog/plugin_catalog.json`

If a local catalog exists, app uses it as the explicit user/developer source.
If it does not exist, app loads the published source catalog. If published
sources are not reachable (for example private GitHub repo), app falls back to
the local catalog path and surfaces a clear error if it is missing too.

## Integrity checks

- Remote HTTP/HTTPS source catalogs are accepted only through an independent
  trust root in `Hivra-App`:
  - preferred path: Ed25519 catalog signature verified against a pinned public
    key,
  - compatibility path: full JSON body SHA256 matches a digest pinned in
    `Hivra-App`.
- Catalog trust is evaluated before per-package checksums are trusted.
- Local `file://` catalogs are treated as explicit user/developer overrides and
  are not remote-trust pinned.
- Signed catalogs use a top-level `signatures` array. Each signature covers the
  canonical JSON form of the catalog with `signatures` removed.
- Source catalog entries can include optional `sha256_hex`.
- If `sha256_hex` is present, Hivra verifies package bytes before install.
- Invalid hash shape in catalog (`not 64 hex chars`) is rejected.
- Hash mismatch blocks installation.
- Installed package metadata must match catalog entry (`plugin_id`, `package_kind`, and `version` when package version is available); mismatch triggers install rollback.
- Zip manifests must declare strict runtime contract:
  - non-empty `contract.kind`
  - non-empty `capabilities` list
  - `runtime.abi = hivra_host_abi_v2`
  - `runtime.entry_export = hivra_evaluate_v1`
  - optional `runtime.module_path = <path/to/module.wasm>` for explicit module selection
- Missing contract or capability metadata is rejected. Legacy compatibility must
  be handled by reinstalling a current package, never by bypassing permissions.

## Local private-repo workflow

Use:

```bash
./tools/plugins/sync_external_plugins_to_documents.sh
```

This script:

1. Builds plugin zip packages in sibling repo `../hivra-plugins`
2. Copies zip packages to `~/Documents/Hivra/Plugins/source`
3. Generates `~/Documents/Hivra/Plugins/plugin_catalog.json` with `file://` URLs and per-package `sha256_hex`

Then open `WASM Plugins` screen and install from `Source Catalog`.

## Release readiness

Package installation and semantic execution use the deterministic ABI v2
JSON-in/JSON-out boundary. The Rust runtime is import-free, fuel-bounded and
size-bounded. The host validates package/module digests, manifest grants,
canonical output identity and output hash before consuming plugin results.
