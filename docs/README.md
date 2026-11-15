# Hivra Project Map

Documentation has one owner per fact. Read only the current status, the
development rules, the three laws, and the contract for the capability being
changed. Historical evidence never authorizes a new implementation path.

## Read Order

1. `development-control.md` for current state, accepted debt boundaries, change
   rules, validation order and the selected product outcome.
2. `product-axis.md` for Person-First ownership, design basis and the three laws.
3. `specification.md` for maintained 1.x protocol behavior.
4. The focused contract for the capability being changed.
5. The matching checklist for release, smoke, migration, or security evidence.

Do not start from a historical evidence row, a generated report, a research
note, or the V2 blueprint when changing maintained 1.x behavior.

## Choose the Change Boundary

Start with the owner's action and observable result, then follow one route
below. Package strategy, service parsing and private state belong in
`hivra-plugins`; a package using supported API operations can change without
rebuilding Capsule. Common execution and access belong in this repository.
Screens present those owners; Core owns identity, Ledger and relationships.
The full boundary is [Plugin Host API](plugins/plugin_host_api_v1.md).

## Maintained 1.x Development Routes

Paths below are entry points, not a second class inventory. Follow calls and
imports from the named owner with `rg`; add a route only for a distinct owner
journey. Contracts and acceptance status are linked in the sections below.

