# Moltbook Agent Drone Design v1

Moltbook is an installable stateless package using the common workspace API.
Its implemented workflow, service-history reconstruction, owner journey and
changed recovery guarantees have one owner:
[`moltbook_engagement_lifecycle_v1.md`](moltbook_engagement_lifecycle_v1.md).
The generic host's operations, permissions and resource bounds belong to
[`plugin_host_api_v1.md`](plugin_host_api_v1.md).

The former host-owned screen, controller, prompt adapter and local product
stores are retired. Extending the package's protocol, content selection or
private transient state must not require a new host adapter or named request.
