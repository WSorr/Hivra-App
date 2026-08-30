# Capsule Analyst Release Smoke Checklist

Use this checklist for release-candidate builds that change Capsule Analyst,
the shared inference session, or the installed Plugin Auditor.

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
- [ ] Explicit unlock restores inference without re-entering the API key.
- [ ] A request prepared for another Capsule fails before provider dispatch.
- [ ] Outbound preview is shown before provider submission.
- [ ] Provider failure leaves Capsule, plugins, and local files unchanged.

## Installed Plugin Auditor

- [ ] Installed package audit renders package digest, ABI, entry export, and
      declared capability evidence.
- [ ] Audit remains read-only and cannot grant capabilities or mutate the
      plugin registry.
