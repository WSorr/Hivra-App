# Capsule Analyst Release Smoke Checklist

Use this checklist for release-candidate builds that change Capsule Analyst,
the shared inference session, or the installed Plugin Auditor.

## Live Inference Availability

Successful live model output is optional release evidence. A missing API key,
exhausted quota, rate limit or provider outage does not block release when the
required local checks below pass. Record the reason for not exercising live
inference in the signoff Notes; do not describe skipped inference as passed.

Credential isolation, Capsule binding, locked-session rejection, redaction,
bounded output and failure handling remain mandatory offline regression tests.
On the packaged artifact, verify the local diagnostics, outbound preview,
read-only audit and safe behavior when inference is locked or unavailable.

## Capsule Analyst

- [ ] Capsule Analyst opens from Settings.
- [ ] Deterministic diagnostics render without mutating Capsule state.
- [ ] Copy snapshot produces a redacted payload only.
- [ ] No repository, patch, scaffold, or developer controls are present.

## Scoped AI Analysis

- [ ] Inference provider and model are selected explicitly.
- [ ] Provider credentials use provider-isolated secure storage.
- [ ] After restart the provider remains configured while the process AI
      session is locked.
- [ ] If a provider key is configured, explicit unlock restores the credential
      session without re-entering the API key; successful model output is not
      required.
- [ ] A request prepared for another Capsule fails before provider dispatch.
- [ ] Outbound preview is shown before provider submission.
- [ ] Locked or unavailable inference leaves Capsule, plugins, and local files
      unchanged; a visible provider failure is not a successful analysis.

## Installed Plugin Auditor

- [ ] Installed package audit renders package digest, ABI, entry export, and
      declared capability evidence.
- [ ] Audit remains read-only and cannot grant capabilities or mutate the
      plugin registry.