| Task / owner action | Entry point -> canonical execution owner | Focused checks |
| --- | --- | --- |
| Change identity, Ledger or relationship semantics | [FFI composition](../platform/hivra-ffi/src/lib.rs) -> [engine](../engine/hivra-engine/src/lib.rs) / [Core](../core/hivra-core/src/lib.rs); Core validates state transitions | Core/engine Rust tests; [FFI tests](../platform/hivra-ffi/src/tests.rs) for changed bindings |
| Open or switch Capsule | [Selector screen](../flutter/lib/screens/capsule_selector_screen.dart) -> [selector service](../flutter/lib/services/capsule_selector_service.dart); [app runtime](../flutter/lib/services/app_runtime_service.dart) composes activation | [Selector](../flutter/test/capsule_selector_service_test.dart), [bootstrap](../flutter/test/capsule_runtime_bootstrap_service_test.dart) |
| Export or recover Capsule | [Backup screen](../flutter/lib/screens/backup_screen.dart) / [recovery screen](../flutter/lib/screens/recovery_screen.dart) -> [backup](../flutter/lib/services/backup_service.dart) / [recovery](../flutter/lib/services/recovery_service.dart) -> FFI/Core | [Backup/recovery](../flutter/test/capsule_backup_recovery_test.dart), [backup service](../flutter/test/backup_service_test.dart), [recovery service](../flutter/test/recovery_service_test.dart) |
| Send an invitation or Chat message | [Invitation intent](../flutter/lib/services/invitation_intent_handler.dart) / [Chat delivery](../flutter/lib/services/capsule_chat_delivery_service.dart) -> [delivery lifecycle](../flutter/lib/services/capsule_delivery_lifecycle_service.dart); [address service](../flutter/lib/services/capsule_address_service.dart) owns card writes and peer routing shared with pair attestations; Core validates relationship facts | [Addressing](../flutter/test/capsule_address_service_test.dart), [invitation intent](../flutter/test/invitation_intent_handler_test.dart), [Chat delivery](../flutter/test/capsule_chat_delivery_service_test.dart), [attestation exchange](../flutter/test/consensus_attestation_exchange_service_test.dart), [delivery lifecycle](../flutter/test/capsule_delivery_lifecycle_service_test.dart) |
| Install, update or remove a package | [Plugins screen](../flutter/lib/screens/wasm_plugins_screen.dart) -> [catalog](../flutter/lib/services/wasm_plugin_source_catalog_service.dart) -> [registry](../flutter/lib/services/wasm_plugin_registry_service.dart); file import converges at the same registry | [Catalog](../flutter/test/wasm_plugin_source_catalog_service_test.dart), [registry](../flutter/test/wasm_plugin_registry_service_test.dart), [activation](../flutter/test/wasm_plugin_workspace_activation_test.dart) |
| Connect a plugin, grant access or revoke it | [Workspace screen](../flutter/lib/screens/plugin_workspace_screen.dart) -> [workspace runtime](../flutter/lib/services/plugin_workspace_runtime.dart); [secret vault](../flutter/lib/services/capsule_scoped_secret_vault.dart) owns credential custody | [Workspace](../flutter/test/plugin_workspace_test.dart), [secret vault](../flutter/test/capsule_scoped_secret_vault_test.dart) |
| Change common API execution or scheduling | Owner action / scheduled wake -> [workspace runtime](../flutter/lib/services/plugin_workspace_runtime.dart) -> [WASM binding](../flutter/lib/services/plugin_host_api_service.dart) -> [capability dispatcher](../flutter/lib/services/plugin_capability_dispatcher.dart); results return to WASM | [Workspace](../flutter/test/plugin_workspace_test.dart), [host API](../flutter/test/plugin_host_api_service_test.dart), [WASM runtime](../flutter/test/wasm_plugin_runtime_service_test.dart) |
| Change Analyst or plugin inference | [Analyst screen](../flutter/lib/screens/capsule_doctor_screen.dart) / workspace `ai.infer` -> [AI runtime](../flutter/lib/services/capsule_ai_runtime_service.dart) -> [provider adapter](../flutter/lib/services/inference_provider_adapter.dart) | [AI runtime](../flutter/test/capsule_ai_runtime_service_test.dart), [inspection](../flutter/test/ai_capsule_inspection_service_test.dart), [provider adapter](../flutter/test/inference_provider_adapter_test.dart) |
| Start, revoke or recover remote execution / server identity | [App composition](../flutter/lib/services/plugin_runtime_module_service.dart) -> [remote custody/transport](../flutter/lib/services/plugin_workspace_remote_service.dart) -> [headless runner](../flutter/bin/plugin_workspace_runner.dart); app and runner share the workspace runtime | [Workspace](../flutter/test/plugin_workspace_test.dart), [real-WASM headless probe](../flutter/test/fixtures/plugin_workspace_headless_probe.dart) |
| Change Jack or Moltbook product behavior | [External package repository](https://github.com/WSorr/hivra-plugins), through the [common API](plugins/plugin_host_api_v1.md); Chat also uses the specialized relationship/delivery path above | Package tests and existing real-WASM probes; replacement/revocation checks in workspace tests; exact-package acceptance when required |

For generic workspace navigation, start at the workspace screen and its
[activation tests](../flutter/test/wasm_plugin_workspace_activation_test.dart).
Source layout by layer is in the [root README](../README.md#repository-layout).

## Canon

| Concern | Owner |
| --- | --- |
| Current state, accepted debt boundaries, next decision and development workflow | [Development control](development-control.md) |
| Person-First ownership, participation, replaceability and the three laws | [Product axis](product-axis.md) |
| Maintained 1.x protocol, Core-only Capsule backup and legacy recovery | [Specification](specification.md) |
| Product terminology | [Conceptual model](hivra-conceptual-model.md) |
| Milestone index and retained debt | [Milestone index](roadmap.md) |

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
| Transport delivery and receipts | [Delivery lifecycle](architecture/transport-delivery-lifecycle.md) |
| External effects | [Effect lifecycle](architecture/external-effect-lifecycle.md) |
| Plugin installation, replacement, fail-closed registry cleanup and restart-safe removal | [Package lifecycle](architecture/plugin-package-lifecycle.md) |
| Unified protocol-2 operation catalog, owner connections, optional storage and workspace boundary; specialized v1 contracts and outstanding migration | [Plugin Host API](plugins/plugin_host_api_v1.md) |
| Capsule-scoped secrets, first connection, native custody and removal failure/retry | [Secret lifecycle](architecture/capsule-scoped-secret-lifecycle.md) |
| Capsule AI Runtime, replaceable compute boundary, disclosure and session unlock | [AI runtime](architecture/capsule-ai-runtime.md) |
| AI proposal boundary | [Proposal boundary](architecture/ai-proposal-boundary.md) |
| Continuous Ledger v5 | [Ledger protocol](architecture/continuous-ledger-protocol-v5.md) |
| Identity migration | [Identity migration](identity-decoupling-migration.md) |
| Capsule addressing | [Addressing model](capsule-addressing-model.md) |
| Android seed migration | [Seed migration](android-keystore-migration.md) |
| Toolchain evolution | [Toolchain contract](platform-toolchain-evolution.md) |
| Jack product brief, new Start and restart recovery | [Trading brief](plugins/trading-plugin-mvp.md) |
| Moltbook stateless workflow, history and recovery limits | [Moltbook lifecycle](plugins/moltbook_engagement_lifecycle_v1.md) |
| External package source, catalog trust and version independence | [External plugin source](plugins/external_plugin_source.md) |

Moltbook and Jack use the common workspace contract. Chat retains its
relationship-scoped specialized contract; do not describe that remaining host
binding as a completed generic capability. Current versions and acceptance
limits belong to `development-control.md`, not this map.

## Design-Only V2 and Generated Inventory

[V2 blueprint](architecture-v2-blueprint.md) and its contracts are design-only
until explicitly activated. They do not select work for the maintained 1.x
runtime.

The [ownership registry](../architecture/ownership-registry.v1.json) is the
machine-readable inventory. Its [generated report](generated/architecture-ownership-baseline.md)
contains current code ownership and V2 migration closure verdicts. Those
verdicts are not release acceptance or an active backlog. Read the corresponding
contract's status before using it; do not edit the generated report manually.

## Verification

Checklists and generated evidence verify contracts; they do not create product
requirements or current status. Use only the checklist matching the changed
risk under `checklists/`.

Run the focused tests for the changed owner first, then the required validation
ladder in `development-control.md`. Repository checks are run with
`tools/review/review_all.sh`. Packaging and publication have one existing path:
[release tools](../tools/release/README.md) and
[exact-artifact signoff](checklists/release-manual-signoff-log.md).
Documentation-only changes need link/path checks and repository gates; they
do not require a new application build or a live plugin cycle.

Every implementation pass must leave a traceable chain:

`current evidence -> owner journey/model -> mechanism/contract -> code -> focused tests -> review gates -> exact packaged smoke`

Stop at the last step required by the change. A green gate without the user
journey it is meant to protect is incomplete evidence.

Research under `research/` and `external-agent-runtime-pattern-audit.md` is
non-authorizing input.
