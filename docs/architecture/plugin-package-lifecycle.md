# Plugin Package Lifecycle v1

Status: normative application-platform contract

## Ownership

`WasmPluginRegistryService` is the sole lifecycle owner for the local plugin
registry and its managed `.wasm` and `.zip` package files. Source catalogs may
download packages and validate catalog metadata, but they do not mutate the
registry or implement rollback. Screens and plugin runtime modules call the
same registry owner.

Plugin registration is application-platform state. It is isolated from the
Capsule Core ledger and does not create domain facts.

## Canonical Transaction

Every load, install, update, and remove operation enters one process-wide
serialized lifecycle:

```text
intent
  -> registry lifecycle lock
  -> read and repair current registry
  -> stage package and run package preflight
  -> run optional source-catalog metadata validation
  -> atomically commit registry.json
  -> remove superseded or unregistered files
  -> result
```

The atomic registry replacement is the commit point. Cleanup after that point
is recovery work and cannot roll back or invalidate the committed record.

## Install And Update

- The existing registry is read before a candidate package is staged.
- Preflight inspects the staged bytes that would become active.
- Source-catalog identity, version, and package-kind validation runs before the
  registry commit.
- A failed preflight, validation, or registry write removes only the staged
  candidate and preserves the previous active record and package.
- An update atomically replaces the active record for the same `plugin_id`.
  Superseded package deletion occurs only after the new registry is durable.

## Remove

- Capsule-scoped secret and plugin-state cleanup remains owned by the
  application module and must complete before package deregistration.
- Package removal first commits the registry without the selected record.
- Physical package deletion follows the commit. An interruption can leave an
  orphaned file, but never a registry pointer to a deliberately deleted file.

## Recovery

Every serialized load repairs the managed directory:

- records whose package is missing are removed through an atomic registry
  rewrite;
- duplicate `plugin_id` records retain one active package;
- unreferenced `.wasm`, `.zip`, and atomic temporary files are deleted;
- malformed registry state fails closed for mutations and is never replaced by
  an apparently empty successful transaction.

This recovery is idempotent. Package or temporary-file cleanup may be retried
after restart without changing the committed registry result.

## Failure Invariants

| Failure point | Durable result |
| --- | --- |
| Before package staging | Previous registry and packages remain unchanged |
| During staging or preflight | Candidate is absent or recoverable as an orphan; previous registration remains active |
| Catalog metadata rejection | Candidate is removed; previous active version remains active |
| Registry commit failure | Previous registry and packages remain active |
| Interruption after install/update commit | New record and package are active; superseded package may remain as a recoverable orphan |
| Interruption after remove commit | Record stays removed; old package may remain as a recoverable orphan |

## Architecture Constraints

- No plugin package lifecycle writes the Core ledger.
- No source catalog, screen, or runtime service owns a parallel registry path.
- Package DTOs remain the existing `WasmPluginRecord`; this lifecycle adds no
  shadow registry or transaction DTO.
- Plugin implementation source and release artifacts remain owned by the
  `hivra-plugins` repository.
