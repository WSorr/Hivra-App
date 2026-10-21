# Hivra Documentation Map

Documentation has one owner per fact. Read only the current status, the
development rules, the three laws, and the contract for the capability being
changed. Historical evidence never authorizes a new implementation path.

## Read Order

1. `development-control.md` for current state, change rules, validation order,
   and the selected product outcome.
2. `product-axis.md` for the permanent Person-First Runtime laws.
3. `specification.md` for maintained 1.x protocol behavior.
4. The focused contract for the capability being changed.
5. The matching checklist for release, smoke, migration, or security evidence.

Do not start from a historical evidence row, a generated report, a research
note, or the V2 blueprint when changing maintained 1.x behavior.

## Canon

| Concern | Owner |
| --- | --- |
| Current state and next decision | `development-control.md` |
| Development rules and change workflow | `development-control.md` |
| Person-First Runtime and the three laws | `product-axis.md` |
| Maintained 1.x protocol | `specification.md` |
| Design-only V2 contracts and migration | `architecture-v2-blueprint.md` |
| Product terminology | `hivra-conceptual-model.md` |
| Milestone index and retained debt | `roadmap.md` |

`roadmap.md` is not a backlog. Git, merged pull requests, releases, tests, and
evidence logs retain detailed history.

## Document Status

| Status | Meaning | May authorize implementation? |
| --- | --- | --- |
| Canon | Current product, protocol, or development rule | Yes, within its scope |
| Contract | Focused architecture or capability boundary | Yes, within its scope |
| Checklist | Verification procedure and evidence shape | No; it verifies a contract |
| Evidence | A completed test, smoke, release, or migration record | No; it proves only the recorded result |
| Design-only | V2 or an explicitly unactivated proposal | No |
| Research | External patterns and options | No |

When a fact changes, update its owner and any directly affected checklist in
the same bounded change. Do not copy the fact into a diary, capability note, or
release row to make it current.

## Runtime Contracts

| Capability | Owner |
| --- | --- |
| Transport delivery and receipts | `architecture/transport-delivery-lifecycle.md` |
| External effects | `architecture/external-effect-lifecycle.md` |
| Plugin installation, replacement and removal recovery | `architecture/plugin-package-lifecycle.md` |
| Plugin host API | `plugins/plugin_host_api_v1.md` |
| Capsule-scoped secrets | `architecture/capsule-scoped-secret-lifecycle.md` |
| Capsule AI Runtime | `architecture/capsule-ai-runtime.md` |
| AI proposal boundary | `architecture/ai-proposal-boundary.md` |
| Continuous Ledger v5 | `architecture/continuous-ledger-protocol-v5.md` |
| Identity migration | `identity-decoupling-migration.md` |
| Capsule addressing | `capsule-addressing-model.md` |
| Android seed migration | `android-keystore-migration.md` |
| Toolchain evolution | `docs/platform-toolchain-evolution.md` |

The generated ownership report is
`generated/architecture-ownership-baseline.md`; its source is
`../architecture/ownership-registry.v1.json`.

## Product Capabilities

| Capability | Owner |
| --- | --- |
| Chat deterministic contract | `plugins/plugin_host_api_v1.md` |
| Chat delivery and durable handoff | `architecture/transport-delivery-lifecycle.md` |
| Moltbook | `plugins/moltbook_agent_drone_design_v1.md` |
| Moltbook engagement, public visibility and result completion | `plugins/moltbook_engagement_lifecycle_v1.md` |
| External plugin source, canonical identity and replacement boundary | `plugins/external_plugin_source.md` |

Moltbook still contains historical implementation material. It is consolidated
only when its product capability migrates out of the Flutter host; no separate
documentation project is authorized.

## Verification

Checklists and generated evidence verify contracts; they do not create product
requirements or current status. Use only the checklist matching the changed
risk under `checklists/`.

Every implementation pass must leave a traceable chain:

`current state -> owner/contract -> code change -> focused tests -> review gates -> exact packaged smoke`

Stop at the last step required by the change. A green gate without the user
journey it is meant to protect is incomplete evidence.

Research under `research/` and `external-agent-runtime-pattern-audit.md` is
non-authorizing input.
