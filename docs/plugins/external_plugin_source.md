# External Plugin Source (Separate Repo)

This project now supports loading plugin packages from an external source catalog.

## Runtime behavior

- Primary source catalog URL:
  - `https://raw.githubusercontent.com/WSorr/hivra-plugins/main/catalog/plugin_catalog.json`
- Local fallback catalog path:
  - `~/Documents/Hivra/Plugins/plugin_catalog.json`

If the remote source is not reachable (for example private GitHub repo), app falls back to local catalog automatically.

## Integrity checks

- Source catalog entries can include optional `sha256_hex`.
- If `sha256_hex` is present, Hivra verifies package bytes before install.
- Invalid hash shape in catalog (`not 64 hex chars`) is rejected.
- Hash mismatch blocks installation.
- Installed package metadata must match catalog entry (`plugin_id`, `package_kind`, and `version` when package version is available); mismatch triggers install rollback.
- Zip manifests must declare strict runtime contract:
  - `runtime.abi = hivra_host_abi_v1`
  - `runtime.entry_export = hivra_entry_v1`
  - optional `runtime.module_path = <path/to/module.wasm>` for explicit module selection

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
