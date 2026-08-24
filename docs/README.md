# Hivra Documentation Map

This file is navigation, not a specification, backlog, or status journal.
Start with the smallest reading set that owns the change.

## Authority Order

1. `development-control.md` selects the current work unit and records current
   product state.
2. `product-axis.md` defines the permanent product and engineering evaluation
   axis.
3. `specification.md` is normative for the maintained Hivra 1.x runtime.
4. The focused architecture or plugin contract owns its bounded capability.
5. Tests, generated evidence, and checklists verify the contract; they do not
   create a second source of truth.

`architecture-v2-blueprint.md` is design-only. It does not authorize 1.x
runtime behavior. `roadmap.md` is a frozen historical archive, not an active
backlog or completion source.

## Default Reading Set

For ordinary Hivra 1.x work, read no more than:

1. `../AGENTS.md`
2. `development-control.md`
3. `product-axis.md`
4. one owning contract from the tables below
5. its focused tests or checklist

Read `hivra-conceptual-model.md` only for product-language context. Read
`roadmap.md` only when historical evidence is explicitly required.

## Canonical Documents

| Concern | Owner document |
| --- | --- |
| Current work, release line, and next boundary | `development-control.md` |
| Product direction and change scorecard | `product-axis.md` |
| Current 1.x protocol and runtime invariants | `specification.md` |
| Product terminology and user-facing model | `hivra-conceptual-model.md` |
| Architecture execution discipline | `architecture-execution-discipline.md` |
| Design-only Hivra 2.0 ownership and migration | `architecture-v2-blueprint.md` |
| Toolchain evolution | `docs/platform-toolchain-evolution.md` |
| Historical engineering record | `roadmap.md` |

## Architecture Contracts

| Capability | Owner document |
| --- | --- |
| Transport delivery and receipts | `architecture/transport-delivery-lifecycle.md` |
| Capsule-scoped secrets | `architecture/capsule-scoped-secret-lifecycle.md` |
| External effects | `architecture/external-effect-lifecycle.md` |
| AI proposal and authority boundary | `architecture/ai-proposal-boundary.md` |
| Shared inference runtime | `architecture/capsule-ai-runtime.md` |
| Plugin package lifecycle | `architecture/plugin-package-lifecycle.md` |
| Continuous Ledger v5 | `architecture/continuous-ledger-protocol-v5.md` |
| Root and transport identity migration | `identity-decoupling-migration.md` |
| Capsule cards and peer addressing | `capsule-addressing-model.md` |
| Android seed migration | `android-keystore-migration.md` |

The architecture ownership registry is
`../architecture/ownership-registry.v1.json`. Its generated, read-only report
is `generated/architecture-ownership-baseline.md`; update the registry or
generator, never the report by hand.

## Plugin Contracts

| Capability | Owner document |
| --- | --- |
| Trading decisions, market inputs, risk, and execution | `plugins/bingx_futures_trading_drone_spec_v1.md` |
| Trading product target and Remote Runner evolution | `plugins/bingx_futures_trading_drone_goal_contract_v1.md` |
| Moltbook capability and authority boundaries | `plugins/moltbook_agent_drone_design_v1.md` |
| Moltbook per-target engagement lifecycle | `plugins/moltbook_engagement_lifecycle_v1.md` |
| Plugin host ABI | `plugins/plugin_host_api_v1.md` |
| External plugin source | `plugins/external_plugin_source.md` |

The two trading documents and the two Moltbook documents currently have
distinct declared owners, but contain historical implementation material.
Consolidating them requires a dedicated semantic migration with gate and
reference updates; do not copy more status into them.

## Verification

Use only the checklist relevant to the selected risk:

| Risk | Checklist or evidence |
| --- | --- |
| Architecture and dependencies | `checklists/architecture-review.md` |
| General manual release smoke | `checklists/manual-smoke.md` |
| macOS or Android release | `checklists/release-macos.md`, `checklists/release-android.md` |
| Release signoff history | `checklists/release-manual-signoff-log.md` |
| User lifetime, restore, and update | `checklists/user-lifetime-safety-pack.md` |
| Transport health | `checklists/transport-health-policy.md` |
| Trading spec/runtime parity | `checklists/trading-drone-spec-runtime-parity.md` |
| Trading release evidence | `checklists/trading-drone-evidence-log.md` |
| Moltbook release smoke | `checklists/moltbook-release-smoke.md` |
| AI engineering release smoke | `checklists/ai-engineer-release-smoke.md` |

Unchecked reusable checklist boxes are templates, not active debt. Current
priority exists only in `development-control.md`.

## Research

Research records are non-authorizing inputs. They do not select implementation
work or change runtime contracts:

- `external-agent-runtime-pattern-audit.md`
- `research/trading-empirical-authority-pass.md`

## Update Rules

- Change a normative document only when its contract or invariant changes.
- Fixes that preserve the contract need code, regression evidence, and no
  documentation closure ceremony.
- Current status belongs only in `development-control.md`.
- Historical pass logs do not belong in normative contracts.
- One effect has one use case and one owner; adapters may differ, semantics may
  not.
- All tracked repository text is English. Spoken conversation is the only
  language-policy exception.
- A 2.0 design change cannot alter 1.x behavior without an explicitly approved
  migration unit.
