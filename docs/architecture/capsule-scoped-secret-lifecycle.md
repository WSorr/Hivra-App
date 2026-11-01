# Capsule-Scoped Secret Lifecycle v1

Status: normative application-platform contract

## Ownership

`CapsuleScopedSecretVault` is the single application owner for secrets scoped
to an installed plugin or external provider. Provider adapters, screens,
Capsule files, plugin state, Core, ledger, and WASM must not persist these
secret values.

The scope is:

```text
Capsule root -> plugin id -> provider id -> external account id -> secret name
```

All scopes are stored in one versioned Secure Storage item. There is no
plaintext, Documents, backup, ledger, or plugin-state fallback.

The common plugin permission form can select an existing reference or accept a
new service token/key from the owner. It never asks for the device password.
New fields from one Allow decision are saved together through the same vault
writer. Their account identifiers are opaque local reference identities, not
host-validated external account facts. An optional owner label is display
metadata; existing entries without labels retain their original references.

The form holds new values only in memory. Cancel writes nothing. A failed
native write produces no references and no execution grant. Saving a secret
does not itself authorize a package: the existing owner/package-bound grant
must still be issued. If grant creation subsequently fails or the Capsule or
package changes, a completed native write may remain scoped to the original
owner; it never authorizes the new selection. Canonical plugin removal still
cleans that plugin's vault entries.

## Lifecycle

- Save and replacement are serialized through one process-wide vault owner.
- A malformed stored vault fails closed and is never replaced with defaults.
- Deleting a Capsule removes every secret under its root before local Capsule
  artifacts and seed are removed.
- Removing a plugin removes that plugin's secrets across every Capsule before
  plugin state and package registration are removed.
- Provider disconnect removes the external account scope before local
  connection metadata is removed.
- A failed secure-storage cleanup aborts the destructive parent action; secret
  orphaning is not reported as successful deletion.

The vault does not interpret provider credentials or return stored values to UI. A
provider-specific connection service may request one exact secret only after
capturing the active Capsule root.
