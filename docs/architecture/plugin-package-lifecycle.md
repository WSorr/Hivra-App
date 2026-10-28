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
  -> atomically commit registry.json (removal first records pending cleanup)
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
- The application module returns any assigned VPS authority and restores its
  opaque checkpoint before activating a replacement. A transport failure keeps
  the previous registration and retained state available for retry.

## Remove

- The application module requires an authenticated VPS return and runner-removal
  acknowledgement before deregistration. It never treats an unreadable old grant
  as proof that remote authority has ended.
- Before cleanup, removal atomically marks the existing registry record as
  `removalPending`. This host-owned status denies runtime binding and replacement;
  it is not plugin-private state and does not create a second registry.
- With admission closed, the application module stops scheduling, drains admitted
  actions and clears Capsule-scoped secrets and private plugin state. Cleanup
  runs outside the registry mutation lock so final action checks can finish.
  Concurrent requests for the same removal share one in-process operation.
  The canonical effect journal and ended execution grant remain retained by
  their existing owners.
- Only successful cleanup removes the registry record and then its package file.
  A cleanup or final registry-write failure retains the non-executable pending
  record. After restart, the installed-package card offers **Retry removal**;
  retry uses the same removal path and skips completed VPS retirement.
- Pending cleanup survives missing package bytes and cannot be bypassed by
  installation or backup recovery. Backup export requires completed removals.
- The UI displays pending cleanup and a safe failure; it does not report success
  before the module completes or display raw provider/Keychain exceptions.

## Recovery

Every serialized load repairs the managed directory:

- active records whose package is missing are removed through an atomic registry
  rewrite; pending-removal records retain their cleanup obligation;
- duplicate `plugin_id` records retain one active package;
- unreferenced `.wasm`, `.zip`, and atomic temporary files are deleted;
- malformed registry state fails closed for mutations and is never replaced by
  an apparently empty successful transaction.

This recovery is idempotent. Package or temporary-file cleanup may be retried
after restart without changing the committed registry result.

A lost VPS return acknowledgement can outlive a package update. The host may
read an old grant only for authenticated retirement; that does not admit package
execution. If the server rebound an ended grant to new package bytes, accepting
its return also requires the original handoff identity and the stored immutable
checkpoint digest. Opaque workspace state and effect evidence are restored
without interpreting plugin-private fields, and the local grant remains ended.

## Failure Invariants

| Failure point | Durable result |
| --- | --- |
| Before package staging | Previous registry and packages remain unchanged |
| During staging or preflight | Candidate is absent or recoverable as an orphan; previous registration remains active |
| Catalog metadata rejection | Candidate is removed; previous active version remains active |
| Registry commit failure | Previous registry and packages remain active |
| Interruption after install/update commit | New record and package are active; superseded package may remain as a recoverable orphan |
| Removal intent cannot be committed | Previous active record and package remain; cleanup has not started |
| Cleanup fails or is interrupted | Pending record denies execution and remains available for retry after restart |
| Final removal commit fails | Cleaned record remains pending and can be retried idempotently |
| Interruption after final remove commit | Record stays removed; old package may remain as a recoverable orphan |

## Architecture Constraints

- No plugin package lifecycle writes the Core ledger.
- No source catalog, screen, or runtime service owns a parallel registry path.
- Package DTOs remain the existing `WasmPluginRecord`; this lifecycle adds no
  shadow registry or transaction DTO.
- Plugin implementation source and release artifacts remain owned by the
  `hivra-plugins` repository.
