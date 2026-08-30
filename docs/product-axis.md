# Hivra Product Axis

Hivra is a **Person-First Runtime (PFR)**. The Capsule is the person's durable,
recoverable execution context. Applications, devices, models, providers,
transports, and execution hosts are replaceable capabilities around it.

The maintained 1.x runtime evolves toward an installable capability system. A
plugin installation must be able to add product behavior without rebuilding
the application. Hivra 2.0 may replace the visual shell, but it must reuse the
proven Core, Ledger, Runtime API, and capability contracts rather than create a
second system.

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
deterministic state machine, decisions, and reconciliation rules. The Runtime
API owns bounded access to projections, storage, delivery, effects, and
credentials. Core and Ledger know no product plugin by name.

The three current product capabilities migrate vertically:

1. Chat proves durable delivery, receipt, deduplication, offline operation, and
   restart continuity.
2. Moltbook proves observation, AI proposal, policy, publication, receipt, and
   reconciliation.
3. Trading proves market observation, deterministic decision, bounded mandate,
   one-event/one-effect execution, restart reconciliation, and remote runtime.

Each migration keeps proven code where it is already correctly owned, moves
plugin semantics behind the Runtime API, and deletes the replaced host path in
the same product pass. No universal agent, intent, DTO, or mandate runtime is
created in advance.

## Version Boundary

Hivra 1.x is the only maintained and releasable runtime. Product-led
pluginization happens there. Hivra 2.0 remains design-only until an explicit
implementation decision selects its new UI and composition shell. Neither
line may create a second Core, Ledger, truth projection, delivery lifecycle, or
effect route.
