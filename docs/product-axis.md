# Hivra Product Axis

Hivra is a **Person-First Runtime (PFR)**. The Capsule is the person's durable,
recoverable execution context. Applications, devices, models, providers,
transports, and execution hosts are replaceable capabilities around it.

The maintained 1.x runtime evolves toward an installable capability system. A
plugin installation must be able to add product behavior without rebuilding
the application. Hivra 2.0 may replace the visual shell, but it must reuse the
proven Core, Ledger, Runtime API, and capability contracts rather than create a
second system.

## Person-First Design Basis

The person owns continuity, identity, signed history and personal relationships.
Applications and service accounts are ways to act in a wider network; they do
not define the person's architectural boundary. Hivra enables compatible
participation in existing infrastructure, with the person choosing executors
and accepting responsibility for delegated actions, budgets and data disclosure.

Local contexts may differ across a person's devices without creating a new
external identity or an obligation to merge or synchronize their histories.
Whether to transfer, retain or continue a context is an owner decision subject
to authentic history and preservation of existing data. This is a design
requirement, not a claim that every such journey is implemented in 1.x.

Owner intent, delegated execution and mutual agreement are distinct. A package,
model or remote executor does not inherit all owner authority. A relationship
involves another independent owner; its Core rules and required pair evidence
cannot be replaced by a local UI permission or a global application status.
Within these boundaries, supported local choices do not require a second
application-level policy that decides what the owner is allowed to prefer.

The host enforces identity/scope binding, secret custody, resource bounds and
the exact authorized effects. The owner and capability package determine
product behavior. Editorial rules, service choices and reference-plugin UI
assumptions must not become permanent host restrictions merely because they
were useful in one application. Every restriction needs a named protected
property, a concrete failure case and one responsible enforcement boundary.

Replacing an executor and erasing owner data are separate intentions. Retention,
credential revocation and deletion must follow the owner's declared lifecycle
choice. Current uninstall, recovery and storage limitations remain documented
1.x contracts until deliberately replaced; this principle does not silently
change their behavior or permit unverified restoration or authority renewal.

Continuity does not require indefinite retention of every capability's content.
An owner-selected cache may evict completed data according to its declared
budget; that does not erase Core identity, relationships or Ledger facts.
State verifiably available from a provider may be reacquired after reconnection.
Preserve only the local intent/evidence still needed for unresolved delivery or
effects and any non-reconstructible data covered by the chosen retention policy.
A missing remote result is not proof that an earlier request was never accepted.

Use the existing runtime ability across authorized packages before adding a
feature-specific host path. Compatible model/provider changes belong in
configuration or replaceable executors. New protocols or genuinely missing
platform abilities may require a host extension. Technical libraries implement
these mechanisms; their application, tenant or coordination model is not an
architectural requirement for Hivra.

Current limitations and selected work belong to `development-control.md`;
implemented wire and persistence behavior belongs to `specification.md`.

## The Three Laws

### Law 1: Domain truth belongs only to Ledger and Core projections

Confirmed Capsule history is an append-only Ledger fact sequence. Core is the
only interpreter of that history. UI, plugins, transports, adapters, caches,
and external providers may hold input or evidence, but they do not create a
parallel truth or independently reinterpret domain events.

### Law 2: Dependencies point strictly downward

Stable contracts point toward Core and capability boundaries. Composition
stays at the application edge. UI does not call raw platform APIs, Core does
not know adapters, plugins do not reach credentials or provider sessions, and
adapters do not make product decisions.

### Law 3: One action has one owner and one canonical result path

One semantic command, domain transition, delivery, or external effect has one
owner, one stable identity, and one lifecycle across retry, timeout, restart,
reconnect, and Capsule switching. A replacement removes or seals the path it
supersedes.

## Target Runtime Shape

Capsule owns identity, owner authority and personal relationships. Isolated
plugins supply the person's capabilities. Core remains small and knows no
installed product; the host supplies the technical means to exercise the
owner's permissions rather than another implementation of each product.

```text
App Shell
  -> Person Runtime API / Plugin Host
       -> Core + Ledger
       -> canonical projections
       -> plugin-scoped state
       -> Delivery and Effect capabilities
       -> credential handles
       -> provider and platform adapters
  -> installed capability packages
       -> Chat
       -> Moltbook
       -> Trading
```

The App Shell owns Capsule selection, plugin installation, navigation, and
presentation. It does not own plugin business logic. A plugin owns its
state machine, service protocol, decisions, response interpretation and
reconciliation rules. The Runtime API owns access enforcement and technical
execution through shared network, crypto, credential, scheduling, presentation
and optional opaque-storage capabilities. Core and Ledger know no product
plugin by name. The target and current API differences have one owner:
`plugins/plugin_host_api_v1.md`.

An owner's Start can authorize an autonomous workflow, including operation
while the owner is absent. Host access checks enforce that choice; they do not
repeat the package's strategy decisions or require approval for every step.
The host does not infer new authority from successful execution or a service
response. Isolation, credential scope and revocation remain enforced.

Ledger is authoritative for Hivra domain facts, not a replica of an exchange
account or another service. A package obtains service facts from that service.
It retains only the settings and irrecoverable decisions needed for continuity;
the host may store those bytes without interpreting their private meaning.
Provider observations and receipts do not become Core facts.

The product capability targets are:

1. Chat gives a person a usable cross-device conversation with durable
   delivery, receipt, deduplication and restart continuity of its retained
   local window. Its accepted cache budget and eviction journey belong to
   `development-control.md`; a permanent complete message archive is not a
   Core requirement.
2. Moltbook turns permitted changes and conversations into original proposals,
   bounded publications and replies, with visible receipts and recovery.
3. Trading lets a person configure and run one bounded
   remote session without terminal work, then follow each managed order
   through its actual provider state without duplicate effects. Its product
   brief is `plugins/trading-plugin-mvp.md`. Availability and acceptance belong
   to `development-control.md`, not this target architecture.

Within supported host capabilities, replacing a package must replace its
decisions, settings and workspace without rebuilding the App Shell. The host
does not select strategy evidence or interpret private plugin state. A genuinely
new system primitive may require one host capability extension. A new service
protocol, strategy, response format or private state shape using supported
primitives must be replaceable in the package.

The selected maintained capability first reaches its complete 1.x user journey
on its existing canonical effect path. Tests prove semantics; packaged and,
where applicable, live evidence prove the journey. A running service,
accepted order, prepared draft, or green gate is intermediate evidence, not
completion. A new capability requires an explicit product decision and a
minimal host boundary, not restoration of a retired host implementation. Do
not copy unfinished Flutter orchestration into a plugin or create a universal
agent, intent, DTO, or mandate runtime in advance. The active outcome and its
release blocker are recorded only in `development-control.md`.

## Version Boundary

Hivra 1.x is the only maintained and releasable runtime. Product-led
pluginization happens there. Hivra 2.0 remains design-only until an explicit
implementation decision selects its new UI and composition shell. Neither
line may create a second Core, Ledger, truth projection, delivery lifecycle, or
effect route.

V2 design may make these laws mechanically stricter in response to proven 1.x
failure modes. It may not rename, reorder, or replace them with a second set of
architectural principles.
