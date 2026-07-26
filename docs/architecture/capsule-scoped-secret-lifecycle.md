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

The vault does not interpret provider credentials or expose them to UI. A
provider-specific connection service may request one exact secret only after
capturing the active Capsule root.
