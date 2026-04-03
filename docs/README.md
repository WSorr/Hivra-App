# Hivra Docs Map

This folder contains the canonical project documentation for Hivra v1.0.0.

## Documents

### 1) `specification.md` (normative)
Use this as the source of truth for implementation and review.

Contains:
- protocol architecture and dependency rules
- Core/Engine/Transport boundaries
- domain events, invariants, serialization rules
- role and network rules
- UI Screen Contract requirements

If there is any conflict, `specification.md` wins.

### 2) `hivra-conceptual-model.md` (product model)
Use this to understand product intent, user-facing mechanics, and behavior scenarios.

Contains:
- conceptual framing of Capsules/Starters/Relationships
- invitation mechanics and edge-case behavior
- relay and trust model from product perspective
- documentation/comment language policy rationale

This document must stay consistent with `specification.md`.

### 3) `roadmap.md` (engineering priorities)
Use this to track the current engineering direction and the highest-value stabilization work.

Contains:
- replay safety priorities
- persist/import reliability work
- device migration safety
- release discipline and preflight expectations
- medium-term architecture and plugin-host work

### 4) `android-keystore-migration.md` (implementation note)
Use this when working on Android seed-storage hardening.

Contains:
- current Android storage debt
- target keystore-backed storage model
- migration path for existing Android users
- implementation constraints and rollout checkpoints

### 5) `identity-decoupling-migration.md` (implementation note)
Use this when working on canonical capsule identity and transport-key separation.

Contains:
- current legacy coupling between capsule identity and Nostr identity
- target root-identity model
- phased migration plan
- upgrade-safety decision points and constraints

### 6) `capsule-addressing-model.md` (design note)
Use this when working on peer addressing after root identity became canonical.

Contains:
- why `v1.0.0` send worked with one visible key
- why root identity alone is not enough for remote routing
- the public capsule card model
- trusted peer records and encrypted endpoint updates

### 7) `checklists/user-lifetime-safety-pack.md` (release safety checklist)
Use this to validate the real-world user path (one or two capsules across long-term use, restore, and update).

Contains:
- first capsule birth stability
- first relationship creation flow
- recovery-on-clean-runtime verification
- update truth-preservation checks
- pending invitation stability checks

### 8) `architecture-execution-discipline.md` (architecture execution standard)
Use this when introducing/refactoring modules and async flows.

Contains:
- the three non-negotiable architecture laws
- execution-path contract (`intent -> effect -> ledger -> projection`)
- effect and async resolution discipline
- module creation checklist and refactor acceptance criteria

## Recommended Reading Order

1. `specification.md`
2. `hivra-conceptual-model.md`
3. `roadmap.md`
4. `android-keystore-migration.md` when touching Android seed storage
5. `identity-decoupling-migration.md` when touching root identity or transport key derivation
6. `capsule-addressing-model.md` when touching invitation addressing or peer endpoint resolution
7. `checklists/user-lifetime-safety-pack.md` when preparing release candidates
8. `architecture-execution-discipline.md` when designing/refactoring module boundaries and async behavior

## Update Rules

- Any protocol, invariant, event, or UI contract change must update `specification.md` in the same PR.
- If product behavior/flows are affected, update `hivra-conceptual-model.md` in the same PR.
- Keep terminology consistent: Capsule, Starter, Invitation, Relationship, Ledger, Network.
- All product-bound documentation and code comments must be in English.

## Quick PR Checklist

- Architecture/dependency rules still valid
- Invariants still valid
- Event set and payload fields still valid
- UI contract still valid
- Conceptual flows and exceptional cases updated (if behavior changed)
