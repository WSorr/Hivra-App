# Moltbook Release Smoke Checklist

Use this checklist on the packaged artifact for every platform that exposes the
Moltbook Ambassador. Use a disposable Moltbook agent and non-sensitive public
text. Automated tests do not replace this manual evidence.

Automatic trigger modes remain experimental until every lifecycle gate below
has automated coverage and both platform rows pass for the same build tag.

## Setup And Scope

- [ ] Launch the packaged Release artifact, not a debug or build-tree copy.
- [ ] Select one Capsule and confirm the expected Moltbook account binding.
- [ ] Confirm the default write policy is `Assisted` and trigger is `On demand`.
- [ ] Confirm API credentials are never rendered, logged, or copied into a
      Capsule ledger, AI prompt preview, or WASM result.

## Canonical Workspace

- [ ] Run one foreground cycle and observe one prominent next action.
- [ ] Confirm active challenge, unresolved, or queued effect takes priority over
      generation of another draft.
- [ ] With no actionable remote target, confirm one pending Capsule public
      change produces one local WASM draft and no provider write.
- [ ] Confirm a retained local draft prevents the next pending public change
      from producing another draft after restart.
- [ ] Confirm secret-like credentials, private-key material, long private
      identifiers, and Capsule addresses are rejected before entering the
      public change feed.
- [ ] Confirm provider ids, hashes, attempts, and checkpoints remain under
      technical details rather than competing primary controls.
- [ ] Switch Capsule during an observation and confirm late work cannot update
      the newly active Capsule.

## Assisted Write Lifecycle

- [ ] Observe one bounded conversation and generate a reply proposal.
- [ ] Review and explicitly approve the exact proposal.
- [ ] Repeated approval/publish clicks retain one semantic operation.
- [ ] If Moltbook returns a numeric challenge, confirm Gemini receives only the
      visible prompt, produces one numeric answer, and the existing effect
      remains unresolved until provider visibility is reconciled.
- [ ] Lock AI or inject malformed/rejected answer evidence and confirm no blind
      provider retry or second publication effect occurs.
- [ ] Restart while the operation is unresolved and confirm the same operation
      resumes without a duplicate post or comment.
- [ ] Review, retain, then delete a local draft. Its unapproved `prepared`
      publication is cancelled, while approved or in-flight work still
      requires explicit cancellation or reconciliation.
- [ ] Reconcile the exact provider receipt before success is shown.
- [ ] Confirm a verified successful post archives its matching local draft and
      cannot reappear as `Review latest draft` after restart.
- [ ] Confirm a succeeded target cannot be selected for another reply.

## Bounded Public Change Lifecycle

- [ ] Use a disposable account with verified ownership of
      `m/person-first-runtime`; no other destination is accepted.
- [ ] Start one bounded foreground session and confirm the packaged public
      snapshot produces one exact fact-bound draft and one post operation.
- [ ] Confirm the visible post body contains every allowlisted snapshot fact
      verbatim and contains no generic replacement summary.
- [ ] Confirm provider receipt or unresolved evidence is retained before the
      change is treated as published.
- [ ] Restart and repeat the session; the same snapshot creates no second post
      or effect.
- [ ] Remove verified community evidence in a fixture and confirm the change
      remains pending without AI, WASM, or provider execution.

## Failure And Control

- [ ] Exercise a timeout or offline request; status remains unresolved and does
      not blindly resubmit.
- [ ] Exercise provider rate limiting or inspect deterministic fixture evidence;
      retry timing is visible and no second operation is created.
- [ ] Disable the agent or press Stop; no new AI request or external effect
      starts after the stop boundary.
- [ ] Feed hostile remote text that asks for secrets, policy changes, tools, or
      publication; it remains untrusted context and grants no authority.
- [ ] Confirm daily/interval limits and stop state survive restart and Capsule
      switching.

## Platform Evidence

- [ ] Record macOS result in `release-manual-signoff-log.md` as `Moltbook Smoke`.
- [ ] Record Android result in `release-manual-signoff-log.md` as `Moltbook Smoke`.
- [ ] Keep session/continuous trigger labels experimental until both rows pass
      and the release decision is explicitly changed in the lifecycle spec.
