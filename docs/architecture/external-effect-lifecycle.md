# External Effect Lifecycle v1

External service effects use one common capability dispatch path. The owner
provides permission, an isolated package chooses requests and interprets service
responses, and the host enforces the active package/grant and applies secrets at
network dispatch. The wire contract is
[`plugin_host_api_v1.md`](../plugins/plugin_host_api_v1.md).

The former `ExternalEffectService` journal/controller and its approval DTOs were
removed with the Moltbook migration. They are not a second lifecycle for common
HTTP requests. Service facts do not become Core or Ledger facts. Necessary
irrecoverable decisions may use a package's optional opaque store; a stateless
package reconstructs its observations from its service.

The host distinguishes non-dispatch, uncertain transport and an HTTP response,
never silently retries, and does not interpret HTTP acceptance as product
success. Package receipt/verification/reconciliation semantics belong to the
package; Moltbook's current contract is
[`moltbook_engagement_lifecycle_v1.md`](../plugins/moltbook_engagement_lifecycle_v1.md).
Revocation cannot undo an already admitted service request. Exactly-once delivery
is not promised without a service protocol that establishes it.

Transport delivery and signed Capsule history retain their existing independent
owners. Generic backup/custody may preserve legacy opaque effect bytes; it does
not execute or reinterpret the retired journal.
