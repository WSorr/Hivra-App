# Hivra Documentation Map

Documentation has one owner per fact. Read only the current status, the three
laws, and the contract for the capability being changed.

## Canon

| Concern | Owner |
| --- | --- |
| Current state and next decision | `development-control.md` |
| Person-First Runtime and the three laws | `product-axis.md` |
| Maintained 1.x protocol | `specification.md` |
| Design-only V2 contracts and migration | `architecture-v2-blueprint.md` |
| Product terminology | `hivra-conceptual-model.md` |
| Milestone index and retained debt | `roadmap.md` |

`roadmap.md` is not a backlog. Git, merged pull requests, releases, tests, and
evidence logs retain detailed history.

## Runtime Contracts

| Capability | Owner |
| --- | --- |
| Transport delivery and receipts | `architecture/transport-delivery-lifecycle.md` |
| External effects | `architecture/external-effect-lifecycle.md` |
| Plugin package installation | `architecture/plugin-package-lifecycle.md` |
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
| Trading | `plugins/bingx_futures_trading_drone_spec_v1.md` |
| Moltbook | `plugins/moltbook_agent_drone_design_v1.md` |
| Moltbook engagement lifecycle | `plugins/moltbook_engagement_lifecycle_v1.md` |
| External plugin source boundary | `plugins/external_plugin_source.md` |

Trading and Moltbook still contain historical implementation material. They
are consolidated only when their product capability migrates out of the
Flutter host; no separate documentation project is authorized.

## Verification

Checklists and generated evidence verify contracts; they do not create product
requirements or current status. Use only the checklist matching the changed
risk under `checklists/`.

Research under `research/` and `external-agent-runtime-pattern-audit.md` is
non-authorizing input.
