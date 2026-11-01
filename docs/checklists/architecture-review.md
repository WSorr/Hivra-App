# Architecture Review Checklist

Use this checklist only for a structural change. A focused capability contract
and its tests own detailed protocol, storage, security, and lifecycle rules.
Apply the design basis in `../product-axis.md` and the model-first workflow in
`../development-control.md`. Answer these checks in the existing review;
do not create another report or gate for routine work.

## Owner Journey And Model

- [ ] The gained capability and what remains the person's after executor
      replacement are explicit; a working reference app alone is insufficient.
- [ ] Acceptance matches the selected debt's recorded retention, permitted
      eviction/reconnection and non-goals; tests have not silently expanded it.
- [ ] Necessary states, transitions, invariants and authority were identified
      before choosing a library or application pattern.
- [ ] Restrictions have a concrete failure case and a canonical enforcement
      owner; owner preferences and current limits are not labelled Core laws.
- [ ] Credible alternative mechanisms and a falsifying experiment were
      considered where the decision is nontrivial.
- [ ] Different local contexts are not forced into a new identity or a merge
      without a product requirement; existing history is preserved.

## The Three Laws

- [ ] Confirmed domain truth is written only as a Ledger/Core fact and read
      through a canonical Core projection.
- [ ] Dependencies still point downward; composition remains at the App Shell
      or platform edge.
- [ ] The changed action, transition, delivery, or effect has one owner, one
      stable identity, and one canonical result path.
- [ ] A replacement removes or seals the path it supersedes.

## Core And Ledger

- [ ] Core remains deterministic and free of network, filesystem, UI, clock,
      RNG, credential, and provider dependencies.
- [ ] UI, plugins, transports, adapters, and caches do not replay raw events to
      create another domain interpretation.
- [ ] `CurrentView`, `PairView`, and `HistoryView` are consumed according to
      their declared scope.
- [ ] Import, replay, recovery, and migration preserve immutable history and
      owner binding.
- [ ] Capsule identity remains separate from transport identity and concrete
      cryptographic key sizes.

## Runtime API And Plugins

- [ ] Product behavior enters through one capability contract rather than a
      screen-owned service graph.
- [ ] Installed plugins receive only declared capabilities and cannot access
      raw credentials, transport sessions, arbitrary storage, or Core mutation.
- [ ] Plugin state is Capsule-scoped, bounded and versioned. Executor removal,
      owner-data erasure and credential revocation follow their explicit
      lifecycle contract, with retention/deletion scope visible to the owner.
- [ ] Product policy remains owner/package-owned. A reference provider, field,
      editorial rule or UI lifetime has not become an unrelated host restriction.
- [ ] Transport adapters move authenticated envelopes but do not interpret
      Chat, invitation, consensus, Moltbook, or Trading semantics.
- [ ] Service protocol, response parsing and workflow belong to the package;
      shared host operations enforce access and execute requests. Existing v1
      exceptions are identified through `../plugins/plugin_host_api_v1.md`.
- [ ] Plugin source and release bytes remain owned by the separate
      `hivra-plugins` repository.

## Delivery And Effects

- [ ] Stable event or operation identity survives timeout, retry, restart,
      reconnect, refresh, and Capsule switching.
- [ ] Necessary pending intent survives dispatch/restart without a duplicate
      host account history; reconstructible observations remain disposable.
- [ ] Timeout or missing receipt remains ambiguous and enters reconciliation;
      it is not converted to success or a safe retry automatically.
- [ ] Duplicate input cannot create a second active semantic effect.
- [ ] Passive and manual triggers converge on the same lifecycle owner.
- [ ] An autonomous grant needs no repeated product approvals. Revocation and
      package isolation still stop new unauthorized dispatches; already sent
      actions are not represented as undone.
- [ ] Full bounded storage produces visible backpressure rather than silent
      loss or eviction of another retained operation.

## Secrets And AI

- [ ] Credentials have one Capsule-scoped owner and are exposed only through a
      bounded handle or adapter call.
- [ ] AI output remains an untrusted proposal; deterministic capability policy
      owns approval and effect eligibility.
- [ ] A locked AI session stops before inference and creates no external
      effect.
- [ ] Root signing, transport signing, transport encryption, and provider
      credentials remain separate roles.

## Evidence

- [ ] The focused regression test includes failure and negative mutation cases
      for the changed boundary.
- [ ] Restart, duplicate, stale completion, Capsule switch, and corruption
      cases are selected when relevant.
- [ ] macOS and Android evidence is required only when packaged behavior or a
      platform boundary changed.
- [ ] `tools/review/review_all.sh` and `git diff --check` pass.
- [ ] Added and removed owners, result paths, DTO conversions, and dependency
      edges are reported; green tests alone do not justify structural growth.
